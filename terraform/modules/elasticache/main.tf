# ElastiCache Redis: a query/response cache in front of RDS for the EC2 app tier. Locust tests at
# ~200 concurrent users showed requests queueing on the Postgres connection pool (db_pool_max_size
# defaults to 5 per app instance); caching the hot, read-heavy list endpoints (see app/cache.py)
# cuts most of that traffic before it ever reaches the database.

resource "random_password" "redis_auth_token" {
  # ElastiCache AUTH tokens must be 16-128 printable ASCII characters, excluding @ " / and space.
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_elasticache_subnet_group" "main" {
  name        = "campushub-${var.environment}-redis-subnet-group"
  description = "Subnet group for CampusHub ElastiCache Redis"
  subnet_ids  = var.app_subnet_ids

  tags = {
    Name = "campushub-${var.environment}-redis-subnet-group"
  }
}

# Parameter group tuned for a cache (not a durable store): evict the least-recently-used key once
# full rather than reject writes or evict only keys with a TTL set.
resource "aws_elasticache_parameter_group" "redis7" {
  name        = "campushub-${var.environment}-redis7-params"
  family      = "redis7"
  description = "CampusHub Redis 7 cache parameter group"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = {
    Name = "campushub-${var.environment}-redis7-params"
  }
}

# Store the AUTH token the same way the DB password is stored, so the EC2 app tier's existing
# Secrets Manager read path and IAM policy pattern cover this too.
resource "aws_secretsmanager_secret" "redis_auth_token" {
  name                    = "/campushub/${var.environment}/redis/auth-token"
  description             = "ElastiCache Redis AUTH token, read by the API at startup"
  recovery_window_in_days = 0

  tags = {
    Name = "campushub-${var.environment}-redis-auth-token"
  }
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = random_password.redis_auth_token.result
}

# Single-node by default (a cache, not a system of record -- a miss just falls back to Postgres),
# with at-rest and in-transit encryption plus AUTH on, since this carries the same traffic the DB
# connection otherwise would. num_cache_clusters > 1 adds read replicas with automatic failover.
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "campushub-${var.environment}-redis"
  description          = "CampusHub Redis cache for EC2 app tier read endpoints"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis7.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.redis_security_group_id]

  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result

  auto_minor_version_upgrade = true
  snapshot_retention_limit   = 0 # a cache: nothing here needs to survive a restore

  tags = {
    Name = "campushub-${var.environment}-redis"
  }
}
