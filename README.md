# Overview
This repository contains a layered Terraform setup for building a secure AWS environment and application stack. The intent is to provide a repeatable infrastructure foundation, a baseline example stack, and an application layer that builds on both. The overall design is meant to be secure by default and align with SOC 2 Type II and ISO 27001 expectations (e.g., strong access controls, encryption, logging, and auditable infrastructure-as-code workflows).

## Repository layout
- `foundation/`: Account-level foundation (state backend, IAM roles, CloudTrail).
- `basics/`: Minimal baseline stack used as the learning/verification path (VPC, EC2, SQS, Route53, and supporting resources).
- `app/`: Application stacks built on top of the foundation and basics; sets up ECS/other app components.
- `modules/`: Reusable modules (VPC, S3, KMS, IPAM, transit gateway, etc.).
- `common/`: Shared variables and values referenced by multiple stacks.
- `code/`: Helper scripts and utilities used by some stacks.

## Build order
The Terraform roots are intended to be applied in this order:
1. `foundation/` → establishes shared account-level infrastructure and state backend.
2. `basics/` → creates a baseline network and supporting services.
3. `app/` → deploys application-specific resources on top of the foundation and basics.

## How to build
Each top-level folder (`foundation`, `basics`, `app`) is a standalone Terraform root. For each layer, run the usual Terraform workflow:

```sh
terraform init
terraform plan
terraform apply
```

Proceed in order (foundation → basics → app) so that shared state, networking, and IAM prerequisites exist before the application layer is applied.



