# define policy documents for backend services
# sample policies
data "aws_iam_policy_document" "resource_access_backendservice" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:Describe*",
    ]
    resources = ["arn:aws:ec2:::stage-*"]
  }
<% if eq (index .Params `fileUploads`) "yes" %>
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["arn:aws:s3:::files.${local.domain_name}/*"]
  }
<% end %>
  # can be more statements here
}
