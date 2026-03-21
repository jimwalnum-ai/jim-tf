"""
Infrastructure Observability Dashboard

Monitors EKS pods/deployments/nodes, Nomad jobs/allocations,
and AWS resources (SQS, RDS, CloudWatch alarms). Fires SNS
alerts when problems are detected.
"""

import fnmatch
import json
import logging
import os
import re
import threading
import time
from datetime import datetime, timezone

import boto3
import requests
from flask import Flask, render_template, jsonify
from kubernetes import client as k8s_client, config as k8s_config

app = Flask(__name__)

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("observability")

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
CLUSTER_NAME = os.environ.get("CLUSTER_NAME", "unknown")
NOMAD_ADDR = os.environ.get("NOMAD_ADDR", "")
SQS_QUEUE_NAMES = [q.strip() for q in os.environ.get("SQS_QUEUE_NAMES", "").split(",") if q.strip()]
FACTOR_TS_NAMESPACE = os.environ.get("FACTOR_TS_NAMESPACE", "factor-ts")
RDS_INSTANCE_ID = os.environ.get("RDS_INSTANCE_ID", "")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "10"))
NOMAD_IGNORED_DEAD_JOBS = {
    j.strip()
    for j in os.environ.get("NOMAD_IGNORED_DEAD_JOBS", "").split(",")
    if j.strip()
}
LOG_TAIL_BYTES = int(os.environ.get("LOG_TAIL_BYTES", "16384"))
BASELINE_WINDOW = int(os.environ.get("BASELINE_WINDOW", "10"))
VOLUME_SPIKE_FACTOR = float(os.environ.get("VOLUME_SPIKE_FACTOR", "3.0"))

# Suppress noisy alerts. Comma-separated rules in "source:component_glob" format.
# Glob patterns (fnmatch) are matched against the problem's component field.
_DEFAULT_SUPPRESSED = ",".join([
    "nomad-logs:logs/factor-process/*",
    "nomad-logs:logs/factor-persist/*",
    "sqs:queue/SQS_FACTOR_DEV",
    "nomad:eval/factor-persist/*",
    "nomad:eval/factor-process/*",
])
_suppressed_rules: list[tuple[str, str]] = []
for _rule in os.environ.get("SUPPRESSED_ALERTS", _DEFAULT_SUPPRESSED).split(","):
    _rule = _rule.strip()
    if ":" in _rule:
        _src, _pat = _rule.split(":", 1)
        _suppressed_rules.append((_src.strip(), _pat.strip()))


def _is_suppressed(problem: dict) -> bool:
    src = problem.get("source", "")
    comp = problem.get("component", "")
    for rule_src, rule_pat in _suppressed_rules:
        if src == rule_src and fnmatch.fnmatch(comp, rule_pat):
            return True
    return False

_cache = {}
_cache_lock = threading.Lock()
_alert_cooldowns: dict[str, float] = {}

HISTORY_WINDOW_SECONDS = 1800  # 30 minutes
_problem_history: list[dict] = []
_history_lock = threading.Lock()

# Per-task rolling baseline for anomaly detection.
# Key: "job/task_group/task"  Value: list of recent poll snapshots
_log_baselines: dict[str, list[dict]] = {}
_baseline_lock = threading.Lock()

ALERT_COOLDOWN_SECONDS = 300

sns = boto3.client("sns", region_name=AWS_REGION) if SNS_TOPIC_ARN else None
cw = boto3.client("cloudwatch", region_name=AWS_REGION)
sqs = boto3.client("sqs", region_name=AWS_REGION)
rds = boto3.client("rds", region_name=AWS_REGION)


# ---------------------------------------------------------------------------
# Kubernetes checks
# ---------------------------------------------------------------------------

def _init_k8s():
    try:
        k8s_config.load_incluster_config()
    except k8s_config.ConfigException:
        k8s_config.load_kube_config()


