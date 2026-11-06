output "data_tools_function_name" {
  description = "Name of the snapshot Lambda (used by scripts/snapshot_export.sh and snapshot_restore.sh)"
  value       = aws_lambda_function.data_tools.function_name
}
