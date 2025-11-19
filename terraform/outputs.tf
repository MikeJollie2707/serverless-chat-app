output "websocket_endpoint" {
  description = "WebSocket endpoint URL to connect clients to"
  value       = "wss://${aws_apigatewayv2_api.ws_api.api_endpoint}/${aws_apigatewayv2_stage.dev.name}"
}

output "dynamodb_table_name" {
  description = "DynamoDB table used to store connections"
  value       = aws_dynamodb_table.connections.name
}

output "sns_topic_arn" {
  description = "SNS topic ARN used for broadcasts"
  value       = aws_sns_topic.broadcasts.arn
}

output "sqs_queue_url" {
  description = "SQS queue URL subscribed to SNS topic"
  value       = aws_sqs_queue.broadcast_queue.id
}

output "lambda_functions" {
  description = "Map of Lambda function names to ARNs"
  value = {
    on_connect        = aws_lambda_function.on_connect.arn
    on_disconnect     = aws_lambda_function.on_disconnect.arn
    on_default        = aws_lambda_function.on_default.arn
    on_message        = aws_lambda_function.on_message.arn
    broadcast_message = aws_lambda_function.broadcast_message.arn
  }
}