def check_kubernetes():
    problems = []
    summary = {"pods_total": 0, "pods_healthy": 0, "pods_unhealthy": 0,
               "deployments_total": 0, "deployments_healthy": 0, "deployments_unhealthy": 0,
               "nodes_total": 0, "nodes_ready": 0, "nodes_not_ready": 0,
               "warning_events": 0}
    try:
        v1 = k8s_client.CoreV1Api()
        apps_v1 = k8s_client.AppsV1Api()

        # Pods
        pods = v1.list_pod_for_all_namespaces(limit=500)
        for pod in pods.items:
            summary["pods_total"] += 1
            phase = pod.status.phase
            ns = pod.metadata.namespace
            name = pod.metadata.name

            restart_count = 0
            if pod.status.container_statuses:
                for cs in pod.status.container_statuses:
                    restart_count += cs.restart_count
                    if cs.state and cs.state.waiting:
                        reason = cs.state.waiting.reason or ""
                        if reason in ("CrashLoopBackOff", "OOMKilled", "ImagePullBackOff", "ErrImagePull"):
                            problems.append({
                                "source": "kubernetes",
                                "severity": "CRITICAL" if reason == "OOMKilled" else "HIGH",
                                "component": f"pod/{ns}/{name}",
                                "message": f"Container {cs.name}: {reason}",
                            })
                    if cs.state and cs.state.terminated:
                        reason = cs.state.terminated.reason or ""
                        if reason == "OOMKilled":
                            problems.append({
                                "source": "kubernetes",
                                "severity": "CRITICAL",
                                "component": f"pod/{ns}/{name}",
                                "message": f"Container {cs.name}: OOMKilled",
                            })

            if phase in ("Running", "Succeeded"):
                summary["pods_healthy"] += 1
            else:
                summary["pods_unhealthy"] += 1
                if phase == "Failed":
                    problems.append({
                        "source": "kubernetes",
                        "severity": "HIGH",
                        "component": f"pod/{ns}/{name}",
                        "message": f"Pod in {phase} state",
                    })

            if restart_count > 5:
                problems.append({
                    "source": "kubernetes",
                    "severity": "MEDIUM",
                    "component": f"pod/{ns}/{name}",
                    "message": f"High restart count: {restart_count}",
                })

        # Deployments
        deps = apps_v1.list_deployment_for_all_namespaces()
        for dep in deps.items:
            summary["deployments_total"] += 1
            ns = dep.metadata.namespace
            name = dep.metadata.name
            desired = dep.spec.replicas or 0
            available = dep.status.available_replicas or 0
            if available >= desired:
                summary["deployments_healthy"] += 1
            else:
                summary["deployments_unhealthy"] += 1
                problems.append({
                    "source": "kubernetes",
                    "severity": "HIGH",
                    "component": f"deploy/{ns}/{name}",
                    "message": f"Unavailable replicas: {desired - available}/{desired}",
                })

        # Nodes
        nodes = v1.list_node()
        for node in nodes.items:
            summary["nodes_total"] += 1
            ready = False
            for cond in (node.status.conditions or []):
                if cond.type == "Ready" and cond.status == "True":
                    ready = True
                if cond.type in ("MemoryPressure", "DiskPressure", "PIDPressure") and cond.status == "True":
                    problems.append({
                        "source": "kubernetes",
                        "severity": "HIGH",
                        "component": f"node/{node.metadata.name}",
                        "message": f"{cond.type} detected",
                    })
            if ready:
                summary["nodes_ready"] += 1
            else:
                summary["nodes_not_ready"] += 1
                problems.append({
                    "source": "kubernetes",
                    "severity": "CRITICAL",
                    "component": f"node/{node.metadata.name}",
                    "message": "Node NotReady",
                })

        # Warning events (last 1h of field-selector is tricky; just grab recent)
        events = v1.list_event_for_all_namespaces(
            field_selector="type=Warning",
            limit=100,
        )
        summary["warning_events"] = len(events.items)
        for ev in events.items[:10]:
            problems.append({
                "source": "kubernetes",
                "severity": "LOW",
                "component": f"event/{ev.involved_object.namespace}/{ev.involved_object.name}",
                "message": f"{ev.reason}: {ev.message[:120] if ev.message else ''}",
            })

    except Exception as exc:
        log.exception("Kubernetes check failed")
        problems.append({
            "source": "kubernetes",
            "severity": "CRITICAL",
            "component": "api",
            "message": f"K8s API unreachable: {exc}",
        })

    return {"summary": summary, "problems": problems}


