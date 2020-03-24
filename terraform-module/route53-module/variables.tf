variable "fqdn" {
  description = "Front-End LB FQDN"
}

variable "zone_id" {
  description = "The Route53 Zone ID for the domain"
}

variable "domain_name" {
  description = "The domain name to use"
}

variable "access_key" {
  description = "AWS Access Key for Route53"
}

variable "access_secret" {
  description = "AWS access secret for Route53"
}

variable "aws_region" {
  description = "Region for AWS"
  default = "us-east-1"
}