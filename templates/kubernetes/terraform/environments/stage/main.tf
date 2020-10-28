terraform {
  backend "s3" {
    bucket         = "<% .Name %>-stage-terraform-state"
    key            = "infrastructure/terraform/environments/stage/kubernetes"
    encrypt        = true
    region         = "<% index .Params `region` %>"
    dynamodb_table = "<% .Name %>-stage-terraform-state-locks"
  }

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.7"
    }
  }
}

locals {
  project      = "<% .Name %>"
  region       = "<% index .Params `region` %>"
  account_id   = "<% index .Params `accountId` %>"
  domain_name  = "<% index .Params `stagingHostRoot` %>"
  file_uploads = <% if eq (index .Params `fileUploads`) "yes" %>true<% else %>false<% end %>
}

provider "aws" {
  region              = local.region
  allowed_account_ids = [local.account_id]
}

# Provision kubernetes resources required to run services/applications
module "kubernetes" {
  source = "../../modules/kubernetes"
  environment         = "stage"

  project             = local.project
  region              = local.region
  allowed_account_ids = [local.account_id]
  random_seed         = "<% index .Params `randomSeed` %>"
  cf_signing_enabled  = local.file_uploads

  # Authenticate with the EKS cluster via the cluster id
  cluster_name = "${local.project}-stage-${local.region}"

  external_dns_zone     = local.domain_name
  external_dns_owner_id = "${local.project}-stage-${local.region}"

  # Registration email for LetsEncrypt
  cert_manager_acme_registration_email = "devops@${local.domain_name}"

  # Logging and Metrics configuration
  logging_type = "<% index .Params `loggingType` %>"
  metrics_type = "<% index .Params `metricsType` %>"
  internal_domain = "" # TODO: Add internal domain support

  # Application policy list - This allows applications running in kubernetes to have access to AWS resources.
  # Specify the service account name, the namespace, and the policy that should be applied.
  # This makes use of IRSA: https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/
  application_policy_list = [
    {
      service_account = "backend-service"
      namespace       = local.project
      policy          = data.aws_iam_policy_document.resource_access_backendservice
    }
    # Add additional mappings here
  ]

  # Version of default database user password for application to access database - change the version if you want to renew the password
  db_app_password_version = "v1.0"


  # Wireguard configuration
  vpn_server_address = "10.10.199.0/24"
  vpn_client_publickeys = [
    ["Max C", "10.10.199.201/32", "/B3Q/Hlf+ILInjpehTLk9DZGgybdGdbm0SsG87OnWV0="],
    ["Carter L", "10.10.199.202/32", "h2jMuaXNIlx7Z0a3owWFjPsAA8B+ZpQH3FbZK393+08="],
  ]
}
