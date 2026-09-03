terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

variable "github_repo" {
  type    = string
  default = "justthatpixel/aws-ecs-project"
}

# Reusing the OIDC provider that already exists in this account — AWS only
# allows one per provider URL, and this one was created independently of
# this project.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# Plan role — assumable from any branch/PR in this repo, read-only.
# Used by the terraform-plan workflow so PRs from any branch can run plan
# without ever being able to change real infrastructure.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "plan_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_plan" {
  name               = "github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_assume_role.json
}

data "aws_iam_policy_document" "plan_permissions" {
  statement {
    sid = "ReadOnly"
    actions = [
      "ec2:Describe*",
      "elasticloadbalancing:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate",
      "logs:DescribeLogGroups",
      "logs:ListTagsLogGroup",
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy",
      "ecr:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "StateBucketRead"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::raihan-terraform-backend-state",
      "arn:aws:s3:::raihan-terraform-backend-state/*",
    ]
  }
}

resource "aws_iam_role_policy" "plan_permissions" {
  name   = "terraform-plan-readonly"
  role   = aws_iam_role.github_actions_plan.id
  policy = data.aws_iam_policy_document.plan_permissions.json
}

# ---------------------------------------------------------------------------
# Apply/destroy role — only assumable from the main branch. Used by the
# terraform-apply and terraform-destroy workflows.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "apply_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_apply" {
  name               = "github-actions-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_assume_role.json
}

data "aws_iam_policy_document" "apply_permissions" {
  statement {
    sid = "InfraManage"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "ecs:*",
      "logs:*",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
      "route53:ChangeResourceRecordSets",
      "route53:GetChange",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "ecr:DescribeRepositories",
    ]
    resources = ["*"]
  }

  statement {
    sid = "IamForEcsRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::*:role/threat-composer-*",
    ]
  }

  statement {
    sid     = "StateBucketReadWrite"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::raihan-terraform-backend-state",
      "arn:aws:s3:::raihan-terraform-backend-state/*",
    ]
  }
}

resource "aws_iam_role_policy" "apply_permissions" {
  name   = "terraform-apply-infra"
  role   = aws_iam_role.github_actions_apply.id
  policy = data.aws_iam_policy_document.apply_permissions.json
}

output "plan_role_arn" {
  value = aws_iam_role.github_actions_plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.github_actions_apply.arn
}