# ---------------------------------------------------------------------------
# Nomad checks
# ---------------------------------------------------------------------------

def check_nomad():
    problems = []
    summary = {"jobs_total": 0, "jobs_running": 0, "jobs_dead": 0,
               "allocs_total": 0, "allocs_running": 0, "allocs_failed": 0,
               "reachable": False}

    if not NOMAD_ADDR:
        return {"summary": summary, "problems": [{
            "source": "nomad", "severity": "LOW",
            "component": "config", "message": "NOMAD_ADDR not configured",
        }]}

    try:
        health = requests.get(f"{NOMAD_ADDR}/v1/agent/health", timeout=5)
        summary["reachable"] = health.status_code == 200

        if not summary["reachable"]:
            problems.append({
                "source": "nomad", "severity": "CRITICAL",
                "component": "agent", "message": f"Nomad agent unhealthy (HTTP {health.status_code})",
            })
            return {"summary": summary, "problems": problems}

        # Jobs
        jobs = requests.get(f"{NOMAD_ADDR}/v1/jobs", timeout=10).json()
        for job in jobs:
            summary["jobs_total"] += 1
            status = job.get("Status", "")
            if status == "running":
                summary["jobs_running"] += 1
            elif status == "dead":
                summary["jobs_dead"] += 1
                stop = job.get("Stop", False)
                is_periodic_child = bool(job.get("ParentID"))
                job_name = job.get("Name", "")
                parent_name = job_name.split("/periodic-")[0] if "/periodic-" in job_name else job_name
                explicitly_ignored = parent_name in NOMAD_IGNORED_DEAD_JOBS or job_name in NOMAD_IGNORED_DEAD_JOBS
                if not stop and not is_periodic_child and not explicitly_ignored:
                    problems.append({
                        "source": "nomad",
                        "severity": "HIGH",
                        "component": f"job/{job_name}",
                        "message": f"Job is dead (not stopped intentionally)",
                    })

        # Allocations
        allocs = requests.get(f"{NOMAD_ADDR}/v1/allocations", params={"resources": "false"}, timeout=10).json()
        for alloc in allocs:
            summary["allocs_total"] += 1
            cs = alloc.get("ClientStatus", "")
            if cs == "running":
                summary["allocs_running"] += 1
            elif cs in ("failed", "lost"):
                summary["allocs_failed"] += 1
                alloc_job = alloc.get("JobID", "?")
                alloc_parent = alloc_job.split("/periodic-")[0] if "/periodic-" in alloc_job else alloc_job
                if alloc_parent in NOMAD_IGNORED_DEAD_JOBS or alloc_job in NOMAD_IGNORED_DEAD_JOBS:
                    continue
                problems.append({
                    "source": "nomad",
                    "severity": "HIGH" if cs == "failed" else "MEDIUM",
                    "component": f"alloc/{alloc_job}/{alloc['ID'][:8]}",
                    "message": f"Allocation {cs}",
                })

        # Evaluations with blocked or failed status
        evals = requests.get(f"{NOMAD_ADDR}/v1/evaluations", params={"status": "blocked"}, timeout=10).json()
        for ev in (evals or []):
            problems.append({
                "source": "nomad",
                "severity": "MEDIUM",
                "component": f"eval/{ev.get('JobID', '?')}/{ev['ID'][:8]}",
                "message": f"Blocked evaluation: {ev.get('StatusDescription', '')}",
            })

    except Exception as exc:
        log.exception("Nomad check failed")
        problems.append({
            "source": "nomad", "severity": "CRITICAL",
            "component": "api", "message": f"Nomad API error: {exc}",
        })

    return {"summary": summary, "problems": problems}


# ---------------------------------------------------------------------------
# Nomad log anomaly detection
# ---------------------------------------------------------------------------

