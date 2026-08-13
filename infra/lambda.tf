data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "ai" {
  function_name    = "cuisinecoord-ai"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda.arn
  timeout          = 60

  environment {
    variables = {
      ANTHROPIC_API_KEY   = var.anthropic_api_key
      GOOGLE_PLACES_KEY   = var.google_places_key
    }
  }
}

resource "aws_apigatewayv2_api" "ai" {
  name          = "cuisinecoord-ai-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 86400
  }
}

resource "aws_apigatewayv2_integration" "ai" {
  api_id                 = aws_apigatewayv2_api.ai.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ai.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ai" {
  api_id    = aws_apigatewayv2_api.ai.id
  route_key = "POST /ai"
  target    = "integrations/${aws_apigatewayv2_integration.ai.id}"
}

resource "aws_apigatewayv2_route" "restaurants" {
  api_id    = aws_apigatewayv2_api.ai.id
  route_key = "POST /restaurants"
  target    = "integrations/${aws_apigatewayv2_integration.ai.id}"
}

resource "aws_apigatewayv2_route" "place_details" {
  api_id    = aws_apigatewayv2_api.ai.id
  route_key = "POST /place-details"
  target    = "integrations/${aws_apigatewayv2_integration.ai.id}"
}

resource "aws_apigatewayv2_stage" "ai" {
  api_id      = aws_apigatewayv2_api.ai.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ai.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ai.execution_arn}/*/*"
}
