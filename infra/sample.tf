data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  acm_cert_arn = "arn:aws:acm:us-east-1:${data.aws_caller_identity.current.id}:certificate/${var.cert_id}"
  domain_name  = "domain.com"
  api_name     = "Notion Proxy"
}

data "aws_route53_zone" "main" {
  name = local.domain_name
}

data "archive_file" "dummy_code" {
  type        = "zip"
  output_path = "lambda.zip"
  source {
    content  = "# This is a dummy code. Update lambda function after `terraform apply`."
    filename = "notion-proxy.py"
  }
}

resource "aws_lambda_function" "main" {
  filename      = data.archive_file.dummy_code.output_path
  function_name = "handbook-notion-proxy"
  role          = aws_iam_role.lambda.arn
  package_type  = "Zip"
  handler       = "notion-proxy.lambda_handler"
  runtime       = "python3.8"

  memory_size = 256
  timeout     = 10
}

resource "aws_iam_role" "lambda" {
  name = "notion-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = ["lambda.amazonaws.com"]
        },
        Effect = "Allow",
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  description = "IAM policy for logging from a lambda"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          aws_cloudwatch_log_group.main.arn,
          "${aws_cloudwatch_log_group.main.arn}:*",
        ],
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
}

resource "aws_route53_record" "main" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.main.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.main.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "msgstore" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "msgstore.${local.domain_name}"
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.msgstore.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.msgstore.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name = local.api_name

  endpoint_configuration {
    types = ["EDGE"]
  }

  binary_media_types = [
    "*/*",
    "text/plain",
  ]

  minimum_compression_size = 0
}

resource "aws_api_gateway_domain_name" "main" {
  certificate_arn = local.acm_cert_arn
  domain_name     = local.domain_name

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_domain_name" "msgstore" {
  certificate_arn = local.acm_cert_arn
  domain_name     = "msgstore.${local.domain_name}"

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_base_path_mapping" "main" {
  api_id      = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  domain_name = aws_api_gateway_domain_name.main.domain_name
}

resource "aws_api_gateway_base_path_mapping" "msgstore" {
  api_id      = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  domain_name = aws_api_gateway_domain_name.msgstore.domain_name
}

resource "aws_api_gateway_stage" "main" {
  stage_name    = "main"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  stage_description = "Trigger deploy due to main.tf change. Digest=${sha1(join("", [
    file("main.tf"),
  ]))}"

  # Deployment can only be created after integrations are created.
  depends_on = [
    aws_api_gateway_integration.root,
    aws_api_gateway_integration.main,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "main" {
  path_part   = "{proxy+}"
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.main.id
}

resource "aws_api_gateway_method" "root" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_rest_api.main.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "main" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.main.id
  http_method   = "ANY"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "root" {
  depends_on              = [aws_api_gateway_method.root]
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_rest_api.main.root_resource_id
  http_method             = "ANY"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.main.invoke_arn
  content_handling        = "CONVERT_TO_TEXT"
}

resource "aws_api_gateway_integration" "main" {
  depends_on              = [aws_api_gateway_method.main]
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.main.id
  http_method             = "ANY"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.main.invoke_arn
  content_handling        = "CONVERT_TO_TEXT"

  cache_key_parameters = ["method.request.path.proxy"]
}

resource "aws_lambda_permission" "main" {
  statement_id  = "allow-api-${aws_api_gateway_method.main.id}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:${data.aws_partition.current.id}:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:${aws_api_gateway_rest_api.main.id}/*/*/*"
}