_FINGERPRINT_REPLACEMENTS = [
    (re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I), "<UUID>"),
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b"), "<IP>"),
    (re.compile(r"\b[0-9a-f]{12,}\b", re.I), "<HEX>"),
    (re.compile(r"\d{4}[-/]\d{2}[-/]\d{2}[T ]\d{2}:\d{2}:\d{2}[^\s]*"), "<TS>"),
    (re.compile(r"\b\d+\.\d+(?:s|ms|us|µs|ns)?\b"), "<NUM>"),
    (re.compile(r"\b\d{2,}\b"), "<N>"),
]


def _fingerprint(line: str) -> str:
    """Collapse a log line into a structural fingerprint by replacing variable parts."""
    fp = line.strip()
    for pattern, repl in _FINGERPRINT_REPLACEMENTS:
        fp = pattern.sub(repl, fp)
    return fp


def _get_running_allocs() -> list[dict]:
    resp = requests.get(
        f"{NOMAD_ADDR}/v1/allocations",
        params={"filter": 'ClientStatus == "running"', "resources": "false"},
        timeout=10,
    )
    resp.raise_for_status()
    allocs = []
    for a in resp.json():
        task_states = a.get("TaskStates") or {}
        for task_name in task_states:
            allocs.append({
                "alloc_id": a["ID"],
                "job": a.get("JobID", "?"),
                "task_group": a.get("TaskGroup", "?"),
                "task": task_name,
                "node_id": a.get("NodeID", ""),
            })
    return allocs


def _fetch_task_log(alloc_id: str, task: str, log_type: str = "stderr") -> str:
    resp = requests.get(
        f"{NOMAD_ADDR}/v1/client/fs/logs/{alloc_id}",
        params={
            "task": task,
            "type": log_type,
            "plain": "true",
            "origin": "end",
            "offset": str(LOG_TAIL_BYTES),
        },
        timeout=10,
    )
    if resp.status_code == 200:
        return resp.text
    return ""


def _analyze_task_logs(task_key: str, stderr: str, stdout: str) -> dict:
    """Compare current log fingerprints against baseline, detect anomalies."""
    current_fps: dict[str, list[str]] = {}
    line_count = 0

    for stream, text in [("stderr", stderr), ("stdout", stdout)]:
        for raw_line in text.splitlines():
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            line_count += 1
            fp = _fingerprint(raw_line)
            current_fps.setdefault(fp, []).append(raw_line)

    anomalies: list[dict] = []

    with _baseline_lock:
        history = _log_baselines.get(task_key, [])
        known_fps: set[str] = set()
        historical_volumes: list[int] = []
        for snap in history:
            known_fps.update(snap["fingerprints"])
            historical_volumes.append(snap["line_count"])

    # --- Anomaly 1: new log patterns never seen in baseline ---
    if known_fps:
        new_fps = set(current_fps.keys()) - known_fps
        for fp in new_fps:
            sample = current_fps[fp][0][:200]
            anomalies.append({
                "type": "new_pattern",
                "fingerprint": fp[:120],
                "sample": sample,
                "count": len(current_fps[fp]),
            })

    # --- Anomaly 2: volume spike ---
    if len(historical_volumes) >= 2:
        avg_vol = sum(historical_volumes) / len(historical_volumes)
        if avg_vol > 0 and line_count > avg_vol * VOLUME_SPIKE_FACTOR:
            anomalies.append({
                "type": "volume_spike",
                "fingerprint": "",
                "sample": f"Current: {line_count} lines vs baseline avg {avg_vol:.0f}",
                "count": line_count,
            })

    # --- Anomaly 3: pattern frequency spike ---
    if known_fps and history:
        recent_freq: dict[str, list[int]] = {}
        for snap in history:
            for fp, cnt in snap["freq"].items():
                recent_freq.setdefault(fp, []).append(cnt)
        for fp, lines in current_fps.items():
            if fp in recent_freq and len(recent_freq[fp]) >= 2:
                avg_cnt = sum(recent_freq[fp]) / len(recent_freq[fp])
                if avg_cnt > 0 and len(lines) > avg_cnt * VOLUME_SPIKE_FACTOR:
                    anomalies.append({
                        "type": "frequency_spike",
                        "fingerprint": fp[:120],
                        "sample": lines[0][:200],
                        "count": len(lines),
                    })

    # --- Update baseline ---
    snapshot = {
        "ts": time.time(),
        "line_count": line_count,
        "fingerprints": set(current_fps.keys()),
        "freq": {fp: len(lines) for fp, lines in current_fps.items()},
    }
    with _baseline_lock:
        history = _log_baselines.setdefault(task_key, [])
        history.append(snapshot)
        if len(history) > BASELINE_WINDOW:
            _log_baselines[task_key] = history[-BASELINE_WINDOW:]

    learning = len(history) <= 2

    return {
        "line_count": line_count,
        "unique_patterns": len(current_fps),
        "known_patterns": len(known_fps),
        "anomalies": anomalies,
        "learning": learning,
    }


