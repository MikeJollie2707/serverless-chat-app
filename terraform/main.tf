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
  region = var.region1
}

provider "aws" {
  alias  = "secondary"
  region = var.region2
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

  stream_enabled = true

  replica {
    region_name = var.region2
  }

  tags = {
    Service = "serverless-chat"
  }
}

// DynamoDB for storing messages
resource "aws_dynamodb_table" "messages" {
  name         = "serverless-chat-messages"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "messageID"

  attribute {
    name = "messageID"
    type = "S"
  }

  stream_enabled = true

  replica {
    region_name = var.region2
  }
}

// SNS topic and SQS queue (used by broadcaster pattern)
resource "aws_sns_topic" "broadcasts1" {
  name = "serverless-chat-broadcasts1"
}

resource "aws_sns_topic" "broadcasts2" {
  provider = aws.secondary
  name     = "serverless-chat-broadcasts2"
}

resource "aws_sqs_queue" "broadcast_queue1" {
  name = "serverless-chat-queue1"
}

resource "aws_sqs_queue" "broadcast_queue2" {
  provider = aws.secondary
  name     = "serverless-chat-queue2"
}

// Fan out
resource "aws_sns_topic_subscription" "sns1_to_sqs1" {
  topic_arn = aws_sns_topic.broadcasts1.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.broadcast_queue1.arn
}

resource "aws_sns_topic_subscription" "sns1_to_sqs2" {
  topic_arn = aws_sns_topic.broadcasts1.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.broadcast_queue2.arn
}

resource "aws_sns_topic_subscription" "sns2_to_sqs1" {
  topic_arn = aws_sns_topic.broadcasts2.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.broadcast_queue1.arn
  provider  = aws.secondary
}

resource "aws_sns_topic_subscription" "sns2_to_sqs2" {
  topic_arn = aws_sns_topic.broadcasts2.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.broadcast_queue2.arn
  provider  = aws.secondary
}

// Give SNS the permission to deliver to SQS
resource "aws_sqs_queue_policy" "allow_sns1" {
  queue_url = aws_sqs_queue.broadcast_queue1.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.broadcast_queue1.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [aws_sns_topic.broadcasts1.arn, aws_sns_topic.broadcasts2.arn]
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "allow_sns2" {
  queue_url = aws_sqs_queue.broadcast_queue2.id
  provider  = aws.secondary

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.broadcast_queue2.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [aws_sns_topic.broadcasts1.arn, aws_sns_topic.broadcasts2.arn]
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
resource "aws_lambda_function" "on_connect1" {
  function_name    = "on_connect1"
  filename         = data.archive_file.on_connect_zip.output_path
  source_code_hash = data.archive_file.on_connect_zip.output_base64sha256
  handler          = "on_connect.on_connect"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_connect.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
    }
  }
}

resource "aws_lambda_function" "on_connect2" {
  provider         = aws.secondary
  function_name    = "on_connect2"
  filename         = data.archive_file.on_connect_zip.output_path
  source_code_hash = data.archive_file.on_connect_zip.output_base64sha256
  handler          = "on_connect.on_connect"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_connect.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
    }
  }
}

resource "aws_lambda_function" "on_disconnect1" {
  function_name    = "on_disconnect1"
  filename         = data.archive_file.on_disconnect_zip.output_path
  source_code_hash = data.archive_file.on_disconnect_zip.output_base64sha256
  handler          = "on_disconnect.on_disconnect"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_disconnect.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
    }
  }
}

resource "aws_lambda_function" "on_disconnect2" {
  provider         = aws.secondary
  function_name    = "on_disconnect2"
  filename         = data.archive_file.on_disconnect_zip.output_path
  source_code_hash = data.archive_file.on_disconnect_zip.output_base64sha256
  handler          = "on_disconnect.on_disconnect"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_disconnect.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
    }
  }
}

resource "aws_lambda_function" "on_default1" {
  function_name    = "on_default1"
  filename         = data.archive_file.on_default_zip.output_path
  source_code_hash = data.archive_file.on_default_zip.output_base64sha256
  handler          = "on_default.on_default"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_default.arn
}

resource "aws_lambda_function" "on_default2" {
  provider         = aws.secondary
  function_name    = "on_default2"
  filename         = data.archive_file.on_default_zip.output_path
  source_code_hash = data.archive_file.on_default_zip.output_base64sha256
  handler          = "on_default.on_default"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_default.arn
}

