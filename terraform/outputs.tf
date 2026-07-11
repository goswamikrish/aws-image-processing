output "aws_region" {
  value = var.aws_region
}

output "project_name" {
  value = var.project_name
}

output "s3_bucket_uploads" {
  value = aws_s3_bucket.uploads.bucket
}

output "s3_bucket_frontend" {
  value = aws_s3_bucket.frontend.bucket
}

output "s3_bucket_processed" {
  value = aws_s3_bucket.processed.bucket
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.image_api.api_endpoint
}

output "frontend_url" {
  value = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}