def check_nomad_logs():
    """Tail logs from every running Nomad task, detect anomalies via fingerprinting."""
    problems = []
    log_findings: list[dict] = []
    summary = {
        "tasks_scanned": 0,
        "tasks_with_anomalies": 0,
        "total_anomalies": 0,
        "baseline_learning": False,
    }

    if not NOMAD_ADDR:
        return {"summary": summary, "log_findings": log_findings, "problems": []}

    try:
        allocs = _get_running_allocs()
        for entry in allocs:
            summary["tasks_scanned"] += 1
            alloc_id = entry["alloc_id"]
            task = entry["task"]
            job = entry["job"]
            task_key = f"{job}/{entry['task_group']}/{task}"

            stderr = _fetch_task_log(alloc_id, task, "stderr")
            stdout = _fetch_task_log(alloc_id, task, "stdout")

            result = _analyze_task_logs(task_key, stderr, stdout)

            if result["learning"]:
                summary["baseline_learning"] = True

            if result["anomalies"]:
                summary["tasks_with_anomalies"] += 1
                summary["total_anomalies"] += len(result["anomalies"])

                finding = {
                    "job": job,
                    "task_group": entry["task_group"],
                    "task": task,
                    "alloc_short": alloc_id[:8],
                    "line_count": result["line_count"],
                    "unique_patterns": result["unique_patterns"],
                    "anomaly_count": len(result["anomalies"]),
                    "anomalies": result["anomalies"][:8],
                    "learning": result["learning"],
                }
                log_findings.append(finding)

                if not result["learning"]:
                    has_volume = any(a["type"] == "volume_spike" for a in result["anomalies"])
                    new_count = sum(1 for a in result["anomalies"] if a["type"] == "new_pattern")
                    severity = "HIGH" if has_volume or new_count >= 3 else "MEDIUM"

                    descs = []
                    if has_volume:
                        descs.append("log volume spike")
                    if new_count:
                        descs.append(f"{new_count} new pattern(s)")
                    freq_count = sum(1 for a in result["anomalies"] if a["type"] == "frequency_spike")
                    if freq_count:
                        descs.append(f"{freq_count} frequency spike(s)")

                    sample = result["anomalies"][0]["sample"][:100]
                    problems.append({
                        "source": "nomad-logs",
                        "severity": severity,
                        "component": f"logs/{task_key}",
                        "message": f"Anomaly: {', '.join(descs)} — {sample}",
                    })

    except Exception as exc:
        log.warning("Nomad log check failed: %s", exc)
        problems.append({
            "source": "nomad-logs",
            "severity": "MEDIUM",
            "component": "logs/api",
            "message": f"Unable to fetch Nomad logs: {exc}",
        })

    return {"summary": summary, "log_findings": log_findings, "problems": problems}


# ---------------------------------------------------------------------------
# AWS SQS checks
# ---------------------------------------------------------------------------

