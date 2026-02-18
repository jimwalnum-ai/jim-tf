# foundation
`foundation/` is the starting point for this Terraform collection and sets up the backend and other aws needed infra


# basics
`basics/` is the starting point for this Terraform collection and contains a simple, end-to-end example stack (VPC, EC2, SQS, Route53, and supporting resources). Start here to understand the conventions and shared variables used across the repository.




## Repository layout
- `basics/`: Minimal baseline stack used as the learning/verification path.
- `foundation/`: Account-level foundation (state backend, IAM roles, CloudTrail).
- `app/`: Application stacks built on top of the foundation; Sets up ECS to run python for factor program
- `modules/`: Reusable modules (VPC, S3, KMS, IPAM, transit gateway, etc.).
- `common/`: Shared variables and values referenced by multiple stacks.
- `code/`: Helper scripts and utilities used by some stacks.

## How to use
Each top-level folder (`basics`, `foundation`, `app`) is a standalone Terraform root.

```sh
terraform init
terraform plan
terraform apply
```



