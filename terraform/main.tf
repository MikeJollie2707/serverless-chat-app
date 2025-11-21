terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "archive" {}

// DynamoDB table (single-region; can be converted to a global table if you add a second region)
resource "aws_dynamodb_table" "connections" {
  name         = "serverless-chat-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connectionId"

  attribute {
    name = "connectionId"
    type = "S"
  }

  tags = {
    Service = "serverless-chat"
  }
}

// SNS topic and SQS queue (used by broadcaster pattern)
resource "aws_sns_topic" "broadcasts" {
  name = "serverless-chat-broadcasts"
}

resource "aws_sqs_queue" "broadcast_queue" {
  name = "serverless-chat-queue"
}

resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.broadcasts.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.broadcast_queue.arn
}

// Give SNS the permission to deliver to SQS
resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.broadcast_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.broadcast_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.broadcasts.arn
          }
        }
      }
    ]
  })
}

// IAM role for on_connect
resource "aws_iam_role" "on_connect" {
  name = "serverless_chat_on_connect"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_on_connect_basic_exec" {
  role       = aws_iam_role.on_connect.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb_write" {
  name = "lambda-dynamodb-write"
  role = aws_iam_role.on_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
        ]
        Resource = "*"
      }
    ]
  })
}

// IAM role for on_disconnect
resource "aws_iam_role" "on_disconnect" {
  name = "serverless_chat_on_disconnect"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_on_disconnect_basic_exec" {
  role       = aws_iam_role.on_disconnect.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb_delete" {
  name = "lambda-dynamodb-write"
  role = aws_iam_role.on_disconnect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
        ]
        Resource = "*"
      }
    ]
  })
}

// IAM role for on_default
resource "aws_iam_role" "on_default" {
  name = "serverless_chat_on_default"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_on_default_basic_exec" {
  role       = aws_iam_role.on_default.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// IAM role for on_message
resource "aws_iam_role" "on_message" {
  name = "serverless_chat_on_message"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_on_message_basic_exec" {
  role       = aws_iam_role.on_message.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sns_publish" {
  name = "lambda-sns-publish"
  role = aws_iam_role.on_message.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish",
          # "sqs:SendMessage",
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
        ]
        Resource = "*"
      }
    ]
  })
}

// IAM role for broadcast_message
resource "aws_iam_role" "broadcast_message" {
  name = "serverless_chat_broadcast_message"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_broadcast_message_basic_exec" {
  role       = aws_iam_role.broadcast_message.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb_scan" {
  name = "lambda-dynamodb-write"
  role = aws_iam_role.broadcast_message.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          # "execute-api:Invoke",
          "execute-api:ManageConnections"
        ]
        Resource = "*"
      }
    ]
  })
}

// Package each lambda file into a separate zip using archive provider. Assumes files are in ../lambda/*.py
data "archive_file" "on_connect_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/on_connect.py"
  output_path = "${path.module}/build/on_connect.zip"
}

data "archive_file" "on_disconnect_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/on_disconnect.py"
  output_path = "${path.module}/build/on_disconnect.zip"
}

data "archive_file" "on_default_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/on_default.py"
  output_path = "${path.module}/build/on_default.zip"
}

data "archive_file" "on_message_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/on_message.py"
  output_path = "${path.module}/build/on_message.zip"
}

data "archive_file" "broadcast_message_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/broadcast_message.py"
  output_path = "${path.module}/build/broadcast_message.zip"
}

// Lambda functions
resource "aws_lambda_function" "on_connect" {
  function_name    = "on_connect"
  filename         = data.archive_file.on_connect_zip.output_path
  source_code_hash = data.archive_file.on_connect_zip.output_base64sha256
  handler          = "on_connect.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_connect.arn
}

resource "aws_lambda_function" "on_disconnect" {
  function_name    = "on_disconnect"
  filename         = data.archive_file.on_disconnect_zip.output_path
  source_code_hash = data.archive_file.on_disconnect_zip.output_base64sha256
  handler          = "on_disconnect.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_disconnect.arn
}