def check_sqs():
    problems = []
    queues = []

    for queue_name in SQS_QUEUE_NAMES:
        try:
            url_resp = sqs.get_queue_url(QueueName=queue_name)
            queue_url = url_resp["QueueUrl"]
            attrs = sqs.get_queue_attributes(
                QueueUrl=queue_url,
                AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible",
                                "ApproximateNumberOfMessagesDelayed"],
            )["Attributes"]

            visible = int(attrs.get("ApproximateNumberOfMessages", 0))
            in_flight = int(attrs.get("ApproximateNumberOfMessagesNotVisible", 0))
            delayed = int(attrs.get("ApproximateNumberOfMessagesDelayed", 0))

            queues.append({
                "name": queue_name,
                "visible": visible,
                "in_flight": in_flight,
                "delayed": delayed,
                "total": visible + in_flight + delayed,
            })

            if visible > 10000:
                problems.append({
                    "source": "sqs", "severity": "HIGH",
                    "component": f"queue/{queue_name}",
                    "message": f"Queue depth critical: {visible:,} messages",
                })
            elif visible > 1000:
                problems.append({
                    "source": "sqs", "severity": "MEDIUM",
                    "component": f"queue/{queue_name}",
                    "message": f"Queue depth elevated: {visible:,} messages",
                })

        except Exception as exc:
            log.warning("SQS check failed for %s: %s", queue_name, exc)
            problems.append({
                "source": "sqs", "severity": "MEDIUM",
                "component": f"queue/{queue_name}",
                "message": f"Unable to query queue: {exc}",
            })

    return {"queues": queues, "problems": problems}


# ---------------------------------------------------------------------------
# AWS RDS checks
# ---------------------------------------------------------------------------

def check_rds():
    problems = []
    instances = []

    if not RDS_INSTANCE_ID:
        return {"instances": instances, "problems": []}

    try:
        resp = rds.describe_db_instances(DBInstanceIdentifier=RDS_INSTANCE_ID)
        for db in resp["DBInstances"]:
            status = db["DBInstanceStatus"]
            engine = db.get("Engine", "")
            instance_class = db.get("DBInstanceClass", "")
            storage = db.get("AllocatedStorage", 0)
            multi_az = db.get("MultiAZ", False)

            instances.append({
                "id": db["DBInstanceIdentifier"],
                "status": status,
                "engine": f"{engine} {db.get('EngineVersion', '')}",
                "instance_class": instance_class,
                "storage_gb": storage,
                "multi_az": multi_az,
            })

            if status != "available":
                problems.append({
                    "source": "rds", "severity": "CRITICAL",
                    "component": f"rds/{db['DBInstanceIdentifier']}",
                    "message": f"Instance status: {status}",
                })

    except Exception as exc:
        log.warning("RDS check failed: %s", exc)
        problems.append({
            "source": "rds", "severity": "HIGH",
            "component": "rds/api",
            "message": f"Unable to describe RDS: {exc}",
        })

    return {"instances": instances, "problems": problems}


# ---------------------------------------------------------------------------
# CloudWatch alarm checks
# ---------------------------------------------------------------------------

def check_cloudwatch_alarms():
    problems = []
    alarms = []

    try:
        resp = cw.describe_alarms(StateValue="ALARM", MaxRecords=50)
        for alarm in resp.get("MetricAlarms", []):
            alarms.append({
                "name": alarm["AlarmName"],
                "state": alarm["StateValue"],
                "reason": alarm.get("StateReason", "")[:200],
                "metric": alarm.get("MetricName", ""),
                "namespace": alarm.get("Namespace", ""),
            })
            problems.append({
                "source": "cloudwatch", "severity": "HIGH",
                "component": f"alarm/{alarm['AlarmName']}",
                "message": f"ALARM: {alarm.get('StateReason', '')[:120]}",
            })

        resp2 = cw.describe_alarms(StateValue="INSUFFICIENT_DATA", MaxRecords=20)
        for alarm in resp2.get("MetricAlarms", []):
            alarms.append({
                "name": alarm["AlarmName"],
                "state": alarm["StateValue"],
                "reason": alarm.get("StateReason", "")[:200],
                "metric": alarm.get("MetricName", ""),
                "namespace": alarm.get("Namespace", ""),
            })

    except Exception as exc:
        log.warning("CloudWatch check failed: %s", exc)
        problems.append({
            "source": "cloudwatch", "severity": "MEDIUM",
            "component": "cloudwatch/api",
            "message": f"Unable to query alarms: {exc}",
        })

    return {"alarms": alarms, "problems": problems}


# ---------------------------------------------------------------------------
# TypeScript Factor Pod checks
# ---------------------------------------------------------------------------

