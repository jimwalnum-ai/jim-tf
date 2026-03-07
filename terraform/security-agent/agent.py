"""
Cilium Hubble Security Agent

Reads recent Hubble flow logs from S3, runs rule-based anomaly detection,
then sends flagged events to Amazon Bedrock (Claude) for correlation and
severity assessment. Results are published to SNS.
"""

import gzip
import io
import json
import logging
import os
import sys
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone

import boto3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

S3_BUCKET = os.environ["S3_BUCKET"]
S3_PREFIX = os.environ.get("S3_PREFIX", "hubble/logs/")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-5-haiku-20241022-v1:0")
CLUSTER_NAME = os.environ.get("CLUSTER_NAME", "unknown")
LOOKBACK_MINUTES = int(os.environ.get("LOOKBACK_MINUTES", "20"))
REPORTS_PREFIX = os.environ.get("REPORTS_PREFIX", "security-reports/")

INTERNAL_CIDRS = {"10.", "172.16.", "172.17.", "172.18.", "172.19.",
                  "172.20.", "172.21.", "172.22.", "172.23.", "172.24.",
                  "172.25.", "172.26.", "172.27.", "172.28.", "172.29.",
                  "172.30.", "172.31.", "192.168."}

SYSTEM_NAMESPACES = {"kube-system", "kube-public", "kube-node-lease",
                     "cilium", "fluent-bit"}

# DNS domains commonly used by crypto-miners, C2 frameworks, etc.
SUSPICIOUS_DNS_PATTERNS = [
    "pool.", "mining.", "coinhive", "cryptonight",
    "xmr.", "monero.", "nicehash",
]

s3 = boto3.client("s3", region_name=AWS_REGION)
sns = boto3.client("sns", region_name=AWS_REGION)
bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)


def list_recent_s3_keys(bucket: str, prefix: str, lookback: timedelta) -> list[str]:
    """Return S3 keys from the time-partitioned prefix that fall within the lookback window."""
    now = datetime.now(timezone.utc)
    start = now - lookback
    keys = []

    current = start.replace(minute=0, second=0, microsecond=0)
    while current <= now:
        hour_prefix = f"{prefix}hubble.flows/{current:%Y/%m/%d/%H}/"
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=bucket, Prefix=hour_prefix):
            for obj in page.get("Contents", []):
                if obj["LastModified"] >= start:
                    keys.append(obj["Key"])
        current += timedelta(hours=1)

    log.info("Found %d S3 objects in lookback window", len(keys))
    return keys


def read_flows_from_s3(bucket: str, keys: list[str]) -> list[dict]:
    """Download and parse gzipped JSONL flow logs from S3."""
    flows = []
    for key in keys:
        try:
            resp = s3.get_object(Bucket=bucket, Key=key)
            body = resp["Body"].read()
            if key.endswith(".gz"):
                body = gzip.decompress(body)
            for line in io.BytesIO(body):
                line = line.strip()
                if line:
                    flows.append(json.loads(line))
        except Exception:
            log.exception("Failed to read %s", key)
    log.info("Parsed %d total flow records", len(flows))
    return flows


def is_external_ip(ip: str) -> bool:
    return ip and not any(ip.startswith(c) for c in INTERNAL_CIDRS)


# ─── Rule-based detectors ────────────────────────────────────────────────────

def detect_drops(flows: list[dict]) -> list[dict]:
    """Flows with DROPPED verdict grouped by source/destination pair."""
    drops = defaultdict(list)
    for f in flows:
        if f.get("verdict") == "DROPPED":
            src = f.get("source", {})
            dst = f.get("destination", {})
            pair = (
                f"{src.get('namespace', '?')}/{src.get('pod_name', '?')}",
                f"{dst.get('namespace', '?')}/{dst.get('pod_name', '?')}",
            )
            drops[pair].append(f)

    alerts = []
    for (src, dst), records in drops.items():
        if len(records) >= 5:
            reasons = defaultdict(int)
            for r in records:
                reasons[r.get("drop_reason", "UNKNOWN")] += 1
            alerts.append({
                "rule": "high_drop_rate",
                "severity": "medium",
                "source": src,
                "destination": dst,
                "count": len(records),
                "drop_reasons": dict(reasons),
                "sample": records[0],
            })
    return alerts


def detect_unexpected_egress(flows: list[dict]) -> list[dict]:
    """App pods communicating with external IPs they haven't historically used."""
    egress_by_pod = defaultdict(set)
    alerts = []

    for f in flows:
        if f.get("traffic_direction") != "EGRESS":
            continue
        src_ns = f.get("source", {}).get("namespace", "")
        if src_ns in SYSTEM_NAMESPACES or not src_ns:
            continue

        dst_ip = f.get("IP", {}).get("destination", "")
        if is_external_ip(dst_ip):
            pod_key = f"{src_ns}/{f['source'].get('pod_name', '?')}"
            egress_by_pod[pod_key].add(dst_ip)

    for pod, ips in egress_by_pod.items():
        if len(ips) >= 5:
            alerts.append({
                "rule": "unexpected_egress",
                "severity": "high",
                "source": pod,
                "unique_external_ips": len(ips),
                "sample_ips": list(ips)[:10],
            })
    return alerts


