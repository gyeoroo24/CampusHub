output "lambda_function_arns" {
  description = "Map of Lambda function ARNs"
  value       = { for k, v in aws_lambda_function.services : k => v.arn }
}

output "lambda_invoke_arns" {
  description = "Map of Lambda function invocation ARNs for API Gateway integration"
  value       = { for k, v in aws_lambda_function.services : k => v.invoke_arn }
}

output "lambda_function_names" {
  description = "Map of Lambda function names"
  value       = { for k, v in aws_lambda_function.services : k => v.function_name }
}

output "lambda_execution_role_arn" {
  description = "The ARN of the IAM role used by Lambdas"
  value       = aws_iam_role.lambda_exec.arn
}
