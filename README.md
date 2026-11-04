# AWS Threat Composer on ECS Fargate with Terraform

![AWS](https://img.shields.io/badge/AWS-ECS_Fargate-FF9900?style=flat&logo=amazonecs&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-IaC-844FBA?style=flat&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-2088FF?style=flat&logo=githubactions&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Containers-2496ED?style=flat&logo=docker&logoColor=white)
![Security](https://img.shields.io/badge/Security-OIDC-6DB33F?style=flat&logo=openid&logoColor=white)

## 📖 Introduction

This project hosts AWS's open-source [Threat Composer](https://awslabs.github.io/threat-composer/workspaces/default/dashboard) threat modelling tool on **ECS Fargate**, behind an HTTPS Application Load Balancer. All infrastructure is Terraform, deployed through GitHub Actions.

Threat Composer helps you map the ways an attacker could exploit a system, modelled as **assumptions, threats and mitigations**.

<img width="1080" height="608" alt="Threat Composer" src="https://github.com/user-attachments/assets/211a6dec-fb41-4b13-8671-0bc4d36d457f" />

## 🗺️ Architecture

<img width="2258" height="1614" alt="Architecture diagram" src="https://github.com/user-attachments/assets/6272ce82-5930-4673-85ff-f24d0e659b8f" />

## 📁 Repository Structure

```
.
├── .github/workflows/     # CI/CD pipelines
├── .pre-commit-config.yaml
├── app/                   # Threat Composer source + Dockerfile + nginx.conf
└── terraform/
    ├── main.tf            # Wires the modules together
    ├── modules/           # vpc, sg, alb, acm, ecs
    └── bootstrap/         # One-off foundations: s3, ecr, route53, github-oidc
```

## 🌟 Key Features

### Infrastructure Highlights

- **AWS ECS Fargate**: Serverless containers, 2 tasks running across 2 AZs
- **Application Load Balancer**: Public entry point with HTTP → HTTPS redirect
- **Multi-AZ Deployment**: Public subnets for the ALB, private subnets for the tasks
- **Route 53 + ACM**: Custom domain with a free TLS certificate
- **VPC Endpoints**: Private access to ECR, S3 and CloudWatch Logs, no NAT Gateway needed
- **Container Insights**: ECS metrics, plus container logs in CloudWatch

### DevOps Best Practices

- **Infrastructure as Code**: Terraform with a modular design
- **CI/CD Integration**: Four GitHub Actions pipelines (below)
- **Remote State Management**: Encrypted S3 backend with state locking
- **Security Scanning**: Trivy, Checkov and TFLint on every change
- **Pre-commit Hooks**: fmt, validate, TFLint and Checkov before each commit
- **Docker Best Practices**:
  - **Multi-stage Build**: Node builds the app, only the static output ships in the final image
  - **Minimal Base Image**: Alpine-based `nginx-unprivileged` to reduce the attack surface
  - **Non-root User**: Container runs as the `nginx` user, never root
  - **Trivy Image Scan**: Every image is scanned for CRITICAL/HIGH vulnerabilities before it is pushed to ECR

## 🔒 Security Features

- **Network Isolation**: ECS tasks sit in private subnets with no public IP
- **Security Groups**: Tasks only accept traffic from the ALB's security group
- **OIDC Authentication**: Short-lived AWS credentials, no stored access keys
- **IAM Roles**: Separate least-privilege roles for plan, apply and image push
- **Hardened Container**: Non-root nginx on a minimal base image, read-only root filesystem
- **Encryption**: State bucket encrypted, TLS 1.3 policy on the ALB

## 🚀 CI/CD Pipelines

- **Docker Build, Scan & Push**: Builds the image, scans it with Trivy, then pushes to ECR tagged with the commit SHA
- **Health Check**: Polls the live URL with retries (currently commented out while the environment is down)
- **Terraform Plan & Apply**: Lint, scan and plan on every change, then apply the exact saved plan on `main`
- **Terraform Destroy**: Manual only, requires typing `destroy` to confirm

Plan, apply and destroy share one concurrency group so they can never race for the state lock.

## 💻 Local Set-up

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) to build and run the container
- [Node.js](https://nodejs.org/) 24 and [Yarn](https://yarnpkg.com/) (only for the dev server)
- [Terraform](https://developer.hashicorp.com/terraform/install) 1.6+, [TFLint](https://github.com/terraform-linters/tflint), [Checkov](https://www.checkov.io/) and [pre-commit](https://pre-commit.com/) (only for the infrastructure checks)
- The AWS CLI with credentials (only for a real `terraform plan`)

### Run the app in Docker (matches what ships to ECS)

```bash
git clone https://github.com/justthatpixel/aws-ecs-project.git
cd aws-ecs-project/app

docker build -t threat-composer:local .
docker run --rm --name threat-composer -p 8080:8080 threat-composer:local
```

Open <http://localhost:8080/>. Stop it with `docker stop threat-composer`.

### Run the app with the dev server (hot reload)

```bash
cd app
yarn install --frozen-lockfile
yarn start
```

Open <http://localhost:3000/>.

### Check the Terraform locally (no AWS account needed)

```bash
cd terraform
terraform fmt -recursive -check
terraform init -backend=false
terraform validate
tflint --init && tflint --config=.tflint.hcl --call-module-type=all
checkov -d . --config-file .checkov.yaml
```

### Plan against the real infrastructure

This reads the shared S3 state, so it needs AWS credentials with access to the state bucket. Normally the pipeline does this for you.

```bash
cd terraform
terraform init
terraform plan
```

### Enable the pre-commit hooks

Run once per clone, from the repo root:

```bash
pre-commit install
```

Then fmt, validate, TFLint and Checkov run on every commit. You can also run them on demand with `pre-commit run --all-files`.

## 🧰 Bootstrapping

Apply once, manually, in this order. Each has its own state so the destroy pipeline can't touch them:

1. `terraform/bootstrap/s3`: state bucket
2. `terraform/bootstrap/ecr`: container registry
3. `terraform/bootstrap/route53`: hosted zone
4. `terraform/bootstrap/github-oidc`: GitHub Actions IAM roles

You also need an issued ACM certificate for the domain and an `AWS_ACCOUNT_ID` repository variable.

## 🔭 Possible Improvements

- Prometheus + Grafana, ELK and X-Ray for observability
- AWS WAF in front of the ALB
- ECS auto-scaling policies