def detect_cross_namespace(flows: list[dict]) -> list[dict]:
    """Traffic between namespaces that wouldn't normally communicate."""
    cross_ns = defaultdict(int)
    for f in flows:
        if f.get("verdict") != "FORWARDED":
            continue
        src_ns = f.get("source", {}).get("namespace", "")
        dst_ns = f.get("destination", {}).get("namespace", "")
        if (src_ns and dst_ns
                and src_ns != dst_ns
                and src_ns not in SYSTEM_NAMESPACES
                and dst_ns not in SYSTEM_NAMESPACES):
            cross_ns[(src_ns, dst_ns)] += 1

    alerts = []
    for (src_ns, dst_ns), count in cross_ns.items():
        if count >= 20:
            alerts.append({
                "rule": "cross_namespace_traffic",
                "severity": "low",
                "source_namespace": src_ns,
                "destination_namespace": dst_ns,
                "flow_count": count,
            })
    return alerts


def detect_suspicious_dns(flows: list[dict]) -> list[dict]:
    """DNS queries matching known-bad patterns (mining pools, C2, etc.)."""
    alerts = []
    for f in flows:
        l7 = f.get("l7", {})
        dns = l7.get("dns", {}) if isinstance(l7, dict) else {}
        query = dns.get("query", "").lower()
        if any(p in query for p in SUSPICIOUS_DNS_PATTERNS):
            src = f.get("source", {})
            alerts.append({
                "rule": "suspicious_dns",
                "severity": "critical",
                "source": f"{src.get('namespace', '?')}/{src.get('pod_name', '?')}",
                "query": query,
            })
    return alerts


def detect_port_scan(flows: list[dict]) -> list[dict]:
    """Single source hitting many distinct destination ports -- possible scanning."""
    ports_by_source = defaultdict(set)
    for f in flows:
        src = f.get("source", {})
        src_key = f"{src.get('namespace', '?')}/{src.get('pod_name', '?')}"
        l4 = f.get("l4", {})
        dst_port = (l4.get("TCP", {}) or l4.get("UDP", {})).get("destination_port")
        if dst_port:
            ports_by_source[src_key].add(dst_port)

    alerts = []
    for src, ports in ports_by_source.items():
        if len(ports) >= 15:
            alerts.append({
                "rule": "port_scan",
                "severity": "high",
                "source": src,
                "unique_ports": len(ports),
                "sample_ports": sorted(list(ports))[:20],
            })
    return alerts


# ─── LLM correlation ─────────────────────────────────────────────────────────

ANALYSIS_PROMPT = """\
You are a Kubernetes network security analyst. Analyze the following anomalous \
Cilium Hubble flow events from cluster "{cluster}" and produce a concise \
security assessment.

For each group of related alerts:
1. Classify the threat type (lateral movement, data exfiltration, port scan, \
DNS tunneling, policy misconfiguration, crypto mining, etc.)
2. Assign a severity: CRITICAL / HIGH / MEDIUM / LOW / INFO
3. Recommend an immediate action (block, investigate, tune policy, etc.)

If nothing looks genuinely malicious, say so — false positives are expected.

Alerts (JSON):
{alerts_json}

Respond in this exact JSON format (no markdown fences):
{{
  "summary": "1-2 sentence overall assessment",
  "incidents": [
    {{
      "title": "short title",
      "severity": "CRITICAL|HIGH|MEDIUM|LOW|INFO",
      "threat_type": "...",
      "description": "what happened and why it matters",
      "affected_workloads": ["namespace/pod", ...],
      "recommendation": "what to do next"
    }}
  ]
}}
"""


def correlate_with_llm(alerts: list[dict]) -> dict | None:
    """Send rule-based alerts to Bedrock Claude for correlation and assessment."""
    if not alerts:
        return None

    prompt = ANALYSIS_PROMPT.format(
        cluster=CLUSTER_NAME,
        alerts_json=json.dumps(alerts, indent=2, default=str),
    )

    try:
        resp = bedrock.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 2048,
                "temperature": 0.1,
                "messages": [{"role": "user", "content": prompt}],
            }),
        )
        result = json.loads(resp["body"].read())
        text = result["content"][0]["text"]
        return json.loads(text)
    except Exception:
        log.exception("Bedrock invocation failed")
        return None


# ─── Alerting ─────────────────────────────────────────────────────────────────

