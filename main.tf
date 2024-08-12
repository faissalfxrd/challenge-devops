provider "aws" {
  region = "eu-central-1"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_exec_role_for_api_status_code"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM Policy Attachment for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "status_code_lambda" {
  filename         = "lambda_function.zip"  # Sicherstellen, dass diese Datei im Arbeitsverzeichnis liegt
  function_name    = "RandomStatusCodeLambdaFunction"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("lambda_function.zip")
}

# API Gateway
resource "aws_api_gateway_rest_api" "status_code_api" {
  name        = "RandomStatusCodeAPI"
  description = "API for generating random HTTP status codes"
}

# API Resource (/statuscode)
resource "aws_api_gateway_resource" "status_code_resource" {
  rest_api_id = aws_api_gateway_rest_api.status_code_api.id
  parent_id   = aws_api_gateway_rest_api.status_code_api.root_resource_id
  path_part   = "statuscode"
}

# API Method (GET /statuscode)
resource "aws_api_gateway_method" "get_status_code_method" {
  rest_api_id   = aws_api_gateway_rest_api.status_code_api.id
  resource_id   = aws_api_gateway_resource.status_code_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.status_code_api.id
  resource_id             = aws_api_gateway_resource.status_code_resource.id
  http_method             = aws_api_gateway_method.get_status_code_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.status_code_lambda.invoke_arn
}

# API Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.status_code_api.id
  stage_name  = "prod"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.status_code_lambda.function_name}"
  retention_in_days = 7
}

# SNS Topic for CloudWatch Alarm Notifications
resource "aws_sns_topic" "alarm_topic" {
  name = "status_code_alarm_topic"
}

# Metric Filter for 5xx Errors
resource "aws_cloudwatch_log_metric_filter" "five_xx_metric_filter" {
  name           = "FiveXXErrors"
  log_group_name = aws_cloudwatch_log_group.lambda_log_group.name
  pattern        = "[statusCode=5*]"
  metric_transformation {
    name      = "FiveXXErrorCount"
    namespace = "StatusCodeErrors"
    value     = "1"
  }
}

# CloudWatch Alarm based on 5xx Errors Metric
resource "aws_cloudwatch_metric_alarm" "status_code_alarm" {
  alarm_name          = "StatusCode5xxAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.five_xx_metric_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.five_xx_metric_filter.metric_transformation[0].namespace
  period              = 10
  statistic           = "Sum"
  threshold           = 10

  alarm_description   = "Triggered when more than 10 5xx errors occur within 10 seconds"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "StatusCodeAPIUsagePlan"
  description = "Usage plan for StatusCode API with rate limiting"

  api_stages {
    api_id = aws_api_gateway_rest_api.status_code_api.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }

  throttle_settings {
    burst_limit = 180  
    rate_limit  = null 
  }
}

# API Gateway API Key and Association with Usage Plan
resource "aws_api_gateway_api_key" "api_key" {
  name        = "StatusCodeAPIKey"
  description = "API Key for accessing the StatusCode API"
  enabled     = true
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
}
