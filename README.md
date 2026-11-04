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

## 💻 Run Locally

```bash
cd app
docker build -t threat-composer:local .
docker run --rm --name threat-composer -p 8080:8080 threat-composer:local
```

Then open <http://localhost:8080/>.

## 🧰 Bootstrapping

Apply once, manually, in this order. Each has its own state so the destroy pipeline can't touch them:

1. `terraform/bootstrap/s3`: state bucket
2. `terraform/bootstrap/ecr`: container registry
3. `terraform/bootstrap/route53`: hosted zone
4. `terraform/bootstrap/github-oidc`: GitHub Actions IAM roles

You also need an issued ACM certificate for the domain and an `AWS_ACCOUNT_ID` repository variable.

## 🔭 Possible Improvements

- AWS WAF in front of the ALB
- ECS auto-scaling policies
- Network ACLs as an extra layer
- Prometheus + Grafana, ELK and X-Ray for observability
- Automatic ECS rollout after an image push
- Required reviewers on the `production` environment

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test thoroughly
4. Submit a pull request with a detailed description
5. Ensure all CI checks pass
