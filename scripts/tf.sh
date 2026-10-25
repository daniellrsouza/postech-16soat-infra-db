#!/usr/bin/env bash
# Wrapper do Terraform para os stacks deste repositório.
#
#   scripts/tf.sh shared <comando terraform> [args...]
#   scripts/tf.sh env <homolog|prod> <comando terraform> [args...]
#
# Exemplos:
#   scripts/tf.sh shared plan
#   scripts/tf.sh env homolog apply -auto-approve
#
# Antes do comando, garante o bucket de state (D17) e roda `terraform init`
# com o backend da conta atual (D19: tfstate-<id-da-conta>-postech-16soat).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"

usage() { sed -n '2,10p' "$0" >&2; exit 1; }

STACK="${1:-}"; shift || usage
case "$STACK" in
  shared)
    STATE_KEY="infra-db/shared.tfstate"
    TF_ARGS=()
    ;;
  env)
    ENVIRONMENT="${1:-}"; shift || usage
    [[ "$ENVIRONMENT" == "homolog" || "$ENVIRONMENT" == "prod" ]] || usage
    STATE_KEY="infra-db/env/${ENVIRONMENT}.tfstate"
    TF_ARGS=(-var "environment=${ENVIRONMENT}")
    ;;
  *) usage ;;
esac
[ $# -ge 1 ] || usage
COMMAND="$1"; shift

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="tfstate-${ACCOUNT_ID}-postech-16soat"

ensure_bucket() {
  local err
  if err="$(aws s3api head-bucket --bucket "$BUCKET" 2>&1)"; then
    return
  fi
  # Só cria quando o bucket não existe (404). Qualquer outro erro, como o 403
  # da política voc-cancel-cred quando a sessão do lab encerra, interrompe.
  if [[ "$err" != *"404"* && "$err" != *"Not Found"* ]]; then
    echo "Não foi possível verificar o bucket $BUCKET: $err" >&2
    echo "Sessão do AWS Academy encerrada? Renove as credenciais." >&2
    exit 1
  fi
  echo "Criando bucket de state $BUCKET" >&2
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  fi
  aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
}

ensure_bucket

cd "$ROOT/stacks/$STACK"
terraform init -input=false -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=${STATE_KEY}" \
  -backend-config="region=${REGION}" >/dev/null

# Comandos que aceitam -var; os demais (output, state, show) rodam sem eles.
case "$COMMAND" in
  plan|apply|destroy|import|refresh|console)
    exec terraform "$COMMAND" -input=false "${TF_ARGS[@]}" "$@"
    ;;
  *)
    exec terraform "$COMMAND" "$@"
    ;;
esac
