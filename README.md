# AWS Threat Composer on ECS Fargate with Terraform

![AWS](https://img.shields.io/badge/AWS-ECS_Fargate-FF9900?style=flat&logo=amazonecs&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-IaC-844FBA?style=flat&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-2088FF?style=flat&logo=githubactions&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Containers-2496ED?style=flat&logo=docker&logoColor=white)
![Security](https://img.shields.io/badge/Security-OIDC-6DB33F?style=flat&logo=openid&logoColor=white)
![IAM](https://img.shields.io/badge/IAM-Least_Privilege-CC2936?style=flat&logo=amazoniam&logoColor=white)

## Contents

- [Introduction](#introduction)
- [Architecture Diagram](#architecture-diagram)
- [Repository Structure](#repository-structure)
- [Local App Set-up](#local-app-set-up)
- [Infrastructure Breakdown](#infrastructure-breakdown)
- [Security](#security)
- [Observability](#observability)
- [Cost & Efficiency](#cost--efficiency)
- [CI/CD Pipelines](#cicd-pipelines)
- [Bootstrapping](#bootstrapping)
- [Possible Improvements](#possible-improvements)
- [Learning and Reflections](#learning-and-reflections)

---

## Introduction

This project is based on AWS's [Threat Composer](https://awslabs.github.io/threat-composer/workspaces/default/dashboard), an open-source threat modelling tool. It helps you work out every way an attacker might exploit a system, modelled as **assumptions, threats and mitigations**, so you can identify strategies to mitigate those threats instead of starting from a blank page.

The app is containerised and hosted on **ECS Fargate** behind an HTTPS Application Load Balancer, with all infrastructure defined in Terraform and deployed through GitHub Actions.

<img width="1080" height="608" alt="Threat Composer" src="https://github.com/user-attachments/assets/211a6dec-fb41-4b13-8671-0bc4d36d457f" />

### Architecture Diagram

<img width="2258" height="1614" alt="Architecture diagram" src="https://github.com/user-attachments/assets/6272ce82-5930-4673-85ff-f24d0e659b8f" />

---

## Repository Structure

One repository, with the infrastructure and the app in sibling folders and all workflows at the root (GitHub only reads workflows from `.github/workflows/`).

```
.
├── .github/
│   └── workflows/
│       ├── docker-build-scan.yml    # Build image + Trivy scan
│       ├── docker-push.yml          # Push the scanned image to ECR
│       ├── terraform-plan.yml       # fmt / validate / tflint / checkov / trivy + plan
│       ├── terraform-apply.yml      # Apply the plan produced by terraform-plan
│       ├── terraform-destroy.yml    # Manual teardown (type "destroy" to confirm)
│       └── health-check.yml         # Poll the live URL (currently commented out)
├── .pre-commit-config.yaml          # Local hooks: fmt, validate, tflint, checkov
├── app/                             # The application + its container build
│   ├── Dockerfile                   # Multi-stage build, non-root nginx runner
│   ├── nginx.conf                   # SPA routing, gzip, caching, non-root paths
│   ├── .trivyignore                 # Documented base-image CVE exceptions
│   └── src/ public/ ...             # Threat Composer React source
└── terraform/
    ├── main.tf                      # Wires the modules together
    ├── provider.tf                  # AWS provider + S3 remote backend
    ├── variables.tf / outputs.tf
    ├── .checkov.yaml  .tflint.hcl  .trivyignore
    ├── modules/
    │   ├── vpc/                     # VPC, 2 public + 2 private subnets, IGW, route tables, VPC endpoints
    │   ├── sg/                      # ALB and ECS-service security groups
    │   ├── alb/                     # ALB, HTTP->HTTPS redirect, HTTPS listener, target group
    │   ├── acm/                     # Looks up the TLS cert + Route 53 zone, creates the alias record
    │   └── ecs/                     # Cluster, task definition, service, IAM roles, log group
    └── bootstrap/                   # One-off foundations, each with its own state
        ├── s3/                      # Remote state bucket
        ├── ecr/                     # Container registry
        ├── route53/                 # Hosted zone (prevent_destroy)
        └── github-oidc/             # IAM roles GitHub Actions assumes via OIDC
```

---

## Local App Set-up

Run from the `app/` folder (where the Dockerfile lives):

```bash
cd app

# 1) Build the image
docker build -t threat-composer:local .

# 2) Run it (host 8080 -> container 8080)
docker run --rm --name threat-composer -p 8080:8080 threat-composer:local
```

Then open <http://localhost:8080/>, or check it from the terminal:

```bash
curl -i http://localhost:8080/
```

Stop the container with:

```bash
docker stop threat-composer
```

---

## Infrastructure Breakdown

### Networking

- Custom `10.0.0.0/16` VPC across **two Availability Zones** (`eu-west-2a`, `eu-west-2b`) for high availability
- Two public subnets (the ALB) and two private subnets (the ECS tasks), with an Internet Gateway on the public route table
- ECS tasks run in the private subnets with `assign_public_ip = false`, so they are not reachable from the internet
- Security groups reference each other rather than IP ranges: the ECS service only accepts traffic from the **ALB's security group** on the container port (8080)
- The ALB redirects **HTTP -> HTTPS**, and the HTTPS listener uses the `ELBSecurityPolicy-TLS13-1-2-2021-06` policy
- There is **no NAT Gateway**. Private tasks reach AWS services over **VPC endpoints** instead (see [Cost](#cost--efficiency))

### DNS & TLS

- **Route 53** hosts the `honeycreators.com` zone; Terraform creates an alias record pointing `threat-composer.honeycreators.com` at the ALB
- **AWS Certificate Manager** provides the TLS certificate the ALB uses, at no cost
- The hosted zone, ECR repo and certificate are deliberately **outside the destroyable app stack**. The app stack only reads them with data sources, so `terraform destroy` can never take them down

### Containers & Runtime

- Multi-stage Docker build: Node builds the app, and only the static output is copied into `nginxinc/nginx-unprivileged`
- Runs as a **non-root user**, using a minimal base image to reduce the attack surface
- The task definition sets `readonlyRootFilesystem = true`; nginx's pid and temp paths are redirected to `/tmp` so it works without root
- Fargate service with `desired_count = 2` (one task per AZ), 0.25 vCPU / 512 MB, `X86_64`
- Images are pushed to **ECR** tagged with the commit SHA and `latest`

### Terraform & State

- Reusable **modules** keep the code DRY (`vpc`, `sg`, `alb`, `acm`, `ecs`)
- Remote state lives in **S3** (versioned, encrypted, public access blocked), with native **state locking** (`use_lockfile = true`) to prevent concurrent writes
- Formatting, linting, validation and security scanning run before every plan

---

## Security

- **OIDC instead of long-lived credentials.** GitHub Actions gets temporary AWS credentials per run. A leaked token is only valid for the duration of the job and the limited privileges of its role
- **Least privilege, one role per job type:**
  - *plan*: read-only, assumable from any branch or PR in this repo
  - *apply / destroy*: assumable only by jobs running in the `production` GitHub Environment
  - *ECR push*: can only push to the one `threat-composer` repository
- Trust policies use GitHub's immutable `repo:OWNER@ID/REPO@ID` subject format, so a renamed or recreated repo can't inherit access
- ECS tasks are not publicly accessible, only the ALB is
- Image scanning (Trivy) blocks publishing on fixable CRITICAL/HIGH vulnerabilities
- Terraform is scanned with **Checkov**, **Trivy** (config) and **TFLint**. Every skipped check is listed in `.checkov.yaml` / `.trivyignore` with a written justification
- Pre-commit hooks catch problems locally before they are pushed

---

## Observability

- **Container Insights** is enabled on the ECS cluster for CPU/memory/task metrics
- Container stdout/stderr ships to **CloudWatch Logs** through the `awslogs` driver, in a log group with explicit retention
- ALB metrics (request count, target response time, 5xx, healthy hosts) are available in CloudWatch under `AWS/ApplicationELB`

---

## Cost & Efficiency

- **No certificate spend**: public ACM certificates used with an ALB are free
- **VPC endpoints instead of a NAT Gateway**: a NAT Gateway bills per hour and per GB even when idle. Instead the private subnets use
  - an **S3 gateway endpoint** (no hourly charge) for ECR image layers
  - **interface endpoints** for `ecr.api`, `ecr.dkr` and `logs`

  Traffic stays on the AWS private network, which is also more secure
- **Disposable environment**: the app stack can be torn down and rebuilt on demand with the destroy and apply pipelines, so non-prod doesn't run (and bill) 24/7
- **Log retention is explicit**, not "store forever by accident"

---

## CI/CD Pipelines

Six workflows live in [`.github/workflows/`](.github/workflows). Four are the main pipelines:

### 1) Docker: build, scan, push

`docker-build-scan.yml` runs when `app/**` changes (on PRs and on push to `main`):
1. Builds the image for `linux/amd64`
2. Scans it with **Trivy** (CRITICAL/HIGH, fixable only); a finding fails the run
3. Hands the scanned image to the next workflow as an artifact (not on PRs)

`docker-push.yml` follows a **successful push-to-main** build. It reuses the exact scanned image, authenticates to AWS with OIDC, and pushes it to ECR tagged with the commit SHA and `latest`. It deliberately does **not** redeploy ECS: shipping an image and rolling it out are separate decisions.

### 2) Health check

`health-check.yml` polls `https://threat-composer.honeycreators.com/` with retries, so a deploy that's still rolling out doesn't cause a false alarm. It is **currently commented out** while the environment is torn down; uncomment it to re-enable the push, 30-minute schedule and manual triggers.

### 3) Terraform: plan and apply

`terraform-plan.yml` runs on PRs and on pushes to `main` that touch `terraform/**`:
1. `terraform fmt`, `init -backend=false`, `validate`
2. **TFLint**, **Checkov** and **Trivy** config scan
3. A speculative `terraform plan` using the read-only role, saved as an artifact and written to the run summary

`terraform-apply.yml` follows a successful push-to-main plan and applies **that exact saved plan**, never a fresh re-plan under the more privileged role. It can also be started manually, in which case it plans and applies in one run. It uses the `production` environment.

### 4) Terraform destroy

`terraform-destroy.yml` is manual only and refuses to run unless you type `destroy` as the confirmation input.

### Pipeline details

- **Concurrency control**: all three Terraform workflows share one `concurrency` group, so a plan and an apply can never race for the S3 state lock
- **Repository variable**: the AWS account ID is a GitHub repository variable, not hard-coded in the Docker workflows
- **Environments**: apply and destroy run in the `production` environment, which is where approval rules can be added (none are configured yet)
- **Fork safety**: workflows use `pull_request` (never `pull_request_target`), so PRs from forks get no secrets or AWS access. First-time contributors need approval before workflows run

### Shift-left security (pre-commit)

`.pre-commit-config.yaml` runs locally before each commit:

- Hygiene: trailing whitespace, end-of-file, merge-conflict markers, large files
- Terraform: `fmt`, `validate`, **TFLint**, **Checkov**

Install once per clone with `pre-commit install`. Hooks are local-only and can be bypassed, so the **same checks run again in CI** as the real gate.

---

## Bootstrapping

The pipelines need a few things to exist first. These live in `terraform/bootstrap/` with **separate state** so the destroy pipeline can never remove them. Apply them once, manually, in this order:

1. `bootstrap/s3`: remote state bucket
2. `bootstrap/ecr`: container registry
3. `bootstrap/route53`: hosted zone (delegate the domain's nameservers to it)
4. `bootstrap/github-oidc`: the plan, apply and ECR-push IAM roles

You also need an issued ACM certificate for the app domain, and the `AWS_ACCOUNT_ID` repository variable set. After that, everything else runs through GitHub Actions.

---

## Possible Improvements

Things deliberately left out of scope, and what I would add next:

- **AWS WAF** in front of the ALB for a stronger security posture
- **Network ACLs** on the subnets as an additional layer (security groups and routing are already tight)
- **Automated rollout**: have the push pipeline trigger a rolling ECS update
- **Observability**: Prometheus + Grafana for metrics, ELK for logs in a real production environment, and AWS X-Ray for traces
- **ALB access logs and VPC flow logs**
- **Required reviewers** on the `production` environment

---

## Learning and Reflections

The biggest takeaway from this project was that most "it doesn't work" moments came down to fundamentals: networking, IAM trust, and state.

I learned to slow down and verify the whole request path end-to-end: Route 53 -> ALB listener -> target group health checks -> ECS task networking -> security groups. Small mismatches (ports, health check paths, SG references, route tables) can look like an application problem when traffic just isn't flowing where you think it is.

The same applied to the pipeline. Getting GitHub OIDC working meant reading the exact token claims rather than guessing at trust policies, and each missing permission was only really found by running the pipeline and reading the exact `AccessDenied`. Building in guardrails early (concurrency control, scanning, pre-commit) caught mistakes before they became expensive to debug.

---

## About

AWS Threat Composer hosted on ECS Fargate with Terraform.
