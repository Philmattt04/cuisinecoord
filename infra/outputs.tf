output "app_url"        { value = "https://${var.app_domain}" }
output "cloudfront_id"  { value = aws_cloudfront_distribution.web.id }
output "s3_bucket"      { value = aws_s3_bucket.web.bucket }
output "api_url"        { value = "${aws_apigatewayv2_stage.ai.invoke_url}/ai" }
