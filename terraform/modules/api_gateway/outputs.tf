output "api_id" {
  description = "The ID of the HTTP API"
  value       = aws_apigatewayv2_api.http_api.id
}

output "api_endpoint" {
  description = "The default invoke URL endpoint of the HTTP API"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "api_execution_arn" {
  description = "The execution ARN of the HTTP API"
  value       = aws_apigatewayv2_api.http_api.execution_arn
}
