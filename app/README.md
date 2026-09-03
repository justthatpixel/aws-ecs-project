# AWS Threat Composer App Hosted on ECS Fargate with Terraform

![AWS](https://img.shields.io/badge/AWS-ECS_Fargate-FF9900?style=flat&logo=amazonecs&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-IaC-844FBA?style=flat&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-2088FF?style=flat&logo=githubactions&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Containers-2496ED?style=flat&logo=docker&logoColor=white)
![Security](https://img.shields.io/badge/Security-OIDC-6DB33F?style=flat&logo=openid&logoColor=white)
![IAM](https://img.shields.io/badge/IAM-Least_Privilege-CC2936?style=flat&logo=amazoniam&logoColor=white)

## Contents

- [Overview of the setup](#overview-of-the-setup)
- [Architecture Diagram](#architecture-diagram)
- [Repository Structure](#repository-structure)
- [Local App Set-up](#local-app-set-up)
- [Key Components](#key-components)
- [Security](#security)
- [Observability](#observability)
- [Cost & Efficiency Considerations](#cost--efficiency-considerations-business-impact)
- [CI/CD Pipelines](#cicd-pipelines)
- [Monitoring](#monitoring-cloudwatch--custom-dashboard)
- [Successful Pipeline Runs](#successful-pipeline-runs)
- [Learning and Reflections](#learning-and-reflections)

---

## Overview of the setup

<!-- TODO: insert demo gif here -->

This project is based on AWS's Threat Composer, an open-source tool designed to facilitate threat modelling and improve security assessments. It answers the question of "What could go wrong?" — helping teams identify potential security threats to a system and document them in a clear, structured format, rather than starting from a blank page. You can check out the tool here: https://awslabs.github.io/threat-composer/workspaces/default/dashboard

### Architecture Diagram

<img width="672" height="480" alt="Architecture Diagram" src="https://github.com/user-attachments/assets/c011bf4f-f670-48a0-bb17-d1dd3c303fbc" />

---

## Repository Structure

```
.
├── modules/
│   ├── vpc/              # VPC, subnets, route tables, NAT Gateway
│   ├── alb/               # Application Load Balancer, listeners, target groups
│   ├── acm/               # ACM certificate + Route 53 validation
│   └── ecs/               # ECS cluster, task definitions, service
├── environments/
│   └── prod/               # Environment-specific variable values
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
├── docker/
│   └── Dockerfile          # Multi-stage build, non-root user
├── .github/
│   └── workflows/          # CI/CD pipeline definitions
├── backend.tf                # S3 remote state + locking config
└── README.md
```

---

## Local App Set-up

### Run locally with Docker (build + run + health check)

From the repo root (where the Dockerfile lives):

```bash
# 1) Build the image
docker build -t threat-composer:local .

# 2) Run the container (maps host 8080 -> container 8080)
docker run --rm --name threat-composer -p 8080:8080 threat-composer:local

# (optional) run in detached mode instead:
# docker run -d --rm --name threat-composer -p 8080:8080 threat-composer:local
```

To do a health check, run the following command:

```bash
curl -i http://localhost:8080/health
# or just:
curl http://localhost:8080/health
```

You can stop the container with:

```bash
docker stop threat-composer
```

---

## Key Components

### Containers & Runtime

- Multi-stage Docker build reduced the application image from **1.39 GB → 99.2 MB (~93%)**
- Container runs as a **non-root user**, reducing unnecessary runtime privileges
- Application runs as an **ECS Fargate service** across two Availability Zones
- ECS tasks run exclusively within private subnets with `assign_public_ip = false`
- Container images are stored in **Amazon ECR** and versioned using immutable Git SHA tags

```
it-tools-fargate:multi-stage    c240da4e2e95    99.2MB    27.1MB
it-tools-fargate:single-stage   4e1bea080292    1.39GB    204MB
```

> [!NOTE]
> ECS Fargate was selected to provide managed container compute without provisioning or maintaining EC2 worker instances.

### Networking & Ingress

- Custom `10.0.0.0/16` VPC spans `eu-west-2a` and `eu-west-2b`
- Public subnets host the internet-facing **Application Load Balancer** and NAT Gateway
- Private subnets isolate **ECS Fargate tasks** from direct internet access
- ECS security rules permit application traffic only from the ALB security group
- NAT Gateway provides controlled outbound connectivity for workloads in private subnets
- HTTP traffic is redirected to HTTPS before being forwarded to healthy ECS targets

> [!NOTE]
> Keeping ECS tasks private ensures the ALB remains the only public entry point to the application.

### DNS & TLS

- **Route 53** manages DNS for `tools.osmanhus.co.uk`
- **AWS Certificate Manager (ACM)** provides the TLS certificate used by the ALB
- Route 53 directs application traffic to the internet-facing ALB
- DNS for the application subdomain is delegated from Cloudflare to Route 53

### Terraform & State Management

- Infrastructure is provisioned through reusable **Terraform modules**: `vpc`, `sg`, `alb`, `acm`, `ecs`
- Module inputs/outputs are wired in `infra/main.tf`, keeping concerns separated and reusable
- Remote Terraform state is stored in **Amazon S3**
- Native S3 state locking with `use_lockfile = true` prevents concurrent state modifications
- Infrastructure parameters are exposed through variables to reduce hard-coded configuration
- Terraform formatting, validation, planning, and security checks run before deployment

> [!IMPORTANT]
> Remote state and state locking protect the shared Terraform state from conflicting infrastructure changes.

---

## Security

- **GitHub Actions OIDC** provides temporary AWS credentials without long-lived access keys
- IAM permissions are scoped to the operations required by GitHub Actions and ECS
- ECS tasks run without public IP addresses inside private subnets
- Container vulnerability scanning runs before images are published to ECR
- Terraform security scanning checks infrastructure configuration before deployment

> [!IMPORTANT]
> OIDC federation removes the need to store long-lived AWS access keys as GitHub secrets entirely — credentials are short-lived and scoped to a single workflow run.

---

## Observability

- ECS container logs are centralised in **Amazon CloudWatch Logs**
- Log retention is explicitly configured through Terraform
- ECS deployment circuit breaker automatically rolls back failed deployments
- Post-deployment health checks verify application availability after infrastructure changes

---

## Cost & Efficiency Considerations (business impact)

This setup is designed to keep costs **predictable** and reduce common sources of waste while staying production-aligned.

- **No certificate spend / lower ops overhead (ACM + ALB)**: TLS is terminated at the ALB using AWS Certificate Manager. Public certificates used with ACM-integrated services (like Elastic Load Balancing) are **free**, which avoids third-party certificate purchase/renewal overhead.
- **Predictable ingress costs (ALB)**: The Application Load Balancer is billed as **ALB-hours + LCU-hours**, so cost scales with runtime and real usage rather than fixed server sizing.
- **Private compute with controlled egress**: ECS tasks run in private subnets; outbound internet access is provided via a NAT Gateway only when required. NAT Gateways are charged **per hour** and **per GB processed**, so keeping environments lifecycle-managed (IaC) helps prevent "always-on" spend in non-prod.
- **Cost optimisation path (recommended improvement)**: Prefer **VPC Endpoints (PrivateLink / Gateway endpoints)** over NAT for AWS service access (e.g., CloudWatch Logs, ECR, S3) to reduce NAT Gateway usage and public data transfer. Gateway endpoints (S3/DynamoDB) have **no hourly charges**, and are explicitly called out in AWS Well-Architected as a way to reduce NAT costs.
- **Observability spend is controlled via retention**: Log retention is set explicitly (not "store forever by accident") and can be tuned per environment requirements, balancing troubleshooting needs vs ongoing CloudWatch Logs storage/analysis costs.

> [!TIP]
> NAT Gateways are one of the most commonly overlooked cost drivers in AWS accounts — they're billed continuously even when idle. Swapping to VPC Gateway Endpoints for S3/DynamoDB traffic is a low-effort, zero-hourly-cost win worth prioritising before scaling this to multiple environments.

---

## CI/CD Pipelines

This project uses three GitHub Actions workflows with clear separation of responsibility.

### 1) Build and Push to ECR

- Runs on push to `main` when `app/**` changes
- Builds and scans the container image for vulnerabilities
- Authenticates to AWS via OIDC and pushes the image to ECR
- Uses Git SHA tags for immutable container image versioning

> [!IMPORTANT]
> GitHub Actions authenticates to AWS using OIDC and temporary credentials, eliminating the need to store long-lived AWS access keys.

### 2) Deploy and Post Health Check

<!-- TODO: describe this workflow -->

### 3) Destroy Infrastructure

<!-- TODO: describe this workflow -->

### Pipeline configuration details

- **Repo variables for configuration**: Non-sensitive settings (e.g. account/region/image tag names) are stored as **GitHub repository variables**, keeping workflows clean and avoiding hard-coded values.
- **Pipeline gating (approvals)**: Terraform **apply / destroy** stages are protected by environment rules so deployments require approval before running. ([docs](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment))
- **Concurrency control**: Deployment workflows use **concurrency** to prevent overlapping applies/destroys and reduce the risk of state conflicts. ([docs](https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs))

### Security scanning

- **Container image scanning**: [Trivy](https://github.com/aquasecurity/trivy-action) scans run during image publishing to catch vulnerabilities before pushing/deploying.
- **Terraform / IaC scanning**: Trivy is also used for [IaC misconfiguration scanning](https://trivy.dev/docs/v0.50/tutorials/misconfiguration/terraform/) of Terraform before deployment.

### Shift-left security (pre-commit)

This repo uses the **pre-commit** framework to run security and quality checks locally before changes land in Git, so misconfigurations and risky patterns are caught early instead of during `terraform apply`.

Hooks include Terraform formatting and scanners (via `pre-commit-terraform`), plus **Checkov** and **Trivy** misconfiguration scanning for Terraform/IaC; supporting hygiene checks like YAML formatting and workflow/Docker linting keep CI and container build files clean as well.

> [!NOTE]
> Running Checkov and Trivy at pre-commit (rather than only in CI) catches misconfigurations before they're even pushed — shifting feedback from minutes-later to seconds-later.

---

## Monitoring (CloudWatch + custom dashboard)

This deployment uses **Amazon CloudWatch** for both **logs** and **metrics** so you can troubleshoot end-to-end (ALB → Target Group → ECS tasks) in one place.

![Dashboard](./assets/dashboard-new.png)

### Logs

- ECS task logs → CloudWatch Logs via the `awslogs` log driver (per container)
- Log groups/streams exist in **eu-west-2** (CloudWatch is regional)

### Metrics

- ALB metrics are available automatically in `AWS/ApplicationELB`
- ECS metrics are available via ECS service/task metrics, and (optionally) Container Insights metrics in `ECS/ContainerInsights` if enabled

### Custom dashboard

A custom CloudWatch dashboard was added to make troubleshooting faster during demos and incident-style debugging.

Typical widgets included:
- **ALB**: `RequestCount`, `TargetResponseTime`, `HTTPCode_Target_5XX_Count`, `HealthyHostCount`
- **ECS / tasks**: CPU and memory utilization, plus any Container Insights metrics if enabled

The dashboard is managed as code using Terraform (`aws_cloudwatch_dashboard`) so it can be recreated.

---

## Successful Pipeline Runs

**Docker Image Publish**

<img width="679" height="127" alt="Docker Image Publish pipeline run" src="https://github.com/user-attachments/assets/925ce867-8e20-4d56-830d-1bee10e9b2ad" />

**Terraform Plan + Apply**

<img width="692" height="136" alt="Terraform Plan and Apply pipeline run" src="https://github.com/user-attachments/assets/b4f0676a-7853-44ed-b601-3507d6ec402a" />

**Terraform Plan + Destroy**

<img width="684" height="158" alt="Terraform Plan and Destroy pipeline run" src="https://github.com/user-attachments/assets/712860ec-4c1f-4c78-99b9-a1563c4c3553" />

**Domain URL Health Check**

<img width="690" height="147" alt="Domain URL health check" src="https://github.com/user-attachments/assets/b0dc64d5-d309-4f1c-b1cb-6400ed0bc1b9" />

---

## Learning and Reflections

The biggest takeaway from this project was that most "it doesn't work" moments came down to networking fundamentals.

I learned to slow down and systematically verify the full request path end-to-end: Route53 → ALB listener rules → target group health checks → ECS task networking (subnets/routes) → security groups (inbound + outbound).

Small mismatches (ports, health check paths, SG references, route tables) can look like an application issue when it's actually just traffic not flowing where you think it is.

On the process side, I reinforced the importance of staying consistent and not trying to solve everything in one jump. Breaking problems into smaller checks, asking for help when stuck, and avoiding overthinking made the biggest difference in getting from "provisioned" to "actually reachable and stable."

I also gained appreciation for building in guardrails early (CI gating/approvals, concurrency control, and pre-commit scanning) so mistakes can be caught quickly before they become expensive or time-consuming to debug.

---

## About

AWS Threat Composer App Hosted on ECS Fargate with Terraform
