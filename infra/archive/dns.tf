# Zone and site records adopted on 2026-10-26. The zone was owned by the old
# VulnCorps/iac containers stack (local state); the apex and www records were
# hand-made.
import {
  to = aws_route53_zone.main
  id = "Z01774112RYX4U5AIE1V7"
}

import {
  to = aws_route53_record.apex
  id = "Z01774112RYX4U5AIE1V7_cvearchiver.com_A"
}

import {
  to = aws_route53_record.www
  id = "Z01774112RYX4U5AIE1V7_www.cvearchiver.com_CNAME"
}

resource "aws_route53_zone" "main" {
  name    = "cvearchiver.com"
  comment = "Managed by Terraform"

  lifecycle {
    prevent_destroy = true
  }
}

# GitHub Pages (site.yml); https://docs.github.com/pages/configuring-a-custom-domain-for-your-github-pages-site
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "cvearchiver.com"
  type    = "A"
  ttl     = 300
  records = ["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"]
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.cvearchiver.com"
  type    = "CNAME"
  ttl     = 300
  records = ["cve-community.github.io"]
}

resource "aws_route53_record" "archive_subdomain" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "archive.cvearchiver.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate" "archive_cert" {
  provider          = aws.us_east_1
  domain_name       = "archive.cvearchiver.com"
  validation_method = "DNS"
}

resource "aws_route53_record" "archive_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.archive_cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "archive_cert_validation" {
  certificate_arn         = aws_acm_certificate.archive_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.archive_cert_validation : r.fqdn]
}

