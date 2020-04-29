/*
/-----------------------------------------\
| Terraform github actions demo           |
|-----------------------------------------|
| Author: Henk van Achterberg             |
| E-mail: henk.vanachterberg@broadcom.com |
\-----------------------------------------/
*/

// Variables
// Change for Account in AWS / GCP??

variable "region" {
  default = "us-west-1"
}
variable "vpc_id" {
  default = "vpc-046c7fbc221c5c16d"
}
variable "subnet_id" {
  default = "subnet-052290797e5f98f0d"
}
variable "ami_id" {
  default = "ami-0f56279347d2fa43e"
}
variable "ssh_key_name" {
  default = "mwinslow-aws"
}
variable "tenant_domain" {
  default = "symcmwinslow.luminatesite.com"
}
variable "luminate_user" {
  default = "michael.winslow@broadcom.com"
}
variable "luminate_group" {
  default = "Developers"
}
variable "git_repo" {
  default = ""
}
variable "git_branch" {
  default = ""
}

// Terraform init
// Where to store the data/template saving the state in S3 or GCS

terraform {
  required_version = ">=0.12.24"
  backend "s3" {
    bucket         = "mwinslow-tf-state"
    key            = "terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "mwinslow-tf-locks"
    encrypt        = true
  }
}

// AWS Provider

provider "aws" {
  region = var.region
}
resource "aws_security_group" "only_allow_outbound" {
  name        = "only_allow_outbound"
  description = "Allow allow outbound traffic"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_instance" "vm" {
  ami           = var.ami_id
  instance_type = "t2.small"
  key_name      = var.ssh_key_name
  user_data     = data.template_file.user-data.rendered
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [aws_security_group.only_allow_outbound.id]
}

data "template_file" "user-data" {
  template = file("tf-tpl/user-data.tpl")
  vars = {
    config_script_64   = base64encode(data.template_file.fixtures-config.rendered)
    config_script_path = "/tmp/node-config.sh"
  }
}

data "template_file" "fixtures-config" {
  template = file("tf-tpl/config-node.sh.tpl")
  vars = {
    connector_command = luminate_connector.connector.command
    git_repo = var.git_repo
    git_branch = var.git_branch
  }
}

// Secure Access Cloud (luminate) provider

provider "luminate" {
  api_endpoint = "api.${var.tenant_domain}"
}

resource "luminate_site" "site" {
  name = "AWS-CICD-Site"
}

resource "luminate_connector" "connector" {
  name    = "aws-cicd-site-connector"
  site_id = luminate_site.site.id
  type    = "linux"
}

resource "luminate_web_application" "nginx" {
  name             = "AWS-SAC-CICD"
  site_id          = luminate_site.site.id
  internal_address = "http://127.0.0.1:8080"
}

resource "luminate_web_access_policy" "web-access-policy" {
  name                 = "AWS-DEV-access-policy"
  identity_provider_id = data.luminate_identity_provider.idp.identity_provider_id
  //user_ids             = data.luminate_user.users.user_ids
  group_ids            = data.luminate_group.groups.group_ids
  applications         = [luminate_web_application.nginx.id]
}

// Change for Account in SAC
data "luminate_identity_provider" "idp" {
  identity_provider_name = "My-SAC-Okta"
}

//data "luminate_user" "users" {
  //identity_provider_id = data.luminate_identity_provider.idp.identity_provider_id
  //users                = [var.luminate_user]
//}

data "luminate_group" "groups" {
  identity_provider_id = data.luminate_identity_provider.idp.identity_provider_id
  //groups                = [var.luminate_group]
  groups                = ["Developers"]
}

// Output variables

output "nginx-demo-url" {
  value = luminate_web_application.nginx.external_address
}