resource "aws_lambda_function" "on_default" {
  function_name    = "on_default"
  filename         = data.archive_file.on_default_zip.output_path
  source_code_hash = data.archive_file.on_default_zip.output_base64sha256
  handler          = "on_default.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_default.arn
}

resource "aws_lambda_function" "on_message" {
  function_name    = "on_message"
  filename         = data.archive_file.on_message_zip.output_path
  source_code_hash = data.archive_file.on_message_zip.output_base64sha256
  handler          = "on_message.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_message.arn
}

resource "aws_lambda_function" "broadcast_message" {
  function_name    = "broadcast_message"
  filename         = data.archive_file.broadcast_message_zip.output_path
  source_code_hash = data.archive_file.broadcast_message_zip.output_base64sha256
  handler          = "broadcast_message.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.broadcast_message.arn
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.broadcasts.arn
    }
  }
}

// WebSocket API
resource "aws_apigatewayv2_api" "ws_api" {
  name                       = "serverless-chat-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

// Integrations
resource "aws_apigatewayv2_integration" "connect_integration" {
  api_id           = aws_apigatewayv2_api.ws_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_connect.arn
}

resource "aws_apigatewayv2_integration" "disconnect_integration" {
  api_id           = aws_apigatewayv2_api.ws_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_disconnect.arn
}

resource "aws_apigatewayv2_integration" "default_integration" {
  api_id           = aws_apigatewayv2_api.ws_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_default.arn
}

resource "aws_apigatewayv2_integration" "message_integration" {
  api_id           = aws_apigatewayv2_api.ws_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_message.arn
}

// Routes
resource "aws_apigatewayv2_route" "connect_route" {
  api_id    = aws_apigatewayv2_api.ws_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect_integration.id}"
}

resource "aws_apigatewayv2_route" "disconnect_route" {
  api_id    = aws_apigatewayv2_api.ws_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect_integration.id}"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.ws_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.default_integration.id}"
}

// application route for message actions. Expect clients to send JSON like { "action": "message", ... }
resource "aws_apigatewayv2_route" "message_route" {
  api_id    = aws_apigatewayv2_api.ws_api.id
  route_key = "message"
  target    = "integrations/${aws_apigatewayv2_integration.message_integration.id}"
}

// Deployment and Stage
resource "aws_apigatewayv2_deployment" "ws_deployment" {
  api_id = aws_apigatewayv2_api.ws_api.id

  depends_on = [
    aws_apigatewayv2_route.connect_route,
    aws_apigatewayv2_route.disconnect_route,
    aws_apigatewayv2_route.default_route,
    aws_apigatewayv2_route.message_route,
  ]
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id        = aws_apigatewayv2_api.ws_api.id
  name          = "dev"
  deployment_id = aws_apigatewayv2_deployment.ws_deployment.id
  auto_deploy   = true
}

// Permissions for API Gateway to invoke Lambdas
resource "aws_lambda_permission" "apigw_invoke_connect" {
  statement_id  = "AllowExecutionFromAPIGWConnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api.id}/*/$connect"
}

resource "aws_lambda_permission" "apigw_invoke_disconnect" {
  statement_id  = "AllowExecutionFromAPIGWDisconnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api.id}/*/$disconnect"
}

resource "aws_lambda_permission" "apigw_invoke_default" {
  statement_id  = "AllowExecutionFromAPIGWDefault"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_default.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api.id}/*/$default"
}

resource "aws_lambda_permission" "apigw_invoke_message" {
  statement_id  = "AllowExecutionFromAPIGWMessage"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api.id}/*/message"
}

// Data source to get account ID for permissions
data "aws_caller_identity" "current" {}

// Inline Lambda permission to consume SQS
resource "aws_iam_role_policy" "sqs_lambda_trigger" {
  name = "sqs-lambda-trigger"
  role = aws_iam_role.broadcast_message.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow Lambda to poll and delete SQS messages
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.broadcast_queue.arn
      }
    ]
  })
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.broadcast_queue.arn
  function_name    = aws_lambda_function.broadcast_message.arn
  batch_size       = 10
  enabled          = true
}
