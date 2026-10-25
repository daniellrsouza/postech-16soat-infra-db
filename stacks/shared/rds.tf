# Saídas do infra-k8s publicadas no SSM (P4).
data "aws_ssm_parameter" "k8s" {
  for_each = toset(["vpc-id", "private-subnet-ids", "eks-cluster-sg-id"])
  name     = "/${var.project_name}/shared/${each.key}"
}

locals {
  vpc_id             = data.aws_ssm_parameter.k8s["vpc-id"].value
  private_subnet_ids = split(",", data.aws_ssm_parameter.k8s["private-subnet-ids"].value)
  eks_cluster_sg_id  = data.aws_ssm_parameter.k8s["eks-cluster-sg-id"].value
}

resource "aws_db_subnet_group" "this" {
  name        = "dbsubnet-${var.project_name}"
  description = "Subnets privadas (sem internet) do RDS"
  subnet_ids  = local.private_subnet_ids
}

# Security group que os clientes do banco (Lambda) usam; o RDS aceita conexões
# de quem tem este SG e dos nós do EKS.
resource "aws_security_group" "db_clients" {
  name        = "dbclients-${var.project_name}"
  description = "Clientes autorizados a conectar no RDS (Lambda)"
  vpc_id      = local.vpc_id

  tags = { Name = "dbclients-${var.project_name}" }
}

resource "aws_vpc_security_group_egress_rule" "db_clients_to_db" {
  security_group_id            = aws_security_group.db_clients.id
  description                  = "Saida para o Postgres"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_security_group" "db" {
  name        = "rds-${var.project_name}"
  description = "RDS PostgreSQL: so a partir dos nos do EKS e dos clientes autorizados"
  vpc_id      = local.vpc_id

  tags = { Name = "rds-${var.project_name}" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_eks" {
  security_group_id            = aws_security_group.db.id
  description                  = "Aplicacao e Job de bootstrap (nos do EKS)"
  referenced_security_group_id = local.eks_cluster_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "db_from_clients" {
  security_group_id            = aws_security_group.db.id
  description                  = "Lambda de autenticacao"
  referenced_security_group_id = aws_security_group.db_clients.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_parameter_group" "this" {
  name        = "pg16-${var.project_name}"
  family      = "postgres16"
  description = "TLS obrigatorio e log de consultas lentas"

  # Parâmetro estático: a AWS registra pending-reboot (sem isso, todo plan
  # mostraria diferença). Na criação da instância ele já vale.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.slow_query_ms)
  }
}

resource "aws_db_instance" "this" {
  identifier     = "rds-${var.project_name}"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  # Database inicial vazio; os databases de cada ambiente são criados pelo
  # stack env (P8). D30: a senha master fica no Secrets Manager.
  db_name                     = "postgres_admin"
  username                    = "postgres_admin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = var.backup_retention_days
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Ambiente de laboratório: destruir sem snapshot final.
  deletion_protection = false
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = ["postgresql"]
}
