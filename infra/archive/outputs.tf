output "cf_url" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "cf_distribution_id" {
  value = aws_cloudfront_distribution.cdn.id
}
