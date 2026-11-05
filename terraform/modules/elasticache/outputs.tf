output "primary_endpoint_address" {
  description = "Primary (write) endpoint hostname for the Redis replication group"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint hostname (same as primary when num_cache_clusters = 1)"
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.redis.port
}

output "replication_group_id" {
  description = "The ElastiCache replication group ID"
  value       = aws_elasticache_replication_group.redis.id
}

output "auth_token_secret_arn" {
  description = "Secrets Manager secret ARN holding the Redis AUTH token, read by the API at startup"
  value       = aws_secretsmanager_secret.redis_auth_token.arn
}