resource "aws_lambda_function" "on_message1" {
  function_name    = "on_message1"
  filename         = data.archive_file.on_message_zip.output_path
  source_code_hash = data.archive_file.on_message_zip.output_base64sha256
  handler          = "on_message.on_message"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_message.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
      "messageTableName"    = aws_dynamodb_table.messages.name
      "messageTopicARN"     = aws_sns_topic.broadcasts1.arn
    }
  }
}

resource "aws_lambda_function" "on_message2" {
  provider         = aws.secondary
  function_name    = "on_message2"
  filename         = data.archive_file.on_message_zip.output_path
  source_code_hash = data.archive_file.on_message_zip.output_base64sha256
  handler          = "on_message.on_message"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.on_message.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
      "messageTableName"    = aws_dynamodb_table.messages.name
      "messageTopicARN"     = aws_sns_topic.broadcasts2.arn
    }
  }
}

resource "aws_lambda_function" "broadcast_message1" {
  function_name    = "broadcast_message1"
  filename         = data.archive_file.broadcast_message_zip.output_path
  source_code_hash = data.archive_file.broadcast_message_zip.output_base64sha256
  handler          = "broadcast_message.broadcast_message"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.broadcast_message.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
      "apigwEndpoint"       = aws_apigatewayv2_stage.dev1.invoke_url
    }
  }
}

resource "aws_lambda_function" "broadcast_message2" {
  provider         = aws.secondary
  function_name    = "broadcast_message2"
  filename         = data.archive_file.broadcast_message_zip.output_path
  source_code_hash = data.archive_file.broadcast_message_zip.output_base64sha256
  handler          = "broadcast_message.broadcast_message"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.broadcast_message.arn
  environment {
    variables = {
      "connectionTableName" = aws_dynamodb_table.connections.name
      "apigwEndpoint"       = aws_apigatewayv2_stage.dev2.invoke_url
    }
  }
}

// WebSocket API
resource "aws_apigatewayv2_api" "ws_api1" {
  name                       = "serverless-chat-ws1"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

// Integrations
resource "aws_apigatewayv2_integration" "connect_integration1" {
  api_id           = aws_apigatewayv2_api.ws_api1.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_connect1.arn
}

resource "aws_apigatewayv2_integration" "disconnect_integration1" {
  api_id           = aws_apigatewayv2_api.ws_api1.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_disconnect1.arn
}

resource "aws_apigatewayv2_integration" "default_integration1" {
  api_id           = aws_apigatewayv2_api.ws_api1.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_default1.arn
}

resource "aws_apigatewayv2_integration" "message_integration1" {
  api_id           = aws_apigatewayv2_api.ws_api1.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_message1.arn
}

// Routes
resource "aws_apigatewayv2_route" "connect_route1" {
  api_id    = aws_apigatewayv2_api.ws_api1.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect_integration1.id}"
}

resource "aws_apigatewayv2_route" "disconnect_route1" {
  api_id    = aws_apigatewayv2_api.ws_api1.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect_integration1.id}"
}

resource "aws_apigatewayv2_route" "default_route1" {
  api_id    = aws_apigatewayv2_api.ws_api1.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.default_integration1.id}"
}

// application route for message actions. Expect clients to send JSON like { "action": "message", ... }
resource "aws_apigatewayv2_route" "message_route1" {
  api_id    = aws_apigatewayv2_api.ws_api1.id
  route_key = "sendmessage"
  target    = "integrations/${aws_apigatewayv2_integration.message_integration1.id}"
}

// Deployment and Stage
resource "aws_apigatewayv2_deployment" "ws_deployment1" {
  api_id = aws_apigatewayv2_api.ws_api1.id

  depends_on = [
    aws_apigatewayv2_route.connect_route1,
    aws_apigatewayv2_route.disconnect_route1,
    aws_apigatewayv2_route.default_route1,
    aws_apigatewayv2_route.message_route1,
  ]
}

resource "aws_apigatewayv2_stage" "dev1" {
  api_id        = aws_apigatewayv2_api.ws_api1.id
  name          = var.stage
  deployment_id = aws_apigatewayv2_deployment.ws_deployment1.id
  # auto_deploy   = true
}

// Permissions for API Gateway to invoke Lambdas
resource "aws_lambda_permission" "apigw_invoke_connect1" {
  statement_id  = "AllowExecutionFromAPIGWConnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_connect1.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region1}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api1.id}/*/$connect"
}

resource "aws_lambda_permission" "apigw_invoke_disconnect1" {
  statement_id  = "AllowExecutionFromAPIGWDisconnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_disconnect1.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region1}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api1.id}/*/$disconnect"
}

