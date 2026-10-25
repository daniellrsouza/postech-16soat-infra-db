data "aws_ssm_parameter" "shared" {
  for_each = toset(["eks-cluster-name", "db-host", "db-port", "db-master-secret-arn"])
  name     = "/${var.project_name}/shared/${each.key}"
}

# D30: senha master gerenciada pelo RDS no Secrets Manager.
data "aws_secretsmanager_secret_version" "master" {
  secret_id = data.aws_ssm_parameter.shared["db-master-secret-arn"].value
}

locals {
  master = jsondecode(data.aws_secretsmanager_secret_version.master.secret_string)

  db_host = data.aws_ssm_parameter.shared["db-host"].value
  db_port = data.aws_ssm_parameter.shared["db-port"].value

  # D29: um database e dois usuários por ambiente.
  db_name     = "tech_challenge_${var.environment}"
  app_user    = "app_${var.environment}"
  lambda_user = "lambda_${var.environment}"

  # Papel de grupo (vale para a instância toda): a migration da aplicação dá
  # SELECT em clientes para ele; o isolamento entre ambientes vem do CONNECT.
  read_clientes_role = "leitura_clientes"

  # Database inicial criado pelo RDS (stacks/shared, db_name).
  admin_db = "postgres_admin"
}

# P5 (revisto): segredos do ambiente gerados aqui e publicados no SSM.
resource "random_password" "app" {
  length  = 32
  special = false
}

resource "random_password" "lambda" {
  length  = 32
  special = false
}

# JWT_SECRET do ambiente: compartilhado por Lambda e aplicação (HS256, D6).
resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "kubernetes_secret_v1" "bootstrap" {
  metadata {
    name      = "db-bootstrap"
    namespace = var.environment
  }

  data = {
    PGHOST          = local.db_host
    PGPORT          = local.db_port
    PGUSER          = local.master.username
    PGPASSWORD      = local.master.password
    PGDATABASE      = "postgres"
    PGSSLMODE       = "require"
    DB_NAME         = local.db_name
    APP_USER        = local.app_user
    APP_PASSWORD    = random_password.app.result
    LAMBDA_USER     = local.lambda_user
    LAMBDA_PASSWORD = random_password.lambda.result
    READ_ROLE       = local.read_clientes_role
    ADMIN_DB        = local.admin_db
  }
}

# P8: o runner do GitHub não alcança o RDS privado; o Job roda no cluster.
# Idempotente: pode rodar de novo (troca de senha, por exemplo).
resource "kubernetes_job_v1" "bootstrap" {
  metadata {
    # O nome muda quando o script ou as senhas mudam, forçando nova execução.
    name      = "db-bootstrap-${substr(sha256("${local.script}${random_password.app.result}${random_password.lambda.result}"), 0, 8)}"
    namespace = var.environment
  }

  spec {
    # Sem ttl_seconds_after_finished: se o Kubernetes apagasse o Job concluído,
    # o Terraform o recriaria a cada plan.
    backoff_limit = 3

    template {
      metadata {}

      spec {
        restart_policy = "Never"

        container {
          name    = "psql"
          image   = var.bootstrap_image
          command = ["sh", "-c", local.script]

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.bootstrap.metadata[0].name
            }
          }

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
    update = "5m"
  }
}

locals {
  script = <<-EOT
    set -eu
    psql -v ON_ERROR_STOP=1 \
      -v db="$DB_NAME" -v app_user="$APP_USER" -v app_pass="$APP_PASSWORD" \
      -v lambda_user="$LAMBDA_USER" -v lambda_pass="$LAMBDA_PASSWORD" -v read_role="$READ_ROLE"       -v admin_db="$ADMIN_DB" <<'SQL'
    SELECT format('CREATE ROLE %I NOLOGIN', :'read_role')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'read_role') \gexec
    SELECT format('CREATE ROLE %I LOGIN', :'app_user')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user') \gexec
    SELECT format('CREATE ROLE %I LOGIN', :'lambda_user')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'lambda_user') \gexec
    ALTER ROLE :"app_user" WITH LOGIN PASSWORD :'app_pass';
    ALTER ROLE :"lambda_user" WITH LOGIN PASSWORD :'lambda_pass';
    GRANT :"read_role" TO :"lambda_user";
    GRANT :"app_user" TO CURRENT_USER;
    SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'app_user')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') \gexec
    ALTER DATABASE :"db" OWNER TO :"app_user";
    REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
    GRANT CONNECT ON DATABASE :"db" TO :"app_user", :"lambda_user";
    -- O database inicial do RDS herda CONNECT para PUBLIC; ninguém além do
    -- master precisa dele.
    REVOKE CONNECT ON DATABASE :"admin_db" FROM PUBLIC;
    \c :"db"
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
    GRANT USAGE ON SCHEMA public TO :"read_role";
    SQL
    echo "bootstrap ok: $DB_NAME"
  EOT
}
