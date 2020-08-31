terraform {
  backend "s3" {
    bucket         = "<% .Name %>-dev-terraform-state"
    key            = "infrastructure/terraform/environments/dev/kubernetes"
    encrypt        = true
    region         = "<% index .Params `region` %>"
    dynamodb_table = "<% .Name %>-dev-terraform-state-locks"
  }
}

# Provision kubernetes resources required to run services/applications
module "kubernetes" {
  source = "../../modules/kubernetes"

  project = "<% .Name %>"

  environment = "dev"
  region      = "<% index .Params `region` %>"

  # Authenticate with the EKS cluster via the cluster id
  cluster_name = "<% .Name %>-dev-<% index .Params `region` %>"

  external_dns_zone = "<% index .Params `stagingHostRoot` %>"
  external_dns_owner_id = "<% GenerateUUID %>" # randomly generated ID

  # Registration email for LetsEncrypt
  cert_manager_acme_registration_email = "devops@<% index .Params `stagingHostRoot` %>"

  # Logging configuration
  logging_type = "<% index .Params `loggingType` %>"

  # Application policy list
  application_policy_list = [
    {
      application     = "app1"
      namespace       = "<% .Name %>"
      policy          = data.aws_iam_policy_document.resource_access_app1
    },
    {
      application     = "app2"
      namespace       = "<% .Name %>"
      policy          = data.aws_iam_policy_document.resource_access_app2
    }
    # could be more policies defined here (if have)
  ]
}
