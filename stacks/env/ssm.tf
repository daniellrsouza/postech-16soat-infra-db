# Contrato com a Lambda e o pipeline da aplicação (P4/P5).
locals {
  ssm_strings = {
    "db-name"        = local.db_name
    "db-app-user"    = local.app_user
    "db-lambda-user" = local.lambda_user
  }
  ssm_secrets = {
    "db-app-password"    = random_password.app.result
    "db-lambda-password" = random_password.lambda.result
    "jwt-secret"         = random_password.jwt.result
  }
}

resource "aws_ssm_parameter" "strings" {
  for_each = local.ssm_strings

  name  = "/${var.project_name}/${var.environment}/${each.key}"
  type  = "String"
  value = each.value

  depends_on = [kubernetes_job_v1.bootstrap]
}

resource "aws_ssm_parameter" "secrets" {
  for_each = local.ssm_secrets

  name  = "/${var.project_name}/${var.environment}/${each.key}"
  type  = "SecureString"
  value = each.value

  depends_on = [kubernetes_job_v1.bootstrap]
}

output "db_name" {
  value = local.db_name
}

output "ssm_prefix" {
  value = "/${var.project_name}/${var.environment}"
}
