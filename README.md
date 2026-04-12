# Terraform Infrastructure

This repository contains the Terraform configurations for a multi-region AWS infrastructure spanning **us-east-1** and **us-west-2**. The platform is purpose-built to support **high-throughput data pipeline and ML inference workloads** — sustaining 1,000 messages per second on cost-optimized instances while maintaining data sovereignty through private networking (AWS Network Firewall, Transit Gateway inspection routing, and VPC-contained traffic). Security and compliance controls (CloudTrail, IAM least-privilege, KMS encryption) are first-class, not afterthoughts.

## Cloud Sandbox Constraints

This infrastructure is designed to run in a **cloud sandbox environment** with limited resources and relaxed security controls. As a result:

- **No TLS certificates** — HTTPS/TLS termination is not configured. Services communicate over plaintext HTTP within the VPC.
- **No WAF or advanced firewall rules** — Web Application Firewall and fine-grained network ACLs are omitted.
- **No secrets rotation or Vault integration** — Credentials are managed through Terraform variables and SSM Parameter Store rather than a dedicated secrets manager with automatic rotation.
- **Self-signed or no certificates on internal endpoints** — EKS API, RDS, and inter-service traffic do not enforce certificate validation.
- **Instance count and size are intentionally limited** — Compute is restricted to smaller instance types (e.g., `t3.medium`, `t4g.small`) and minimal node/replica counts to stay within sandbox quotas and keep costs low.
- **No multi-AZ RDS or HA NAT gateways** — High-availability configurations are skipped to reduce resource consumption.
- **No production-grade monitoring or alerting thresholds** — Alarms and dashboards exist but are tuned for demonstration, not production SLAs.
- **kube-prometheus-stack Grafana password is a placeholder** — `changeme` is set in `app/eks_prometheus.tf`; replace with a sealed secret before promoting to production.

These trade-offs are acceptable for a sandbox but should be addressed before promoting to a production environment.

## Directory Overview

### Infrastructure Root Modules

| Directory | Region | Description |
|---|---|---|
| `bootstrap/` | us-east-1 | One-time account setup: S3 state bucket, DynamoDB lock table, IAM roles, CloudTrail |
| `foundation/` | us-east-1 | Core networking and shared infrastructure: VPC, IPAM, Route53, Network Firewall, EC2, S3/SQS |
| `foundation-west/` | us-west-2 | West-region networking: VPC, IPAM, KMS |
| `nomad/` | us-east-1 | HashiCorp Nomad/Consul cluster: servers, clients, ALB, jobs for factor workloads |
| `app/` | us-east-1 | Primary application stack: EKS cluster, RDS PostgreSQL, ECR repositories, K8s workloads, Prometheus/Grafana (kube-prometheus-stack) |
| `app-west/` | us-west-2 | Secondary application stack: EKS cluster, VPC peering to east for cross-region RDS access |
| `global/` | multi-region | Cross-region resources: ECR replication, Route53 health checks and DNS failover |


### Shared Modules

| Directory | Description |
|---|---|
| `modules/vpc` | VPC, subnets, route tables, NAT gateways, flow logs |
| `modules/eks` | EKS cluster, node groups, OIDC provider, security groups |
| `modules/transit-gateway` | Transit Gateway and inspection routing |
| `modules/tgw-route-tables` | Transit Gateway route tables, spoke/inspection attachments and propagation |
| `modules/transit-egress-vpc` | Egress VPC with public/private subnets, NAT gateways, NACLs, flow logs |
| `modules/inspect-vpc` | Inspection VPC for AWS Network Firewall |
| `modules/kms` | KMS encryption keys |
| `modules/s3` | S3 buckets |
| `modules/route53` | Private hosted zones |
| `modules/ipam` | IPAM pools |

### SRE Documentation

| Directory | Description |
|---|---|
| `docs/runbooks/` | Operational runbooks and SLO definitions — see [eks-node-notready.md](infrastructure/docs/runbooks/eks-node-notready.md) and [slo-definitions.md](infrastructure/docs/runbooks/slo-definitions.md) |

### Application Code (non-Terraform)

| Directory | Description |
|---|---|
| `code/` | Python scripts, Docker and GitLab CI config for factor workloads |
| `code-ts/` | TypeScript factor workloads — parallel pipeline using separate SQS queues (`SQS_FACTOR_TS_DEV`), EKS pods, and Nomad jobs |
| `web/` | Flask web app — built and pushed to ECR by `app/web.tf` |
| `security-agent/` | Python security agent — deployed to EKS via `app/` and `app-west/` |
| `security-dashboard/` | Python security dashboard — deployed to EKS via `app/` and `app-west/` |
| `observability-dashboard/` | Infrastructure observability dashboard — monitors EKS, Nomad, SQS, RDS, CloudWatch alarms, and TypeScript factor pods with alerting via SNS |
| `common/` | Shared variable definitions (symlinked) |

## Deployment Order

Run the Terraform root modules in the following order. Each step must complete before moving to the next.

```
1. bootstrap
   │
2. foundation ──────────── foundation-west
   │                           │
4. nomad (uses foundation VPC and app RDS credentials)
   |
3. app ─────────────────── app-west
   |
5. global (reads state from foundation, app, and app-west)

```

### Step-by-step

1. **`bootstrap/`** — Run first. Creates the S3 backend bucket, DynamoDB lock table, IAM roles, and CloudTrail. All other modules depend on this backend.

2. **`foundation/`** and **`foundation-west/`** — Provisions VPCs, subnets, IPAM, Route53 zones, KMS keys, and Network Firewall. `foundation-west` can run in parallel with or after `foundation` (no cross-dependency).

3. **`app/`** then **`app-west/`** — Deploys EKS clusters, RDS, ECR repos, and Kubernetes workloads. **`app/` must be applied before `app-west/`** because `app-west` reads remote state from `app` for RDS credentials, ECR image URLs, and VPC peering targets.

4. **`global/`** — Sets up ECR replication from us-east-1 to us-west-2 and Route53 failover routing. Reads remote state from `foundation`, `app`, and `app-west`, so all three must exist first.

5. **`nomad/`** — Deploys the Nomad/Consul cluster. Depends on the `foundation` VPC and `app` RDS credentials, so both must be applied first. Can run in parallel with `global`.
