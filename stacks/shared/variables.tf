variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo dos recursos (igual ao do infra-k8s)"
  type        = string
  default     = "tech-challenge"
}

variable "engine_version" {
  description = "Versão major do PostgreSQL"
  type        = string
  default     = "16"
}

# D28: db.t3.micro Single-AZ (orçamento do lab, D31).
variable "instance_class" {
  description = "Classe da instância RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage_gb" {
  description = "Disco gp3 em GB"
  type        = number
  default     = 20
}

variable "backup_retention_days" {
  description = "Retenção dos backups automáticos"
  type        = number
  default     = 1
}

variable "slow_query_ms" {
  description = "Consultas acima deste tempo vão para o log do Postgres (análise de performance)"
  type        = number
  default     = 500
}
