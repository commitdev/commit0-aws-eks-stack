locals {
  # user-auth:enabled will allow deployer to manage oathkeeper rules, otherwise concats with []
  auth_enabled = <% if eq (index .Params `userAuth`) "yes" %>true<% else %>false<% end %>
  auth_deploy_rules = local.auth_enabled ? [{
      verbs      = ["get", "create", "delete", "patch", "update"]
      api_groups = ["*"]
      resources  = ["rules"]
    }] : []
}

# define AWS policy documents for developer
data "aws_iam_policy_document" "developer_access" {
  # IAM
  statement {
    effect    = "Allow"
    actions   = ["iam:GetGroup"]
    resources = ["arn:aws:iam::${local.account_id}:group/users/${local.project}-developer-stage"]
  }
  # EKS
  statement {
    effect    = "Allow"
    actions   = ["eks:ListClusters"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${local.region}:${local.account_id}:cluster/${local.project}-stage*"]
  }

  # ECR
  statement {
    effect = "Allow"
    actions = [
      "ecr:DescribeImages",
      "ecr:DescribeRepositories"
    ]
    resources = ["*"]
  }

  # S3
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::*${local.domain_name}"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::*${local.domain_name}/*"]
  }

  # Application secret management - this role can view and edit application secrets in the staging environment
  statement {
    sid       = "ManageApplicationSecrets"
    effect    = "Allow"
    resources = ["arn:aws:secretsmanager:${local.account_id}:${local.account_id}:secret:${local.project}/kubernetes/stage/*"]

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:UpdateSecret",
    ]
  }
  statement {
    sid       = "ListSecrets"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["secretsmanager:ListSecrets"]
  }
}

# define AWS policy documents for operator
data "aws_iam_policy_document" "operator_access" {
  # IAM
  statement {
    effect = "Allow"
    actions = [
      "iam:ListRoles",
      "sts:AssumeRole"
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.project}-kubernetes-operator-stage"]
  }

  # EKS
  statement {
    effect    = "Allow"
    actions   = ["eks:*"]
    resources = ["arn:aws:eks:${local.region}:${local.account_id}:cluster/${local.project}-stage*"]
  }

  # ECR
  statement {
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["*"]
  }

  # S3
  statement {
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::*${local.domain_name}"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::*${local.domain_name}/*"]
  }

  # CloudTrail
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.shared.outputs.cloudtrail_bucket_id}"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.shared.outputs.cloudtrail_bucket_id}/*"]
  }

    # Application secret management - this role can view and edit application secrets in the staging environment
  statement {
    sid       = "ManageApplicationSecrets"
    effect    = "Allow"
    resources = ["arn:aws:secretsmanager:${local.account_id}:${local.account_id}:secret:${local.project}/kubernetes/stage/*"]

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:UpdateSecret",
    ]
  }
  statement {
    sid       = "ListSecrets"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["secretsmanager:ListSecrets"]
  }
}

# define AWS policy documents for deployer
locals {
  non_upload_buckets = [for p in module.stage.s3_hosting : p if ! p.cf_signing_enabled]
}

data "aws_iam_policy_document" "deployer_access" {
  # deploy_assets_policy - Allow the deployers read/write access to the frontend assets bucket and CF invalidations
  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = module.stage.s3_hosting[*].bucket_arn
  }

  statement {
    actions = [
      "s3:*Object",
      "s3:GetBucketLocation",
    ]

    resources = formatlist("%s/*", local.non_upload_buckets[*].bucket_arn)
  }

  statement {
    actions = [
      "cloudfront:ListDistributions",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "cloudfront:CreateInvalidation",
    ]
    resources = formatlist("arn:aws:cloudfront::%s:distribution/%s", local.account_id, module.stage.s3_hosting[*].cloudfront_distribution_id)
  }

  # EKS - Allow the CI user to list and describe clusters
  statement {
    actions = [
      "eks:ListUpdates",
      "eks:ListClusters",
      "eks:DescribeUpdate",
      "eks:DescribeCluster",
    ]

    resources = ["*"]
  }

  # ECR - Allow the deployers to manage ECR
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:GetLifecyclePolicy",
      "ecr:GetLifecyclePolicyPreview",
      "ecr:ListTagsForResource",
      "ecr:DescribeImageScanFindings",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = ["*"]
  }
}


locals {
  # define Kubernetes policy for developer env deployment
  # TODO: given that in a small team, developers are given almost full permissions on Staging here. In the future, may limit the permissions to sub-namepsace per user.
  k8s_developer_env_access = [
    # to support developer environment
    {
      verbs      = ["create", "exec", "list", "get", "delete", "patch", "update", "watch"]
      api_groups = ["*"]
      resources = ["namespaces", "deployments", "deployments/scale", "configmaps", "pods", "pods/log", "pods/status", "pods/portforward", "pods/exec",
        "jobs", "cronjobs", "daemonsets", "endpoints", "events",
        "replicasets", "horizontalpodautoscalers", "horizontalpodautoscalers/status",
        "ingresses", "services", "serviceaccounts",
        "poddisruptionbudgets",
        "secrets", "externalsecrets"
      ]
    }
  ]

  # define Kubernetes policy for developer
  k8s_developer_access = [
    {
      verbs      = ["exec", "list"]
      api_groups = [""]
      resources  = ["pods", "pods/exec", "pods/portforward"]
      }, {
      verbs      = ["get", "list", "watch"]
      api_groups = ["*"]
      resources = ["deployments", "configmaps", "pods", "pods/log", "pods/status", "nodes", "jobs", "cronjobs", "services", "replicasets",
        "daemonsets", "endpoints", "namespaces", "events", "ingresses", "statefulsets", "horizontalpodautoscalers", "horizontalpodautoscalers/status", "replicationcontrollers"
      ]
    }
  ]

  # define Kubernetes policy for operator
  k8s_operator_access = [
    {
      verbs      = ["exec", "create", "list", "get", "delete", "patch", "update", "watch"]
      api_groups = ["*"]
      resources = ["deployments", "configmaps", "pods", "pods/exec", "pods/log", "pods/status", "pods/portforward",
        "nodes", "jobs", "cronjobs", "statefulsets", "secrets", "externalsecrets", "services", "daemonsets", "endpoints", "namespaces", "events", "ingresses",
        "horizontalpodautoscalers", "horizontalpodautoscalers/status",
        "poddisruptionbudgets", "replicasets", "replicationcontrollers"
      ]
    }
  ]

  # define Kubernetes policy for deployer
  k8s_deployer_access = concat([
    {
      verbs      = ["create", "list", "get", "delete", "patch", "update", "watch"]
      api_groups = ["*"]
      resources = ["deployments", "configmaps", "pods", "pods/log", "pods/status",
        "jobs", "cronjobs", "services", "daemonsets", "endpoints", "namespaces", "events", "ingresses",
        "horizontalpodautoscalers", "horizontalpodautoscalers/status",
        "poddisruptionbudgets", "replicasets", "externalsecrets"
      ]
    },
    {
      verbs      = ["create", "delete", "patch", "update"]
      api_groups = ["*"]
      resources  = ["secrets"]
    }
  ], local.auth_deploy_rules)
}