resource "aws_lambda_permission" "apigw_invoke_default1" {
  statement_id  = "AllowExecutionFromAPIGWDefault"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_default1.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region1}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api1.id}/*/$default"
}

resource "aws_lambda_permission" "apigw_invoke_message1" {
  statement_id  = "AllowExecutionFromAPIGWMessage"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_message1.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region1}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api1.id}/*/sendmessage"
}

// Second region
resource "aws_apigatewayv2_api" "ws_api2" {
  provider                   = aws.secondary
  name                       = "serverless-chat-ws2"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

// Integrations
resource "aws_apigatewayv2_integration" "connect_integration2" {
  provider         = aws.secondary
  api_id           = aws_apigatewayv2_api.ws_api2.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_connect2.arn
}

resource "aws_apigatewayv2_integration" "disconnect_integration2" {
  provider         = aws.secondary
  api_id           = aws_apigatewayv2_api.ws_api2.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_disconnect2.arn
}

resource "aws_apigatewayv2_integration" "default_integration2" {
  provider         = aws.secondary
  api_id           = aws_apigatewayv2_api.ws_api2.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_default2.arn
}

resource "aws_apigatewayv2_integration" "message_integration2" {
  provider         = aws.secondary
  api_id           = aws_apigatewayv2_api.ws_api2.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.on_message2.arn
}

// Routes
resource "aws_apigatewayv2_route" "connect_route2" {
  provider  = aws.secondary
  api_id    = aws_apigatewayv2_api.ws_api2.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect_integration2.id}"
}

resource "aws_apigatewayv2_route" "disconnect_route2" {
  provider  = aws.secondary
  api_id    = aws_apigatewayv2_api.ws_api2.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect_integration2.id}"
}

resource "aws_apigatewayv2_route" "default_route2" {
  provider  = aws.secondary
  api_id    = aws_apigatewayv2_api.ws_api2.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.default_integration2.id}"
}

// application route for message actions. Expect clients to send JSON like { "action": "message", ... }
resource "aws_apigatewayv2_route" "message_route2" {
  provider  = aws.secondary
  api_id    = aws_apigatewayv2_api.ws_api2.id
  route_key = "sendmessage"
  target    = "integrations/${aws_apigatewayv2_integration.message_integration2.id}"
}

// Deployment and Stage
resource "aws_apigatewayv2_deployment" "ws_deployment2" {
  provider = aws.secondary
  api_id   = aws_apigatewayv2_api.ws_api2.id

  depends_on = [
    aws_apigatewayv2_route.connect_route2,
    aws_apigatewayv2_route.disconnect_route2,
    aws_apigatewayv2_route.default_route2,
    aws_apigatewayv2_route.message_route2,
  ]
}

resource "aws_apigatewayv2_stage" "dev2" {
  provider      = aws.secondary
  api_id        = aws_apigatewayv2_api.ws_api2.id
  name          = var.stage
  deployment_id = aws_apigatewayv2_deployment.ws_deployment2.id
  # auto_deploy   = true
}

// Permissions for API Gateway to invoke Lambdas
resource "aws_lambda_permission" "apigw_invoke_connect2" {
  provider      = aws.secondary
  statement_id  = "AllowExecutionFromAPIGWConnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_connect2.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region2}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api2.id}/*/$connect"
}

resource "aws_lambda_permission" "apigw_invoke_disconnect2" {
  provider      = aws.secondary
  statement_id  = "AllowExecutionFromAPIGWDisconnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_disconnect2.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region2}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api2.id}/*/$disconnect"
}

resource "aws_lambda_permission" "apigw_invoke_default2" {
  provider      = aws.secondary
  statement_id  = "AllowExecutionFromAPIGWDefault"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_default2.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region2}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api2.id}/*/$default"
}

resource "aws_lambda_permission" "apigw_invoke_message2" {
  provider      = aws.secondary
  statement_id  = "AllowExecutionFromAPIGWMessage"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_message2.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region2}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.ws_api2.id}/*/sendmessage"
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
        Resource = [aws_sqs_queue.broadcast_queue1.arn, aws_sqs_queue.broadcast_queue2.arn]
      }
    ]
  })
}

resource "aws_lambda_event_source_mapping" "sqs1_trigger" {
  event_source_arn = aws_sqs_queue.broadcast_queue1.arn
  function_name    = aws_lambda_function.broadcast_message1.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_lambda_event_source_mapping" "sqs2_trigger" {
  provider         = aws.secondary
  event_source_arn = aws_sqs_queue.broadcast_queue2.arn
  function_name    = aws_lambda_function.broadcast_message2.arn
  batch_size       = 10
  enabled          = true
}
