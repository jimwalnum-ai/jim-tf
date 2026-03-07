"""
Cilium Security Dashboard

Reads security agent reports from S3 and serves a web interface
for browsing incidents, viewing trends, and inspecting raw alerts.
"""

import json
import os
from datetime import datetime, timedelta, timezone
from functools import lru_cache

import boto3
from flask import Flask, render_template, jsonify, request, abort

app = Flask(__name__)

S3_BUCKET = os.environ["S3_BUCKET"]
REPORTS_PREFIX = os.environ.get("REPORTS_PREFIX", "security-reports/")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
CLUSTER_NAME = os.environ.get("CLUSTER_NAME", "unknown")

s3 = boto3.client("s3", region_name=AWS_REGION)

SEVERITY_RANK = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "INFO": 0}


def list_reports(days: int = 7) -> list[dict]:
    """List report metadata from the last N days, most recent first."""
    now = datetime.now(timezone.utc)
    reports = []

    for day_offset in range(days):
        day = now - timedelta(days=day_offset)
        prefix = f"{REPORTS_PREFIX}{day:%Y/%m/%d}/"
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                filename = key.rsplit("/", 1)[-1]
                reports.append({
                    "key": key,
                    "filename": filename,
                    "last_modified": obj["LastModified"].isoformat(),
                    "size": obj["Size"],
                })

    reports.sort(key=lambda r: r["last_modified"], reverse=True)
    return reports


def get_report(key: str) -> dict:
    """Fetch and parse a single report from S3."""
    try:
        resp = s3.get_object(Bucket=S3_BUCKET, Key=key)
        return json.loads(resp["Body"].read())
    except s3.exceptions.NoSuchKey:
        abort(404)


def compute_stats(reports_data: list[dict]) -> dict:
    """Aggregate stats across a batch of loaded reports."""
    total_runs = len(reports_data)
    clean_runs = sum(1 for r in reports_data if r.get("status") == "clean")
    alert_runs = total_runs - clean_runs

    severity_counts = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "INFO": 0}
    total_flows = 0
    all_incidents = []

    for report in reports_data:
        total_flows += report.get("flows_analyzed", 0)
        for inc in report.get("analysis", {}).get("incidents", []):
            sev = inc.get("severity", "INFO").upper()
            severity_counts[sev] = severity_counts.get(sev, 0) + 1
            all_incidents.append({
                **inc,
                "report_timestamp": report.get("timestamp", ""),
            })

    return {
        "total_runs": total_runs,
        "clean_runs": clean_runs,
        "alert_runs": alert_runs,
        "total_flows": total_flows,
        "severity_counts": severity_counts,
        "recent_incidents": sorted(
            all_incidents,
            key=lambda i: SEVERITY_RANK.get(i.get("severity", "INFO").upper(), 0),
            reverse=True,
        )[:50],
    }


# ─── Routes ──────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    days = int(request.args.get("days", 7))
    report_metas = list_reports(days=days)

    reports_data = []
    for meta in report_metas[:200]:
        try:
            reports_data.append(get_report(meta["key"]))
        except Exception:
            continue

    stats = compute_stats(reports_data)

    return render_template(
        "index.html",
        cluster=CLUSTER_NAME,
        stats=stats,
        report_metas=report_metas[:100],
        days=days,
    )


@app.route("/report")
def report_detail():
    key = request.args.get("key", "")
    if not key or not key.startswith(REPORTS_PREFIX):
        abort(400)
    report = get_report(key)
    return render_template("report.html", cluster=CLUSTER_NAME, report=report, key=key)


@app.route("/api/reports")
def api_reports():
    days = int(request.args.get("days", 7))
    return jsonify(list_reports(days=days))


@app.route("/api/report")
def api_report():
    key = request.args.get("key", "")
    if not key or not key.startswith(REPORTS_PREFIX):
        abort(400)
    return jsonify(get_report(key))


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
