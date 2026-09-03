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

# GitHub rolled out an "immutable" OIDC sub-claim format for repos created
# after July 15, 2026: `repo:OWNER@OWNER-ID/REPO@REPO-ID:...` instead of the
# old `repo:OWNER/REPO:...`. Both repos here postdate that cutoff, so their
# tokens use the new format — trust conditions below must match it exactly
# or every AssumeRoleWithWebIdentity call fails with a generic "Not
# authorized" error that gives no hint the claim shape is the problem.
# IDs come from `gh api repos/<owner>/<repo> --jq '.id, .owner.id'`.
locals {
  github_owner_id = "justthatpixel@64263647"
  github_repo     = "${local.github_owner_id}/aws-ecs-project@1356034345"
  app_github_repo = "${local.github_owner_id}/ecs-project@1325329604"
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
      values   = ["repo:${local.github_repo}:*"]
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
      "acm:GetCertificate",
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

  # Even a read-only `terraform plan` acquires the S3-native state lock
  # (use_lockfile = true in provider.tf), which writes/deletes a small
  # `<key>.tflock` companion object. Scoped to just that lock object, not
  # the real state file, so this role still can't ever write actual state.
  statement {
    sid       = "StateLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::raihan-terraform-backend-state/*.tflock"]
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
      # The apply/destroy jobs target the "production" GitHub Environment
      # (for future manual-approval protection rules), which changes the
      # OIDC token's sub claim from the branch-ref format to this
      # environment-scoped one.
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo}:environment:production"]
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
      "acm:GetCertificate",
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

# ---------------------------------------------------------------------------
# ECR-push role — for the app repo's build/scan/push pipeline. Deliberately
# separate from the infra roles above: this one only ever pushes images and
# force-redeploys the one ECS service it's scoped to (so a new image
# actually gets picked up) — no VPC/ALB/IAM access, and it's trusted for a
# different repo entirely.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecr_push_assume_role" {
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
      values   = ["repo:${local.app_github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr_push" {
  name               = "github-actions-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.ecr_push_assume_role.json
}

data "aws_iam_policy_document" "ecr_push_permissions" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
    ]
    resources = ["arn:aws:ecr:eu-west-2:720644165598:repository/threat-composer"]
  }

  statement {
    sid       = "ForceEcsRedeploy"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:aws:ecs:eu-west-2:720644165598:service/ecs-project/threat-composer"]
  }
}

resource "aws_iam_role_policy" "ecr_push_permissions" {
  name   = "ecr-push-threat-composer"
  role   = aws_iam_role.github_actions_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push_permissions.json
}

output "ecr_push_role_arn" {
  value = aws_iam_role.github_actions_ecr_push.arn
}
