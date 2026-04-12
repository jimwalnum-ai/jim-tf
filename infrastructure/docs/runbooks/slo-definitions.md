# SLO Definitions

This document defines Service Level Objectives for the platform. Each SLO links
to the Prometheus/Grafana recording rules that implement it and to the runbook
that on-call engineers should follow when the error budget is burning.

---

## Conventions

| Term | Definition |
|---|---|
| **SLI** | Service Level Indicator — the measured signal |
| **SLO** | Service Level Objective — the target threshold for the SLI |
| **Error budget** | `1 - SLO` over the rolling window; consumed by bad minutes |
| **Burn rate** | Rate at which the error budget is being consumed relative to the window |

All windows are **30-day rolling** unless otherwise noted.

---

## SLO 1 — API Availability

**Service:** EKS-hosted web API (`web` deployment, `app/` module)  
**Owner:** Platform / SRE

| | Value |
|---|---|
| **SLI** | `sum(rate(http_requests_total{job="web",code!~"5.."}[5m])) / sum(rate(http_requests_total{job="web"}[5m]))` |
| **SLO** | ≥ 99.5 % of requests return a non-5xx response over the rolling 30-day window |
| **Error budget** | 0.5 % → ~216 minutes of downtime per 30 days |
| **Alert: page** | Burn rate > 14.4× for 5 min (fast burn — consumes 2 % budget in 1 h) |
| **Alert: ticket** | Burn rate > 1× for 6 h (slow burn) |
| **Runbook** | [eks-node-notready.md](./eks-node-notready.md) for node-level causes; see also web-deployment.md |

### Grafana Dashboard

`Dashboards → Platform → API Golden Signals` — "Availability (30d)" panel.

---

## SLO 2 — Factor Pipeline End-to-End Latency

**Service:** SQS → EKS factor worker → SQS result queue (TypeScript pipeline)  
**Owner:** Data Platform

| | Value |
|---|---|
| **SLI** | 95th-percentile message processing latency (time from SQS enqueue to result enqueue) |
| **SLO** | p95 latency ≤ 2 000 ms over any 1-hour window |
| **Error budget** | 5 % of windows may exceed threshold |
| **Alert: page** | p99 > 5 000 ms sustained for 10 min |
| **Alert: ticket** | p95 > 2 000 ms sustained for 30 min |
| **Runbook** | See `docs/runbooks/factor-pipeline-latency.md` (TODO) |

### Key Metrics

```promql
# p95 factor processing latency (histogram)
histogram_quantile(0.95,
  sum(rate(factor_processing_duration_seconds_bucket[5m])) by (le)
)
```

---

## SLO 3 — RDS Availability

**Service:** PostgreSQL RDS instance (`factor` database, `app/rds.tf`)  
**Owner:** Platform / SRE

| | Value |
|---|---|
| **SLI** | Fraction of 1-minute intervals in which the RDS instance is in `available` state (sourced from CloudWatch `DatabaseConnections` metric — zero connections during a maintenance window is excluded) |
| **SLO** | ≥ 99.9 % over the rolling 30-day window |
| **Error budget** | 0.1 % → ~43 minutes per 30 days |
| **Alert: page** | RDS `available` state absent for > 2 min |
| **Alert: ticket** | RDS CPU > 80 % sustained for 15 min |
| **Runbook** | See `docs/runbooks/rds-unavailable.md` (TODO) |

---

## SLO 4 — EKS Control Plane API Latency

**Service:** Kubernetes API server  
**Owner:** Platform / SRE

| | Value |
|---|---|
| **SLI** | `apiserver_request_duration_seconds` p99, non-LIST/WATCH verbs |
| **SLO** | p99 ≤ 1 000 ms for mutating requests; p99 ≤ 500 ms for read requests |
| **Error budget** | 1 % of request-minutes may exceed threshold |
| **Alert: ticket** | p99 > 1 s for 10 min |
| **Runbook** | See `docs/runbooks/eks-api-slow.md` (TODO) |

### Key Metrics (Prometheus)

```promql
# p99 API server request latency (mutating)
histogram_quantile(0.99,
  sum(rate(apiserver_request_duration_seconds_bucket{
    verb!~"LIST|WATCH|GET"
  }[5m])) by (le, verb, resource)
)
```

---

## Error Budget Policy

1. **> 50 % budget consumed** in the first 15 days → freeze all non-critical changes; SRE reviews root causes.
2. **> 75 % budget consumed** at any point → incident declared; post-mortem required within 5 business days.
3. **Budget exhausted** → all feature work pauses until the window resets or reliability improvements are shipped and verified.

---

## Review Cadence

| Review | Frequency | Owner |
|---|---|---|
| SLO burn-rate dashboard | Weekly (SRE sync) | SRE |
| SLO target adjustment | Quarterly | SRE + Engineering leads |
| Runbook accuracy | After every P1/P2 incident | Incident commander |
