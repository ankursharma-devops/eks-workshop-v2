variable "cluster_subnet_ids" {
  type = list(string)
}

variable "redis_security_group" {
  type = string
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "elasticache-redis-subnet"
  subnet_ids = var.cluster_subnet_ids
}

resource "aws_cloudwatch_log_group" "checkout_redis" {
  name = "aws-redis"
}

resource "aws_elasticache_cluster" "checkout_redis" {
  cluster_id        = "checkout-cache-redis"
  engine            = "redis"
  node_type         = "cache.t4g.micro"
  num_cache_nodes   = 1
  port              = 6379
  apply_immediately = true
	subnet_group_name = aws_elasticache_subnet_group.redis_subnet_group.name
	security_group_ids = var.redis_security_group
	engine_version     = 6.0.5
	parameter_group_name = default.redis6.x
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.checkout_redis.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }
}


output "environment" {
  value = <<EOF
export REDIS_ENDPOINT="${aws_elasticache_cluster.checkout_redis.cache_nodes[0].address}:${aws_elasticache_cluster.checkout_redis.cache_nodes[0].port}"
EOF
}
