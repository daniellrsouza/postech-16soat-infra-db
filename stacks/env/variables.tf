variable "environment" {
  description = "Ambiente: homolog (branch develop) ou prod (branch main)"
  type        = string

  validation {
    condition     = contains(["homolog", "prod"], var.environment)
    error_message = "environment deve ser homolog ou prod."
  }
}

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

variable "bootstrap_image" {
  description = "Imagem com psql usada pelo Job de bootstrap"
  type        = string
  default     = "postgres:16-alpine"
}