def check_factor_ts():
    """Monitor pods in the factor-ts namespace — process, persist, and test-msg workloads."""
    problems = []
    summary = {
        "pods_total": 0, "pods_running": 0, "pods_failed": 0,
        "deployments_total": 0, "deployments_healthy": 0, "deployments_unhealthy": 0,
        "cronjobs_total": 0, "cronjobs_active": 0,
        "namespace": FACTOR_TS_NAMESPACE,
    }
    pods_detail: list[dict] = []

    try:
        v1 = k8s_client.CoreV1Api()
        apps_v1 = k8s_client.AppsV1Api()
        batch_v1 = k8s_client.BatchV1Api()

        pods = v1.list_namespaced_pod(namespace=FACTOR_TS_NAMESPACE)
        for pod in pods.items:
            summary["pods_total"] += 1
            phase = pod.status.phase
            name = pod.metadata.name
            restart_count = 0
            container_ready = True

            if pod.status.container_statuses:
                for cs in pod.status.container_statuses:
                    restart_count += cs.restart_count
                    if not cs.ready:
                        container_ready = False
                    if cs.state and cs.state.waiting:
                        reason = cs.state.waiting.reason or ""
                        if reason in ("CrashLoopBackOff", "OOMKilled", "ImagePullBackOff", "ErrImagePull"):
                            problems.append({
                                "source": "factor-ts",
                                "severity": "CRITICAL" if reason == "OOMKilled" else "HIGH",
                                "component": f"pod/{name}",
                                "message": f"Container {cs.name}: {reason}",
                            })

            pod_info = {
                "name": name,
                "phase": phase,
                "ready": container_ready and phase == "Running",
                "restarts": restart_count,
                "app": pod.metadata.labels.get("app", ""),
            }
            pods_detail.append(pod_info)

            if phase in ("Running", "Succeeded"):
                summary["pods_running"] += 1
            else:
                summary["pods_failed"] += 1
                if phase == "Failed":
                    problems.append({
                        "source": "factor-ts",
                        "severity": "HIGH",
                        "component": f"pod/{name}",
                        "message": f"Pod in {phase} state",
                    })

            if restart_count > 5:
                problems.append({
                    "source": "factor-ts",
                    "severity": "MEDIUM",
                    "component": f"pod/{name}",
                    "message": f"High restart count: {restart_count}",
                })

        deps = apps_v1.list_namespaced_deployment(namespace=FACTOR_TS_NAMESPACE)
        for dep in deps.items:
            summary["deployments_total"] += 1
            name = dep.metadata.name
            desired = dep.spec.replicas or 0
            available = dep.status.available_replicas or 0
            if available >= desired:
                summary["deployments_healthy"] += 1
            else:
                summary["deployments_unhealthy"] += 1
                problems.append({
                    "source": "factor-ts",
                    "severity": "HIGH",
                    "component": f"deploy/{name}",
                    "message": f"Unavailable replicas: {desired - available}/{desired}",
                })

        crons = batch_v1.list_namespaced_cron_job(namespace=FACTOR_TS_NAMESPACE)
        for cj in crons.items:
            summary["cronjobs_total"] += 1
            if cj.status.active:
                summary["cronjobs_active"] += len(cj.status.active)

    except Exception as exc:
        log.warning("Factor TS check failed: %s", exc)
        problems.append({
            "source": "factor-ts",
            "severity": "MEDIUM",
            "component": "api",
            "message": f"Unable to query factor-ts namespace: {exc}",
        })

    return {"summary": summary, "pods": pods_detail, "problems": problems}


# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------