def publish_to_sns(analysis: dict, raw_alert_count: int) -> None:
    """Publish the LLM-correlated security report to SNS."""
    incidents = analysis.get("incidents", [])
    max_severity = "INFO"
    severity_rank = {"INFO": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4}
    for inc in incidents:
        sev = inc.get("severity", "INFO")
        if severity_rank.get(sev, 0) > severity_rank.get(max_severity, 0):
            max_severity = sev

    subject = f"[{max_severity}] Cilium Security — {CLUSTER_NAME}"
    body_lines = [
        f"Cluster: {CLUSTER_NAME}",
        f"Time: {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}",
        f"Raw alerts analysed: {raw_alert_count}",
        f"Summary: {analysis.get('summary', 'N/A')}",
        "",
    ]
    for i, inc in enumerate(incidents, 1):
        body_lines += [
            f"--- Incident {i}: {inc.get('title', 'Untitled')} ---",
            f"Severity: {inc.get('severity')}",
            f"Type: {inc.get('threat_type')}",
            f"Description: {inc.get('description')}",
            f"Workloads: {', '.join(inc.get('affected_workloads', []))}",
            f"Action: {inc.get('recommendation')}",
            "",
        ]

    message = "\n".join(body_lines)
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject[:100],
        Message=message,
    )
    log.info("Published SNS alert: %s", subject)


# ─── Report persistence ───────────────────────────────────────────────────────

def save_report_to_s3(report: dict) -> str:
    """Write the full run report to S3 so the dashboard can display it."""
    now = datetime.now(timezone.utc)
    run_id = uuid.uuid4().hex[:12]
    key = f"{REPORTS_PREFIX}{now:%Y/%m/%d}/{now:%H%M%S}-{run_id}.json"
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=json.dumps(report, indent=2, default=str).encode(),
        ContentType="application/json",
    )
    log.info("Saved report to s3://%s/%s", S3_BUCKET, key)
    return key


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    log.info("Cilium Security Agent starting — cluster=%s lookback=%dm",
             CLUSTER_NAME, LOOKBACK_MINUTES)

    now = datetime.now(timezone.utc)
    lookback = timedelta(minutes=LOOKBACK_MINUTES)
    keys = list_recent_s3_keys(S3_BUCKET, S3_PREFIX, lookback)

    if not keys:
        log.info("No flow logs found in lookback window, saving clean report")
        save_report_to_s3({
            "timestamp": now.isoformat(),
            "cluster": CLUSTER_NAME,
            "status": "clean",
            "flows_analyzed": 0,
            "raw_alerts": [],
            "analysis": {"summary": "No flow logs in lookback window.", "incidents": []},
        })
        return

    flows = read_flows_from_s3(S3_BUCKET, keys)
    if not flows:
        log.info("No flow records parsed, saving clean report")
        save_report_to_s3({
            "timestamp": now.isoformat(),
            "cluster": CLUSTER_NAME,
            "status": "clean",
            "flows_analyzed": 0,
            "raw_alerts": [],
            "analysis": {"summary": "No flow records could be parsed.", "incidents": []},
        })
        return

    log.info("Running rule-based detection on %d flows", len(flows))
    alerts = []
    alerts.extend(detect_drops(flows))
    alerts.extend(detect_unexpected_egress(flows))
    alerts.extend(detect_cross_namespace(flows))
    alerts.extend(detect_suspicious_dns(flows))
    alerts.extend(detect_port_scan(flows))

    log.info("Rule-based detection produced %d alerts", len(alerts))

    if not alerts:
        log.info("No anomalies detected, saving clean report")
        save_report_to_s3({
            "timestamp": now.isoformat(),
            "cluster": CLUSTER_NAME,
            "status": "clean",
            "flows_analyzed": len(flows),
            "raw_alerts": [],
            "analysis": {"summary": f"Analyzed {len(flows)} flows — no anomalies detected.", "incidents": []},
        })
        return

    log.info("Sending %d alerts to Bedrock for correlation", len(alerts))
    analysis = correlate_with_llm(alerts)

    if not analysis:
        log.warning("LLM correlation failed — building fallback report")
        analysis = {
            "summary": f"Rule-based detection found {len(alerts)} anomalies but LLM correlation was unavailable.",
            "incidents": [
                {
                    "title": a.get("rule", "unknown"),
                    "severity": a.get("severity", "MEDIUM").upper(),
                    "threat_type": a.get("rule", "unknown"),
                    "description": json.dumps(a, default=str),
                    "affected_workloads": [a.get("source", "unknown")],
                    "recommendation": "Investigate manually",
                }
                for a in alerts[:10]
            ],
        }

    severity_rank = {"INFO": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4}
    max_severity = "INFO"
    for inc in analysis.get("incidents", []):
        sev = inc.get("severity", "INFO")
        if severity_rank.get(sev, 0) > severity_rank.get(max_severity, 0):
            max_severity = sev

    report = {
        "timestamp": now.isoformat(),
        "cluster": CLUSTER_NAME,
        "status": "alert",
        "max_severity": max_severity,
        "flows_analyzed": len(flows),
        "raw_alerts": alerts,
        "analysis": analysis,
    }
    save_report_to_s3(report)

    actionable = [i for i in analysis.get("incidents", []) if i.get("severity") not in ("INFO",)]
    if actionable:
        publish_to_sns(analysis, len(alerts))
    else:
        log.info("All incidents assessed as INFO-level, skipping SNS notification")

    log.info("Agent run complete")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log.exception("Unhandled exception in security agent")
        sys.exit(1)
