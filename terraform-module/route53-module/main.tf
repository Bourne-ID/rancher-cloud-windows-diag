provider "aws" {
  access_key = var.access_key
  secret_key = var.access_secret
  region     = var.aws_region
}

resource "aws_route53_record" "bourneidrecord" {
  name = var.fqdn
  type = "CNAME"
  zone_id = var.zone_id
  records = [var.fqdn]
  ttl = "60"
}