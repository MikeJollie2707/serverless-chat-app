output "websocket_endpoint1" {
  description = "WebSocket endpoint URL to connect clients to"
  value       = aws_apigatewayv2_stage.dev1.invoke_url
}

output "websocket_endpoint2" {
  description = "WebSocket endpoint URL to connect clients to"
  value       = aws_apigatewayv2_stage.dev2.invoke_url
}

output "dynamodb_table_name" {
  description = "DynamoDB table used to store connections"
  value       = aws_dynamodb_table.connections.name
}

output "sns_topic_arn1" {
  description = "SNS topic ARN used for broadcasts"
  value       = aws_sns_topic.broadcasts1.arn
}

output "sns_topic_arn2" {
  description = "SNS topic ARN used for broadcasts"
  value       = aws_sns_topic.broadcasts2.arn
}

output "sqs_queue_url1" {
  description = "SQS queue URL subscribed to SNS topic"
  value       = aws_sqs_queue.broadcast_queue1.id
}

output "sqs_queue_url2" {
  description = "SQS queue URL subscribed to SNS topic"
  value       = aws_sqs_queue.broadcast_queue2.id
}

output "lambda_functions" {
  description = "Map of Lambda function names to ARNs"
  value = {
    on_connect1        = aws_lambda_function.on_connect1.arn
    on_disconnect1     = aws_lambda_function.on_disconnect1.arn
    on_default1        = aws_lambda_function.on_default1.arn
    on_message1        = aws_lambda_function.on_message1.arn
    broadcast_message1 = aws_lambda_function.broadcast_message1.arn

    on_connect2        = aws_lambda_function.on_connect2.arn
    on_disconnect2     = aws_lambda_function.on_disconnect2.arn
    on_default2        = aws_lambda_function.on_default2.arn
    on_message2        = aws_lambda_function.on_message2.arn
    broadcast_message2 = aws_lambda_function.broadcast_message2.arn
  }
}
