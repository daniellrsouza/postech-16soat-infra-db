# Contrato com os demais repositórios (P4).
locals {
  ssm_parameters = {
    "db-host"              = aws_db_instance.this.address
    "db-port"              = tostring(aws_db_instance.this.port)
    "db-master-secret-arn" = aws_db_instance.this.master_user_secret[0].secret_arn
    "db-clients-sg-id"     = aws_security_group.db_clients.id
  }
}

resource "aws_ssm_parameter" "shared" {
  for_each = local.ssm_parameters

  name  = "/${var.project_name}/shared/${each.key}"
  type  = "String"
  value = each.value
}

output "db_host" {
  value = aws_db_instance.this.address
}

output "db_clients_sg_id" {
  value = aws_security_group.db_clients.id
}