def _fire_alerts(all_problems):
    if not sns or not SNS_TOPIC_ARN:
        return

    critical = [p for p in all_problems if p["severity"] in ("CRITICAL", "HIGH")]
    if not critical:
        return

    now = time.time()
    to_alert = []
    for p in critical:
        key = f"{p['source']}:{p['component']}:{p['severity']}"
        last = _alert_cooldowns.get(key, 0)
        if now - last > ALERT_COOLDOWN_SECONDS:
            to_alert.append(p)
            _alert_cooldowns[key] = now

    if not to_alert:
        return

    body = f"Observability Alert — {CLUSTER_NAME} ({AWS_REGION})\n\n"
    for p in to_alert:
        body += f"[{p['severity']}] {p['source']} / {p['component']}\n  {p['message']}\n\n"

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{to_alert[0]['severity']}] Observability: {len(to_alert)} issue(s) in {CLUSTER_NAME}",
            Message=body,
        )
        log.info("Sent SNS alert with %d issues", len(to_alert))
    except Exception as exc:
        log.warning("SNS publish failed: %s", exc)


# ---------------------------------------------------------------------------
# Collector
# ---------------------------------------------------------------------------

def _stamp_problems(problems: list[dict]) -> list[dict]:
    """Add an ISO-8601 UTC timestamp to every problem that lacks one."""
    now = datetime.now(timezone.utc).isoformat()
    for p in problems:
        if "timestamp" not in p:
            p["timestamp"] = now
    return problems


def _update_history(new_problems: list[dict]) -> list[dict]:
    """Append new problems and prune entries older than 30 minutes."""
    cutoff = time.time() - HISTORY_WINDOW_SECONDS
    with _history_lock:
        _problem_history.extend(new_problems)
        _problem_history[:] = [
            p for p in _problem_history
            if datetime.fromisoformat(p["timestamp"]).timestamp() > cutoff
        ]
        return list(_problem_history)


def collect_all():
    k8s = check_kubernetes()
    nomad = check_nomad()
    nomad_logs = check_nomad_logs()
    sqs_data = check_sqs()
    rds_data = check_rds()
    cw_data = check_cloudwatch_alarms()
    factor_ts = check_factor_ts()

    current_problems = [
        p for p in (
            k8s["problems"]
            + nomad["problems"]
            + nomad_logs["problems"]
            + sqs_data["problems"]
            + rds_data["problems"]
            + cw_data["problems"]
            + factor_ts["problems"]
        )
        if not _is_suppressed(p)
    ]
    _stamp_problems(current_problems)

    all_history = _update_history(current_problems)

    severity_order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFO": 4}
    current_problems.sort(key=lambda p: severity_order.get(p["severity"], 5))
    all_history.sort(key=lambda p: severity_order.get(p.get("severity", "INFO"), 5))

    overall = "healthy"
    for p in current_problems:
        if p["severity"] == "CRITICAL":
            overall = "critical"
            break
        if p["severity"] == "HIGH":
            overall = "degraded"

    result = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "cluster": CLUSTER_NAME,
        "region": AWS_REGION,
        "overall_status": overall,
        "kubernetes": k8s,
        "nomad": nomad,
        "nomad_logs": nomad_logs,
        "sqs": sqs_data,
        "rds": rds_data,
        "cloudwatch": cw_data,
        "factor_ts": factor_ts,
        "all_problems": current_problems,
        "all_problems_30m": all_history,
        "problem_count": len(current_problems),
        "problem_count_30m": len(all_history),
        "critical_count": sum(1 for p in current_problems if p["severity"] == "CRITICAL"),
        "high_count": sum(1 for p in current_problems if p["severity"] == "HIGH"),
    }

    _fire_alerts(current_problems)

    with _cache_lock:
        _cache["data"] = result

    return result


def _background_poller():
    while True:
        try:
            collect_all()
            log.info("Poll complete — %d problems", _cache.get("data", {}).get("problem_count", 0))
        except Exception:
            log.exception("Poller error")
        time.sleep(POLL_INTERVAL)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    with _cache_lock:
        data = _cache.get("data")
    if data is None:
        data = collect_all()
    return render_template("index.html", data=data)


@app.route("/api/status")
def api_status():
    with _cache_lock:
        data = _cache.get("data")
    if data is None:
        data = collect_all()
    return jsonify(data)


@app.route("/api/refresh")
def api_refresh():
    data = collect_all()
    return jsonify(data)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "region": AWS_REGION, "cluster": CLUSTER_NAME})


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

def _startup():
    _init_k8s()
    t = threading.Thread(target=_background_poller, daemon=True)
    t.start()


_startup()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
