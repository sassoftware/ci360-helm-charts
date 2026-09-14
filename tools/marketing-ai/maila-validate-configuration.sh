#!/usr/bin/env bash
###############################################################################
#
# maila-validate-configuration.sh
#
# Pre-deployment configuration validator for CI360 Marketing AI (MAI)
# Local Agent. Validates cloud resources, Kubernetes state, and secrets
# against the Helm values file — catching misconfigurations before
# deployment. The script is READ-ONLY and never mutates any resource.
#
# Supported providers: aws | azure | gcp
#
# Usage:
#   ./maila-validate-configuration.sh --cloud <provider> --values <file> [OPTIONS]
#
# Options:
#   --cloud <provider>   Cloud provider: aws, azure, gcp        (required)
#   --values <file>      Helm values YAML file                  (required)
#   --namespace <ns>     K8s namespace for secret/SA checks
#   --aws-profile <name> AWS CLI profile (or AWS_PROFILE env)
#   --gcp-project <id>   GCP project override (default: from values)
#   --skip-cloud         Skip cloud API checks
#   --skip-k8s           Skip Kubernetes checks
#   --help               Show usage
#
# Examples:
#   ./maila-validate-configuration.sh --cloud aws   --values values-aws.yaml   --namespace mai-ns
#   ./maila-validate-configuration.sh --cloud azure --values values-azure.yaml --namespace mai-ns
#   ./maila-validate-configuration.sh --cloud gcp   --values values-gcp.yaml   --namespace mai-ns
#   ./maila-validate-configuration.sh --cloud gcp   --values values-gcp.yaml   --gcp-project my-proj
#   ./maila-validate-configuration.sh --cloud aws   --values values-aws.yaml   --skip-cloud --skip-k8s
#
# Validation steps:
#   0. Pre-requisite tools    — kubectl, helm, yq, cloud CLI
#   1. Required values        — storageBucket, storagePrefix, gateway host,
#                               cloud-specific anchors, fleets config
#   2. Cloud resource access  — authentication, buckets, IAM roles/SAs,
#                               container registries, APIs
#   3. Cluster connectivity   — nodes, node pools
#   4. Storage classes        — existence, provisioner type
#   5. Namespace & secrets    — SA annotations, auth/postgres/pgpool/fleets secrets
#   6. Resource quotas        — quota & PVC inventory
#
# Exit codes:
#   0  All checks passed (or passed with warnings)
#   1  One or more checks failed
#
# Notes:
#   • YAML anchors (&name / *name) are resolved automatically.
#   • Works with yq (mikefarah) or falls back to grep/sed.
#   • Inline comments (including checkov directives) are stripped.
#
###############################################################################

set -euo pipefail

# ─────────────────────────── Colors ───────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
CHECKS=0

# ─────────────────────────── Logging ──────────────────────────
log_header()  { echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"; }
log_section() { echo -e "\n${BOLD}── $1 ──${NC}"; }
log_pass()    { CHECKS=$((CHECKS+1)); echo -e "  ${GREEN}✅ PASS${NC}: $1"; }
log_fail()    { CHECKS=$((CHECKS+1)); ERRORS=$((ERRORS+1)); echo -e "  ${RED}❌ FAIL${NC}: $1"; }
log_warn()    { CHECKS=$((CHECKS+1)); WARNINGS=$((WARNINGS+1)); echo -e "  ${YELLOW}⚠️  WARN${NC}: $1"; }
log_info()    { echo -e "  ℹ️  INFO: $1"; }

# ─────────────────────────── Usage ────────────────────────────
usage() {
cat <<EOF
Usage: $0 --cloud <aws|azure|gcp> --values <file> [OPTIONS]

Required:
  --cloud         aws, azure, or gcp
  --values        Path to the Helm values YAML file

Optional:
  --namespace     K8s namespace (SA annotations, secrets)
  --aws-profile   AWS CLI profile name to use (e.g. my-sso-profile)
                  Can also be set via AWS_PROFILE environment variable
  --gcp-project   GCP project ID override (default: read from values file)
  --skip-cloud    Skip cloud CLI checks
  --skip-k8s      Skip Kubernetes checks
  --help          Show this message

Examples:
  $0 --cloud aws --values values-aws.yaml --namespace mai-ns --aws-profile my-sso-profile
  $0 --cloud azure --values values-azure.yaml --namespace mai-ns
  $0 --cloud gcp --values values-gcp.yaml --namespace mai-ns
  $0 --cloud gcp --values values-gcp.yaml --namespace mai-ns --gcp-project my-project-id
  $0 --cloud aws --values values-aws.yaml --skip-cloud
EOF
exit 0
}

# ─────────────────────────── YAML Parsing ─────────────────────
YQ_CMD=""
YQ_VERSION=""

declare -A YAML_ANCHORS

detect_yq() {
  if command -v yq &>/dev/null; then
    if yq --version 2>&1 | grep -q "mikefarah"; then
      YQ_CMD="yq_mikefarah"
      YQ_VERSION="mikefarah"
    elif yq --version 2>&1 | grep -q "version"; then
      YQ_CMD="yq_mikefarah"
      YQ_VERSION="mikefarah"
    else
      YQ_CMD="yq_kislyuk"
      YQ_VERSION="kislyuk"
    fi
  fi
}

parse_yaml_anchors() {
  local file="$1"
  YAML_ANCHORS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ \&([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+(.*) ]]; then
      local anchor_name="${BASH_REMATCH[1]}"
      local anchor_value="${BASH_REMATCH[2]}"
      anchor_value=$(echo "$anchor_value" | sed 's/[[:space:]]\+#.*//' | tr -d '"' | tr -d "'" | tr -d '\r' | xargs 2>/dev/null || echo "$anchor_value")
      YAML_ANCHORS["$anchor_name"]="$anchor_value"
    fi
  done < "$file"
}

resolve_anchor() {
  local value="$1"
  if [[ "$value" =~ ^\*([a-zA-Z_][a-zA-Z0-9_]*)$ ]]; then
    local anchor_name="${BASH_REMATCH[1]}"
    if [[ -n "${YAML_ANCHORS[$anchor_name]:-}" ]]; then
      echo "${YAML_ANCHORS[$anchor_name]}"
      return 0
    fi
  fi
  echo "$value"
}

is_unresolved_anchor() {
  local value="$1"
  [[ "$value" =~ ^\*[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

yaml_get() {
  local file="$1"
  local key_path="$2"
  local result=""

  if [[ "$YQ_CMD" == "yq_mikefarah" ]]; then
    result=$(yq eval ".${key_path}" "$file" 2>/dev/null | grep -v "^null$" || echo "")
  elif [[ "$YQ_CMD" == "yq_kislyuk" ]]; then
    result=$(yq -r ".${key_path} // empty" "$file" 2>/dev/null || echo "")
  else
    local key=$(echo "$key_path" | awk -F. '{print $NF}')
    result=$(grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null \
      | head -1 \
      | sed 's/[[:space:]]*#.*//' \
      | sed 's/.*:[[:space:]]*//' \
      | tr -d '\r' \
      | xargs 2>/dev/null || echo "")
  fi

  # Strip inline comments from result
  result=$(echo "$result" | sed 's/[[:space:]]\+#.*//' | tr -d '\r' | xargs 2>/dev/null || echo "$result")
  if [[ "$result" == '""' || "$result" == "''" ]]; then
    result=""
  else
    result=$(echo "$result" | tr -d '"' | tr -d "'" | xargs 2>/dev/null || echo "$result")
  fi

  if is_unresolved_anchor "$result"; then
    result=$(resolve_anchor "$result")
  fi

  echo "$result"
}

yaml_grep_all() {
  local file="$1"
  local key_name="$2"
  local results=""

  while IFS= read -r line; do
    local value=$(echo "$line" | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r' | xargs 2>/dev/null || echo "")
    if is_unresolved_anchor "$value"; then
      value=$(resolve_anchor "$value")
    fi
    [[ -n "$value" && "$value" != "null" ]] && results="${results}"$'\n'"${value}"
  done < <(grep -E "^[[:space:]]*${key_name}:" "$file" 2>/dev/null || true)

  echo "$results" | sort -u | grep -v "^$" || echo ""
}

yaml_get_anchor() {
  local file="$1"
  local anchor_var="$2"
  local result=$(grep -E "^${anchor_var}:" "$file" 2>/dev/null | head -1 | sed 's/.*&[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r' | xargs 2>/dev/null || echo "")
  echo "$result"
}

yaml_extract_iam_roles() {
  local file="$1"
  grep -oE 'arn:aws:iam::[0-9]+:role/[a-zA-Z0-9_+=,.@-]+' "$file" 2>/dev/null | sort -u || echo ""
}

yaml_extract_iam_role_names() {
  local file="$1"
  grep -oE 'arn:aws:iam::[0-9]+:role/[a-zA-Z0-9_+=,.@-]+' "$file" 2>/dev/null | sed 's|.*role/||' | sort -u || echo ""
}

yaml_extract_azure_workload_identity() {
  local file="$1"
  local results=""
  while IFS= read -r line; do
    local value=$(echo "$line" | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r' | xargs 2>/dev/null || echo "")
    if is_unresolved_anchor "$value"; then
      value=$(resolve_anchor "$value")
    fi
    [[ -n "$value" ]] && results="${results}"$'\n'"${value}"
  done < <(grep -E "azure.workload.identity/client-id:" "$file" 2>/dev/null || true)
  echo "$results" | sort -u | grep -v "^$" || echo ""
}

yaml_extract_azure_identity_anchor() {
  local file="$1"
  grep -E "^_workloadIdentityClientId:" "$file" 2>/dev/null \
    | sed 's/.*&[a-zA-Z_]*[[:space:]]*//' \
    | tr -d '"' | tr -d "'" | tr -d '\r' \
    | xargs 2>/dev/null || echo ""
}

# Extract GCP service account emails from file
yaml_extract_gcp_service_accounts() {
  local file="$1"
  grep -v '^\s*#' "$file" 2>/dev/null \
    | sed 's/[[:space:]]\+#.*//' \
    | grep -oE '[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+\.iam\.gserviceaccount\.com' \
    | sort -u || echo ""
}

# ─────────────────────────── Parse args ───────────────────────
CLOUD=""
VALUES_FILE=""
NAMESPACE=""
SKIP_CLOUD=false
SKIP_K8S=false
AWS_PROFILE="${AWS_PROFILE:-}"
GCP_PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)        CLOUD="$2";        shift 2 ;;
    --values)       VALUES_FILE="$2";  shift 2 ;;
    --namespace)    NAMESPACE="$2";    shift 2 ;;
    --aws-profile)  AWS_PROFILE="$2";  shift 2 ;;
    --gcp-project)  GCP_PROJECT="$2";  shift 2 ;;
    --skip-cloud)   SKIP_CLOUD=true;   shift ;;
    --skip-k8s)     SKIP_K8S=true;     shift ;;
    --help)         usage ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage ;;
  esac
done

CLOUD=$(echo "${CLOUD}" | tr '[:upper:]' '[:lower:]')
if [[ "$CLOUD" != "aws" && "$CLOUD" != "azure" && "$CLOUD" != "gcp" ]]; then
  echo -e "${RED}Error: --cloud must be 'aws', 'azure', or 'gcp'${NC}"; usage
fi
if [[ -z "$VALUES_FILE" ]]; then
  echo -e "${RED}Error: --values is required${NC}"; usage
fi
if [[ ! -f "$VALUES_FILE" ]]; then
  echo -e "${RED}Error: values file not found: ${VALUES_FILE}${NC}"; exit 1
fi

# Detect yq availability
detect_yq

# IMPORTANT: Parse YAML anchors FIRST before reading any values
parse_yaml_anchors "$VALUES_FILE"

# ─────────────────────────── Read values ──────────────────────
STORAGE_BUCKET=$(yaml_get "$VALUES_FILE" "global.storageBucket")
STORAGE_PREFIX=$(yaml_get "$VALUES_FILE" "global.storagePrefix")
EXTERNAL_GATEWAY_HOST=$(yaml_get "$VALUES_FILE" "global.ExternalGatewayHost")
K8S_AUTH_SECRET_NAME=$(yaml_get "$VALUES_FILE" "global.k8s_auth_secret_name")
AIRFLOW_AUTH_SECRET_NAME=$(yaml_get "$VALUES_FILE" "global.airflowSimpleAuth.secretName")

# Fleets settings
FLEETS_MODE=$(yaml_get "$VALUES_FILE" "global.fleets.mode")
FLEETS_HOSTNAME=$(yaml_get "$VALUES_FILE" "global.fleets.hostName")
FLEETS_DIRECT_HOST=$(yaml_get "$VALUES_FILE" "global.fleets.directHost")
FLEETS_TENANT=$(yaml_get "$VALUES_FILE" "global.fleets.tenant")
EXISTING_SECRET=$(yaml_get "$VALUES_FILE" "fleets.existingSecret")

# Storage classes
STORAGE_CLASS_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_storageClassName")
DAGS_STORAGE_CLASS_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_dagsStorageClassName")
STORAGE_CLASSES_RAW=$(yaml_grep_all "$VALUES_FILE" "storageClassName")
STORAGE_CLASS_PERSISTENCE=$(yaml_grep_all "$VALUES_FILE" "storageClass")

ALL_STORAGE_CLASSES=""
[[ -n "$STORAGE_CLASS_ANCHOR" ]] && ALL_STORAGE_CLASSES="$STORAGE_CLASS_ANCHOR"
[[ -n "$DAGS_STORAGE_CLASS_ANCHOR" ]] && ALL_STORAGE_CLASSES="${ALL_STORAGE_CLASSES}"$'\n'"${DAGS_STORAGE_CLASS_ANCHOR}"
[[ -n "$STORAGE_CLASSES_RAW" ]] && ALL_STORAGE_CLASSES="${ALL_STORAGE_CLASSES}"$'\n'"${STORAGE_CLASSES_RAW}"
[[ -n "$STORAGE_CLASS_PERSISTENCE" ]] && ALL_STORAGE_CLASSES="${ALL_STORAGE_CLASSES}"$'\n'"${STORAGE_CLASS_PERSISTENCE}"
ALL_STORAGE_CLASSES=$(echo "$ALL_STORAGE_CLASSES" | sort -u | grep -v "^$" || echo "")

# AWS-specific values
if [[ "$CLOUD" == "aws" ]]; then
  if [[ -n "$AWS_PROFILE" ]]; then
    export AWS_PROFILE="$AWS_PROFILE"
  fi

  aws_cmd() {
    if [[ -n "$AWS_PROFILE" ]]; then
      aws "$@" --profile "$AWS_PROFILE"
    else
      aws "$@"
    fi
  }

  IAM_ROLES=$(yaml_extract_iam_roles "$VALUES_FILE")
  IAM_ROLE_NAMES=$(yaml_extract_iam_role_names "$VALUES_FILE")
  SERVICE_ROLE_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_serviceRole")

  S3_BUCKET_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_s3BucketName")
  [[ -z "$STORAGE_BUCKET" || "$STORAGE_BUCKET" == "null" ]] && STORAGE_BUCKET="$S3_BUCKET_ANCHOR"

  REMOTE_LOG_FOLDER=$(yaml_get "$VALUES_FILE" "airflow.config.logging.remote_base_log_folder")
  [[ -z "$REMOTE_LOG_FOLDER" || "$REMOTE_LOG_FOLDER" == "null" ]] && REMOTE_LOG_FOLDER=$(yaml_get_anchor "$VALUES_FILE" "_remoteBaseLogFolder")

  S3_LOG_BUCKET=""
  if [[ -n "$REMOTE_LOG_FOLDER" && "$REMOTE_LOG_FOLDER" == s3://* ]]; then
    S3_LOG_BUCKET=$(echo "$REMOTE_LOG_FOLDER" | sed 's|s3://||' | cut -d'/' -f1)
  fi

  EXTERNAL_GW_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_externalGatewayHost")
  [[ -z "$EXTERNAL_GATEWAY_HOST" || "$EXTERNAL_GATEWAY_HOST" == "null" ]] && EXTERNAL_GATEWAY_HOST="$EXTERNAL_GW_ANCHOR"
fi

# Azure-specific values
if [[ "$CLOUD" == "azure" ]]; then
  AZURE_WORKLOAD_IDENTITY=$(yaml_extract_azure_identity_anchor "$VALUES_FILE")
  [[ -z "$AZURE_WORKLOAD_IDENTITY" ]] && AZURE_WORKLOAD_IDENTITY=$(yaml_extract_azure_workload_identity "$VALUES_FILE" | head -1)

  AGENTPOOL=$(yaml_get_anchor "$VALUES_FILE" "_agentpool")

  EXTERNAL_GW_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_externalGatewayHost")
  [[ -z "$EXTERNAL_GATEWAY_HOST" || "$EXTERNAL_GATEWAY_HOST" == "null" ]] && EXTERNAL_GATEWAY_HOST="$EXTERNAL_GW_ANCHOR"

  WASB_CONN_RAW=$(grep -A1 'AIRFLOW_CONN_WASB_DEFAULT' "$VALUES_FILE" 2>/dev/null \
    | grep 'value:' \
    | sed "s/.*value:[[:space:]]*//" \
    | tr -d '\r' \
    | xargs 2>/dev/null || echo "")

  WASB_CONN_TYPE=$(echo "$WASB_CONN_RAW" | sed -n 's/.*"conn_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || echo "")
  WASB_HOST_RAW=$(echo "$WASB_CONN_RAW" | sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || echo "")

  if [[ "$WASB_HOST_RAW" =~ \{\{.*\.Values\.global\.storageAccountName.*\}\} ]]; then
    STORAGE_ACCOUNT_NAME=$(yaml_get_anchor "$VALUES_FILE" "_storageAccountName")
    if [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
      STORAGE_ACCOUNT_NAME=$(yaml_get "$VALUES_FILE" "global.storageAccountName")
    fi
    if [[ -n "$STORAGE_ACCOUNT_NAME" && "$STORAGE_ACCOUNT_NAME" != "null" ]]; then
      WASB_HOST="${STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
    else
      WASB_HOST="$WASB_HOST_RAW"
      log_warn "Could not resolve {{ .Values.global.storageAccountName }} - check _storageAccountName anchor in values file"
    fi
  else
    WASB_HOST="$WASB_HOST_RAW"
  fi
fi

# GCP-specific values
if [[ "$CLOUD" == "gcp" ]]; then
  # GCP project ID
  GCP_PROJECT_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_projectId")
  [[ -z "$GCP_PROJECT" ]] && GCP_PROJECT="$GCP_PROJECT_ANCHOR"
  [[ -z "$GCP_PROJECT" ]] && GCP_PROJECT=$(yaml_get "$VALUES_FILE" "global.projectId")

  # GCP service account
  GCP_SERVICE_ACCOUNT_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_gcpServiceAccount")
  GCP_SERVICE_ACCOUNT="${GCP_SERVICE_ACCOUNT_ANCHOR}"
  [[ -z "$GCP_SERVICE_ACCOUNT" ]] && GCP_SERVICE_ACCOUNT=$(yaml_get "$VALUES_FILE" "global.gcpServiceAccount")

  # All GCP service accounts referenced in file
  GCP_SERVICE_ACCOUNTS=$(yaml_extract_gcp_service_accounts "$VALUES_FILE")

  # GCS bucket
  GCS_BUCKET_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_gcsBucketName")
  [[ -z "$STORAGE_BUCKET" || "$STORAGE_BUCKET" == "null" ]] && STORAGE_BUCKET="$GCS_BUCKET_ANCHOR"

  # Node pool
  GCP_NODE_POOL=$(yaml_get_anchor "$VALUES_FILE" "_nodePool")
  [[ -z "$GCP_NODE_POOL" ]] && GCP_NODE_POOL=$(yaml_get "$VALUES_FILE" "global.nodePool")

  # Remote log folder (gs://)
  REMOTE_LOG_FOLDER=$(yaml_get "$VALUES_FILE" "airflow.config.logging.remote_base_log_folder")
  [[ -z "$REMOTE_LOG_FOLDER" || "$REMOTE_LOG_FOLDER" == "null" ]] && REMOTE_LOG_FOLDER=$(yaml_get_anchor "$VALUES_FILE" "_remoteBaseLogFolder")

  GCS_LOG_BUCKET=""
  if [[ -n "$REMOTE_LOG_FOLDER" && "$REMOTE_LOG_FOLDER" == gs://* ]]; then
    GCS_LOG_BUCKET=$(echo "$REMOTE_LOG_FOLDER" | sed 's|gs://||' | cut -d'/' -f1)
  fi

  # ExternalGatewayHost
  EXTERNAL_GW_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_externalGatewayHost")
  [[ -z "$EXTERNAL_GATEWAY_HOST" || "$EXTERNAL_GATEWAY_HOST" == "null" ]] && EXTERNAL_GATEWAY_HOST="$EXTERNAL_GW_ANCHOR"

  # GCS connection for Airflow
  GCS_CONN_RAW=$(grep -A1 'AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT' "$VALUES_FILE" 2>/dev/null \
    | grep 'value:' \
    | sed "s/.*value:[[:space:]]*//" \
    | tr -d '\r' \
    | xargs 2>/dev/null || echo "")
fi

# ═══════════════════════════════════════════════════════════════
log_header "MAI LOCAL AGENT - CONFIGURATION VALIDATION · ${CLOUD^^}"
echo -e "  Cloud              : ${BOLD}${CLOUD}${NC}"
echo -e "  Values file        : ${BOLD}${VALUES_FILE}${NC}"
echo -e "  YAML parser        : ${BOLD}${YQ_VERSION:-grep/sed fallback}${NC}"
echo -e "  Anchors parsed     : ${BOLD}${#YAML_ANCHORS[@]}${NC}"
echo -e "  ExternalGatewayHost: ${BOLD}${EXTERNAL_GATEWAY_HOST:-<empty>}${NC}"
echo -e "  Storage prefix     : ${BOLD}${STORAGE_PREFIX:-<empty>}${NC}"
echo -e "  Storage bucket     : ${BOLD}${STORAGE_BUCKET:-<empty>}${NC}"
echo -e "  Fleets mode        : ${BOLD}${FLEETS_MODE:-<empty>}${NC}"
echo -e "  Namespace          : ${BOLD}${NAMESPACE:-<not specified>}${NC}"
if [[ "$CLOUD" == "gcp" ]]; then
  echo -e "  GCP Project        : ${BOLD}${GCP_PROJECT:-<empty>}${NC}"
  echo -e "  GCP Service Account: ${BOLD}${GCP_SERVICE_ACCOUNT:-<empty>}${NC}"
  echo -e "  GCS Log Bucket     : ${BOLD}${GCS_LOG_BUCKET:-<empty>}${NC}"
  echo -e "  Node Pool          : ${BOLD}${GCP_NODE_POOL:-<empty>}${NC}"
fi
echo -e "  Timestamp          : $(date)"

# Debug: Show parsed anchors
if [[ ${#YAML_ANCHORS[@]} -gt 0 ]]; then
  echo -e "\n  ${CYAN}Parsed YAML Anchors:${NC}"
  for anchor in "${!YAML_ANCHORS[@]}"; do
    echo -e "    ${anchor} = ${YAML_ANCHORS[$anchor]}"
  done
fi

# ─────────────────────────── 0. Tool check ────────────────────
log_section "0  Pre-requisite Tools"

for tool in kubectl grep sed; do
  command -v "$tool" &>/dev/null \
    && log_pass "$tool installed" \
    || log_fail "$tool is NOT installed"
done

if [[ -n "$YQ_VERSION" ]]; then
  log_pass "yq installed ($YQ_VERSION version)"
else
  log_info "yq not found — using grep/sed fallback with anchor resolution"
fi

if command -v helm &>/dev/null; then
  HELM_VER=$(helm version --short 2>/dev/null | head -1)
  log_pass "Helm installed ($HELM_VER)"
else
  log_fail "Helm is NOT installed"
fi

if [[ "$SKIP_CLOUD" == false ]]; then
  if [[ "$CLOUD" == "aws" ]]; then
    command -v aws &>/dev/null \
      && log_pass "AWS CLI installed" \
      || log_fail "AWS CLI is NOT installed"
  elif [[ "$CLOUD" == "azure" ]]; then
    command -v az &>/dev/null \
      && log_pass "Azure CLI installed" \
      || log_fail "Azure CLI is NOT installed"
  elif [[ "$CLOUD" == "gcp" ]]; then
    command -v gcloud &>/dev/null \
      && log_pass "Google Cloud CLI installed ($(gcloud version 2>/dev/null | grep 'Google Cloud SDK' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo 'unknown'))" \
      || log_fail "Google Cloud CLI (gcloud) is NOT installed"
    command -v gsutil &>/dev/null \
      && log_pass "gsutil installed" \
      || log_warn "gsutil not found — GCS bucket checks may be limited"
  fi
fi

# ─────────────────────────── 1. Required Values ───────────────
log_section "1  Required Values Validation"

if [[ -n "$STORAGE_BUCKET" && "$STORAGE_BUCKET" != "null" && ! "$STORAGE_BUCKET" =~ ^\* ]]; then
  log_pass "global.storageBucket is set: ${STORAGE_BUCKET}"
else
  log_fail "global.storageBucket is missing, empty, or unresolved anchor"
fi

if [[ -n "$STORAGE_PREFIX" && "$STORAGE_PREFIX" != "null" ]]; then
  log_pass "global.storagePrefix is set: ${STORAGE_PREFIX}"
else
  log_fail "global.storagePrefix is missing or empty"
fi

if [[ -n "$EXTERNAL_GATEWAY_HOST" && "$EXTERNAL_GATEWAY_HOST" != "null" && ! "$EXTERNAL_GATEWAY_HOST" =~ ^\* ]]; then
  log_pass "global.ExternalGatewayHost is set: ${EXTERNAL_GATEWAY_HOST}"
else
  log_fail "global.ExternalGatewayHost is missing, empty, or unresolved anchor"
fi

# GCP-specific required values
if [[ "$CLOUD" == "gcp" ]]; then
  if [[ -n "$GCP_PROJECT" && "$GCP_PROJECT" != "null" && ! "$GCP_PROJECT" =~ ^\* ]]; then
    log_pass "GCP Project ID is set: ${GCP_PROJECT}"
  else
    log_fail "GCP Project ID is missing — set _projectId anchor or use --gcp-project"
  fi

  if [[ -n "$GCP_SERVICE_ACCOUNT" && "$GCP_SERVICE_ACCOUNT" != "null" && ! "$GCP_SERVICE_ACCOUNT" =~ ^\* ]]; then
    if [[ "$GCP_SERVICE_ACCOUNT" =~ ^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+\.iam\.gserviceaccount\.com$ ]]; then
      log_pass "GCP Service Account format valid: ${GCP_SERVICE_ACCOUNT}"
    else
      log_fail "GCP Service Account format invalid: ${GCP_SERVICE_ACCOUNT} (expected: <name>@<project>.iam.gserviceaccount.com)"
    fi
  else
    log_fail "GCP Service Account (_gcpServiceAccount) is missing or empty"
  fi

  if [[ -n "$REMOTE_LOG_FOLDER" && "$REMOTE_LOG_FOLDER" == gs://* ]]; then
    log_pass "Remote log folder is set: ${REMOTE_LOG_FOLDER}"
  elif [[ -n "$REMOTE_LOG_FOLDER" ]]; then
    log_fail "Remote log folder '${REMOTE_LOG_FOLDER}' does not start with gs:// — expected GCS path for GCP"
  else
    log_warn "Remote log folder (remote_base_log_folder) is not set"
  fi

  if [[ -n "$GCP_NODE_POOL" && "$GCP_NODE_POOL" != "null" ]]; then
    log_pass "Node pool is set: ${GCP_NODE_POOL}"
  else
    log_warn "Node pool (_nodePool) is not set"
  fi
fi

# Fleets configuration validation
if [[ -n "$FLEETS_MODE" ]]; then
  if [[ "$FLEETS_MODE" == "gateway" ]]; then
    log_pass "Fleets mode: gateway"
    if [[ -n "$FLEETS_HOSTNAME" && "$FLEETS_HOSTNAME" != "null" ]]; then
      log_pass "Fleets gateway hostname is set: ${FLEETS_HOSTNAME}"
    else
      log_fail "Fleets mode is 'gateway' but global.fleets.hostName is empty"
    fi
  elif [[ "$FLEETS_MODE" == "direct" ]]; then
    log_pass "Fleets mode: direct"
    if [[ -n "$FLEETS_DIRECT_HOST" && "$FLEETS_DIRECT_HOST" != "null" ]]; then
      log_pass "Fleets direct host is set: ${FLEETS_DIRECT_HOST}"
    else
      log_fail "Fleets mode is 'direct' but global.fleets.directHost is empty"
    fi
  else
    log_warn "Fleets mode '${FLEETS_MODE}' is not recognized (expected: gateway or direct)"
  fi
else
  log_warn "global.fleets.mode is not set"
fi

# ═══════════════════════════════════════════════════════════════
# 2. CLOUD-SPECIFIC CHECKS
# ═══════════════════════════════════════════════════════════════
if [[ "$SKIP_CLOUD" == false ]]; then

  # ───────────────── AWS ──────────────────
  if [[ "$CLOUD" == "aws" ]]; then
    log_section "2  AWS Cloud Validation"

    if [[ -n "$AWS_PROFILE" ]]; then
      log_info "Using AWS profile: ${AWS_PROFILE}"
    else
      log_info "Using default AWS profile / environment credentials"
    fi

    if aws_cmd sts get-caller-identity &>/dev/null; then
      ACCT=$(aws_cmd sts get-caller-identity --query "Account" --output text 2>/dev/null)
      ARN=$(aws_cmd sts get-caller-identity --query "Arn" --output text 2>/dev/null)
      log_pass "AWS credentials valid (Account: $ACCT | ARN: $ARN)"
    else
      log_fail "AWS credentials invalid — run 'aws sso login --profile <profile>' or check IAM role"
    fi

    if [[ -n "$STORAGE_BUCKET" && ! "$STORAGE_BUCKET" =~ ^\* ]]; then
      if aws_cmd s3 ls "s3://${STORAGE_BUCKET}" &>/dev/null; then
        log_pass "S3 bucket accessible: s3://${STORAGE_BUCKET}"
      else
        log_fail "S3 bucket NOT accessible: s3://${STORAGE_BUCKET}"
      fi
    else
      log_warn "global.storageBucket is empty or unresolved — skipping S3 check"
    fi

    if [[ -n "$S3_LOG_BUCKET" && ! "$S3_LOG_BUCKET" =~ ^\* && "$S3_LOG_BUCKET" != "$STORAGE_BUCKET" ]]; then
      if aws_cmd s3 ls "s3://${S3_LOG_BUCKET}" &>/dev/null; then
        log_pass "S3 remote log bucket accessible: s3://${S3_LOG_BUCKET}"
      else
        log_fail "S3 remote log bucket NOT accessible: s3://${S3_LOG_BUCKET}"
      fi
    elif [[ -n "$S3_LOG_BUCKET" && "$S3_LOG_BUCKET" == "$STORAGE_BUCKET" ]]; then
      log_info "Remote log bucket same as storage bucket: ${S3_LOG_BUCKET}"
    fi

    if [[ -n "$IAM_ROLE_NAMES" ]]; then
      while IFS= read -r role; do
        [[ -z "$role" ]] && continue
        if aws_cmd iam get-role --role-name "$role" &>/dev/null; then
          log_pass "IAM role exists: ${role}"
        else
          log_fail "IAM role NOT found: ${role}"
        fi
      done <<< "$IAM_ROLE_NAMES"
    else
      log_warn "No IAM role ARNs found in values file"
    fi

    if [[ -n "$EXTERNAL_GATEWAY_HOST" && ! "$EXTERNAL_GATEWAY_HOST" =~ ^\* ]]; then
      case "$EXTERNAL_GATEWAY_HOST" in
        *dev.cidev.sas.us*|*stage.cistage.sas.com*|*prod.ci360.sas.com*|*training.ci360.sas.com*|*demo.cidemo.sas.com*)
          ECR_REGION="us-east-1" ;;
        *eu-prod.ci360.sas.com*)
          ECR_REGION="eu-west-1" ;;
        *apn-prod.ci360.sas.com*)
          ECR_REGION="ap-northeast-1" ;;
        *syd-prod.ci360.sas.com*)
          ECR_REGION="ap-southeast-2" ;;
        *mum-prod.ci360.sas.com*)
          ECR_REGION="ap-south-1" ;;
        *)
          ECR_REGION=""
          log_warn "Could not determine ECR region from ExternalGatewayHost: ${EXTERNAL_GATEWAY_HOST}"
          ;;
      esac

      if [[ -n "$ECR_REGION" ]]; then
        if aws_cmd ecr describe-repositories --region "$ECR_REGION" --max-items 1 &>/dev/null; then
          log_pass "ECR registry accessible in region: ${ECR_REGION}"
        else
          log_fail "ECR registry NOT accessible in region: ${ECR_REGION}"
        fi
      fi
    else
      log_warn "ExternalGatewayHost is empty or unresolved — skipping ECR check"
    fi
  fi

  # ───────────────── Azure ────────────────
  if [[ "$CLOUD" == "azure" ]]; then
    log_section "2  Azure Cloud Validation"

    if az account show &>/dev/null; then
      SUB=$(az account show --query "name" --output tsv 2>/dev/null)
      log_pass "Azure login valid (Subscription: $SUB)"
    else
      log_fail "Azure login invalid — run 'az login'"
    fi

    if [[ -n "$AZURE_WORKLOAD_IDENTITY" && ! "$AZURE_WORKLOAD_IDENTITY" =~ ^\* ]]; then
      if [[ "$AZURE_WORKLOAD_IDENTITY" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        log_pass "Workload Identity Client ID format is valid: ${AZURE_WORKLOAD_IDENTITY}"
        if az ad sp show --id "$AZURE_WORKLOAD_IDENTITY" &>/dev/null 2>&1; then
          SP_NAME=$(az ad sp show --id "$AZURE_WORKLOAD_IDENTITY" --query "displayName" --output tsv 2>/dev/null || echo "unknown")
          log_pass "Workload Identity Client ID exists in Azure AD (displayName: ${SP_NAME})"
        else
          log_fail "Workload Identity Client ID '${AZURE_WORKLOAD_IDENTITY}' NOT found in Azure AD"
        fi
      else
        log_fail "Workload Identity Client ID '${AZURE_WORKLOAD_IDENTITY}' has invalid UUID format"
      fi
    else
      log_fail "Workload Identity Client ID is missing or unresolved"
    fi

    if [[ -n "$AGENTPOOL" && ! "$AGENTPOOL" =~ ^\* ]]; then
      log_info "Node selector agentpool: ${AGENTPOOL}"
    fi

    if [[ -z "$WASB_CONN_RAW" ]]; then
      log_fail "AIRFLOW_CONN_WASB_DEFAULT is missing from airflow.extraEnv"
    else
      log_pass "AIRFLOW_CONN_WASB_DEFAULT entry found in airflow.extraEnv"
      if [[ "$WASB_CONN_TYPE" == "wasb" ]]; then
        log_pass "WASB conn_type is correct: wasb"
      else
        log_fail "WASB conn_type is '${WASB_CONN_TYPE:-<missing>}' — expected 'wasb'"
      fi
      if [[ -z "$WASB_HOST" ]]; then
        log_fail "WASB host could not be resolved"
      elif [[ "$WASB_HOST" == *.blob.core.windows.net ]]; then
        log_pass "WASB host is valid: ${WASB_HOST}"
      else
        log_fail "WASB host format is invalid: ${WASB_HOST}"
      fi
    fi
  fi

  # ───────────────── GCP ──────────────────
  if [[ "$CLOUD" == "gcp" ]]; then
    log_section "2  GCP Cloud Validation"

    # 2a. Authentication
    if gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -1 | grep -q "."; then
      ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -1)
      log_pass "GCP authentication active (Account: ${ACTIVE_ACCOUNT})"
    else
      log_fail "GCP authentication invalid — run 'gcloud auth login' or 'gcloud auth activate-service-account'"
    fi

    # 2b. Project access
    if [[ -n "$GCP_PROJECT" ]]; then
      if gcloud projects describe "$GCP_PROJECT" &>/dev/null; then
        log_pass "GCP project accessible: ${GCP_PROJECT}"
      else
        log_fail "GCP project NOT accessible: ${GCP_PROJECT} — check permissions or project ID"
      fi

      # Verify current active project matches
      ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
      if [[ "$ACTIVE_PROJECT" == "$GCP_PROJECT" ]]; then
        log_pass "Active gcloud project matches values file: ${ACTIVE_PROJECT}"
      else
        log_warn "Active gcloud project '${ACTIVE_PROJECT:-<none>}' differs from values file '${GCP_PROJECT}'"
        log_info "Consider: gcloud config set project ${GCP_PROJECT}"
      fi
    fi

    # 2c. GCS bucket access
    if [[ -n "$STORAGE_BUCKET" && ! "$STORAGE_BUCKET" =~ ^\* ]]; then
      if gsutil ls "gs://${STORAGE_BUCKET}" &>/dev/null 2>&1; then
        log_pass "GCS bucket accessible: gs://${STORAGE_BUCKET}"
      elif gcloud storage ls "gs://${STORAGE_BUCKET}" &>/dev/null 2>&1; then
        log_pass "GCS bucket accessible: gs://${STORAGE_BUCKET} (via gcloud storage)"
      else
        log_fail "GCS bucket NOT accessible: gs://${STORAGE_BUCKET}"
      fi
    else
      log_warn "Storage bucket is empty or unresolved — skipping GCS check"
    fi

    # 2d. GCS remote log bucket (if different from main bucket)
    if [[ -n "$GCS_LOG_BUCKET" && ! "$GCS_LOG_BUCKET" =~ ^\* && "$GCS_LOG_BUCKET" != "$STORAGE_BUCKET" ]]; then
      if gsutil ls "gs://${GCS_LOG_BUCKET}" &>/dev/null 2>&1; then
        log_pass "GCS remote log bucket accessible: gs://${GCS_LOG_BUCKET}"
      elif gcloud storage ls "gs://${GCS_LOG_BUCKET}" &>/dev/null 2>&1; then
        log_pass "GCS remote log bucket accessible: gs://${GCS_LOG_BUCKET} (via gcloud storage)"
      else
        log_fail "GCS remote log bucket NOT accessible: gs://${GCS_LOG_BUCKET}"
      fi
    elif [[ -n "$GCS_LOG_BUCKET" && "$GCS_LOG_BUCKET" == "$STORAGE_BUCKET" ]]; then
      log_info "Remote log bucket same as storage bucket: ${GCS_LOG_BUCKET}"
    fi

    # 2e. GCP Service Account(s) validation
    if [[ -n "$GCP_SERVICE_ACCOUNTS" ]]; then
      while IFS= read -r sa; do
        [[ -z "$sa" ]] && continue
        # Extract project from SA email
        sa_project=$(echo "$sa" | sed 's/.*@\(.*\)\.iam\.gserviceaccount\.com/\1/')
        if gcloud iam service-accounts describe "$sa" --project="$sa_project" &>/dev/null 2>&1; then
          log_pass "GCP Service Account exists: ${sa}"

          # Check if Workload Identity binding exists
          k8s_ns="${NAMESPACE:-default}"
          bindings=$(gcloud iam service-accounts get-iam-policy "$sa" --project="$sa_project" --format=json 2>/dev/null || echo "{}")

          if echo "$bindings" | grep -q "serviceAccount:${GCP_PROJECT}.svc.id.goog"; then
            log_pass "Workload Identity binding found for SA: ${sa}"
          else
            log_warn "No Workload Identity binding found for SA: ${sa}"
            log_info "Bind with: gcloud iam service-accounts add-iam-policy-binding ${sa} \\"
            log_info "  --role=roles/iam.workloadIdentityUser \\"
            log_info "  --member=\"serviceAccount:${GCP_PROJECT}.svc.id.goog[${k8s_ns}/<k8s-sa-name>]\" \\"
            log_info "  --project=${sa_project}"
          fi
        else
          log_fail "GCP Service Account NOT found: ${sa}"
        fi
      done <<< "$GCP_SERVICE_ACCOUNTS"
    else
      log_warn "No GCP service accounts found in values file"
    fi

    # 2f. Required GCP APIs
    if [[ -n "$GCP_PROJECT" && "$GCP_PROJECT" != "null" && ! "$GCP_PROJECT" =~ ^\* ]]; then
      log_info "Checking required GCP APIs..."
      REQUIRED_APIS=("container.googleapis.com" "storage.googleapis.com" "iam.googleapis.com" "iamcredentials.googleapis.com")

      for api in "${REQUIRED_APIS[@]}"; do
        if gcloud services list --project="$GCP_PROJECT" --filter="config.name:${api}" --format="value(config.name)" 2>/dev/null | grep -q "$api"; then
          log_pass "GCP API enabled: ${api}"
        else
          log_fail "GCP API NOT enabled: ${api}"
          log_info "Enable with: gcloud services enable ${api} --project=${GCP_PROJECT}"
        fi
      done
    else
      log_warn "GCP Project ID is empty or unresolved — skipping API enablement checks"
    fi

    # 2g. Artifact Registry / Container Registry access
    if [[ -n "$EXTERNAL_GATEWAY_HOST" && ! "$EXTERNAL_GATEWAY_HOST" =~ ^\* ]]; then
      # Determine region from gateway host
      case "$EXTERNAL_GATEWAY_HOST" in
        *dev.cidev.sas.us*|*stage.cistage.sas.com*|*prod.ci360.sas.com*|*training.ci360.sas.com*|*demo.cidemo.sas.com*)
          GAR_REGION="us" ;;
        *eu-prod.ci360.sas.com*)
          GAR_REGION="europe" ;;
        *apn-prod.ci360.sas.com*)
          GAR_REGION="asia-northeast1" ;;
        *syd-prod.ci360.sas.com*)
          GAR_REGION="australia-southeast1" ;;
        *mum-prod.ci360.sas.com*)
          GAR_REGION="asia-south1" ;;
        *)
          GAR_REGION=""
          log_warn "Could not determine Artifact Registry region from ExternalGatewayHost: ${EXTERNAL_GATEWAY_HOST}"
          ;;
      esac

      if [[ -n "$GAR_REGION" ]]; then
        if gcloud artifacts repositories list --project="$GCP_PROJECT" --location="$GAR_REGION" --limit=1 &>/dev/null 2>&1; then
          log_pass "Artifact Registry accessible in region: ${GAR_REGION}"
        else
          log_warn "Could not verify Artifact Registry in region: ${GAR_REGION} — check artifactregistry.googleapis.com API"
        fi
      fi
    else
      log_warn "ExternalGatewayHost is empty or unresolved — skipping registry check"
    fi

    # 2h. GKE cluster validation
    log_info "Checking GKE cluster connectivity..."
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | grep -oE 'gke_[^_]+_[^_]+_(.+)' | sed 's/gke_[^_]*_[^_]*_//' || echo "")
    if [[ -n "$CLUSTER_NAME" ]]; then
      log_pass "Connected to GKE cluster: ${CLUSTER_NAME}"
    else
      log_info "Could not determine GKE cluster name from kubectl context"
    fi
  fi

else
  log_section "2  Cloud Validation"
  log_info "Skipped (--skip-cloud)"
fi

# ═══════════════════════════════════════════════════════════════
# 3. KUBERNETES PRE-CHECKS
# ═══════════════════════════════════════════════════════════════
if [[ "$SKIP_K8S" == false ]]; then
  log_section "3  Kubernetes Cluster Connectivity"

  if kubectl cluster-info &>/dev/null; then
    CLUSTER_EP=$(kubectl cluster-info 2>/dev/null | head -1 | grep -oE 'https?://[^\s]+' || echo "connected")
    log_pass "Cluster reachable: $CLUSTER_EP"
  else
    log_fail "Cannot connect to Kubernetes cluster"
  fi

  READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
  TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)
  [[ "$READY" -gt 0 ]] && log_pass "Nodes ready: ${READY}/${TOTAL}" || log_fail "No nodes Ready"

  # GCP: Check node pool labels
  if [[ "$CLOUD" == "gcp" && -n "$GCP_NODE_POOL" ]]; then
    NODE_POOL_NODES=$(kubectl get nodes -l "cloud.google.com/gke-nodepool=${GCP_NODE_POOL}" --no-headers 2>/dev/null | wc -l || echo 0)
    if [[ "$NODE_POOL_NODES" -gt 0 ]]; then
      log_pass "Nodes in pool '${GCP_NODE_POOL}': ${NODE_POOL_NODES}"
    else
      log_fail "No nodes found with label cloud.google.com/gke-nodepool=${GCP_NODE_POOL}"
    fi
  fi

  # ──────── Storage classes ────────
  log_section "4  Storage Class Verification"

  if [[ -n "$ALL_STORAGE_CLASSES" ]]; then
    while IFS= read -r sc; do
      sc=$(echo "$sc" | tr -d '\r' | xargs)
      [[ -z "$sc" ]] && continue
      [[ "$sc" =~ ^\* ]] && continue
      if kubectl get storageclass "$sc" &>/dev/null; then
        PROVISIONER=$(kubectl get storageclass "$sc" -o jsonpath='{.provisioner}' 2>/dev/null)
        log_pass "StorageClass '${sc}' exists (provisioner=${PROVISIONER})"

        # GCP: Validate provisioner types
        if [[ "$CLOUD" == "gcp" ]]; then
          case "$sc" in
            *rwo*|*standard-rwo*)
              if [[ "$PROVISIONER" == "pd.csi.storage.gke.io" ]]; then
                log_pass "StorageClass '${sc}' uses expected GKE PD CSI provisioner"
              else
                log_warn "StorageClass '${sc}' provisioner '${PROVISIONER}' — expected 'pd.csi.storage.gke.io' for RWO"
              fi
              ;;
            *rwx*|*standard-rwx*)
              if [[ "$PROVISIONER" == "filestore.csi.storage.gke.io" ]]; then
                log_pass "StorageClass '${sc}' uses expected GKE Filestore CSI provisioner"
              else
                log_warn "StorageClass '${sc}' provisioner '${PROVISIONER}' — expected 'filestore.csi.storage.gke.io' for RWX"
              fi
              ;;
          esac
        fi
      else
        log_fail "StorageClass '${sc}' NOT found in cluster"
      fi
    done <<< "$ALL_STORAGE_CLASSES"
  else
    log_warn "No storageClassName found in values file"
  fi

  # ──────── Namespace & SA ────────
  if [[ -n "$NAMESPACE" ]]; then
    log_section "5  Namespace & Service Account Checks"

    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
      log_pass "Namespace '${NAMESPACE}' exists"

      # Check for ServiceAccounts with cloud-specific annotations
      if [[ "$CLOUD" == "aws" ]]; then
        ANNOTATION_KEY="eks.amazonaws.com/role-arn"
      elif [[ "$CLOUD" == "azure" ]]; then
        ANNOTATION_KEY="azure.workload.identity/client-id"
      elif [[ "$CLOUD" == "gcp" ]]; then
        ANNOTATION_KEY="iam.gke.io/gcp-service-account"
      fi

      SA_MATCHES=$(kubectl get serviceaccount -n "$NAMESPACE" -o yaml 2>/dev/null | grep "$ANNOTATION_KEY" || true)

      if [[ -n "$SA_MATCHES" ]]; then
        MATCH_COUNT=$(echo "$SA_MATCHES" | wc -l)
        log_pass "Found ${MATCH_COUNT} SA(s) with '${ANNOTATION_KEY}' annotation"

        # GCP: Verify SA annotation value matches expected service account
        if [[ "$CLOUD" == "gcp" && -n "$GCP_SERVICE_ACCOUNT" ]]; then
          if echo "$SA_MATCHES" | grep -q "$GCP_SERVICE_ACCOUNT"; then
            log_pass "K8s SA annotated with expected GCP SA: ${GCP_SERVICE_ACCOUNT}"
          else
            log_warn "K8s SA annotation does not match expected GCP SA: ${GCP_SERVICE_ACCOUNT}"
          fi
        fi
      else
        log_info "No SAs with '${ANNOTATION_KEY}' annotation yet (will be created by Helm)"
      fi

      # Check for required secrets
      if [[ -n "$K8S_AUTH_SECRET_NAME" && ! "$K8S_AUTH_SECRET_NAME" =~ ^\* ]]; then
        if kubectl get secret "$K8S_AUTH_SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
          log_pass "Secret '${K8S_AUTH_SECRET_NAME}' exists"
        else
          log_fail "Secret '${K8S_AUTH_SECRET_NAME}' not found — create before deployment"
        fi
      fi

      if [[ -n "$AIRFLOW_AUTH_SECRET_NAME" && ! "$AIRFLOW_AUTH_SECRET_NAME" =~ ^\* ]]; then
        if kubectl get secret "$AIRFLOW_AUTH_SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
          log_pass "Secret '${AIRFLOW_AUTH_SECRET_NAME}' exists"
        else
          log_fail "Secret '${AIRFLOW_AUTH_SECRET_NAME}' not found — create before deployment"
        fi
      fi

      # PostgreSQL HA secrets
      log_info "Checking PostgreSQL HA secrets..."

      if kubectl get secret postgres-credentials -n "$NAMESPACE" &>/dev/null; then
        POSTGRES_SECRET_KEYS=$(kubectl get secret postgres-credentials -n "$NAMESPACE" -o jsonpath='{.data}' 2>/dev/null)
        if echo "$POSTGRES_SECRET_KEYS" | grep -q '"password"' && \
           echo "$POSTGRES_SECRET_KEYS" | grep -q '"repmgr-password"'; then
          log_pass "Secret 'postgres-credentials' exists with required keys (password, repmgr-password)"
        else
          MISSING_KEYS=()
          echo "$POSTGRES_SECRET_KEYS" | grep -q '"password"' || MISSING_KEYS+=("password")
          echo "$POSTGRES_SECRET_KEYS" | grep -q '"repmgr-password"' || MISSING_KEYS+=("repmgr-password")
          log_fail "Secret 'postgres-credentials' exists but missing keys: $(IFS=', '; echo "${MISSING_KEYS[*]}")"
          log_info "Recreate with: kubectl create secret generic postgres-credentials \\"
          log_info "  --from-literal=password='<postgres-password>' \\"
          log_info "  --from-literal=repmgr-password='<repmgr-password>' \\"
          log_info "  -n ${NAMESPACE}"
        fi
      else
        log_fail "Secret 'postgres-credentials' not found — create before deployment"
        log_info "Create with: kubectl create secret generic postgres-credentials \\"
        log_info "  --from-literal=password='<postgres-password>' \\"
        log_info "  --from-literal=repmgr-password='<repmgr-password>' \\"
        log_info "  -n ${NAMESPACE}"
      fi

      if kubectl get secret pgpool-credentials -n "$NAMESPACE" &>/dev/null; then
        PGPOOL_SECRET_KEYS=$(kubectl get secret pgpool-credentials -n "$NAMESPACE" -o jsonpath='{.data}' 2>/dev/null)
        if echo "$PGPOOL_SECRET_KEYS" | grep -q '"admin-password"'; then
          log_pass "Secret 'pgpool-credentials' exists with required key (admin-password)"
        else
          log_fail "Secret 'pgpool-credentials' exists but missing key: admin-password"
          log_info "Recreate with: kubectl create secret generic pgpool-credentials \\"
          log_info "  --from-literal=admin-password='<pgpool-admin-password>' \\"
          log_info "  -n ${NAMESPACE}"
        fi
      else
        log_fail "Secret 'pgpool-credentials' not found — create before deployment"
        log_info "Create with: kubectl create secret generic pgpool-credentials \\"
        log_info "  --from-literal=admin-password='<pgpool-admin-password>' \\"
        log_info "  -n ${NAMESPACE}"
      fi

      # Fleets secret check
      if [[ "$FLEETS_MODE" == "gateway" ]]; then
        EXISTING_SECRET_CLEAN=$(echo "$EXISTING_SECRET" | tr -d '"' | tr -d "'" | xargs 2>/dev/null || echo "")
        if [[ -n "$EXISTING_SECRET_CLEAN" && "$EXISTING_SECRET_CLEAN" != "null" && ! "$EXISTING_SECRET_CLEAN" =~ ^\* ]]; then
          if kubectl get secret "$EXISTING_SECRET_CLEAN" -n "$NAMESPACE" &>/dev/null; then
            log_pass "Fleets secret '${EXISTING_SECRET_CLEAN}' exists"
          else
            log_fail "Fleets secret '${EXISTING_SECRET_CLEAN}' specified but not found in namespace '${NAMESPACE}'"
          fi
        else
          log_fail "fleets.existingSecret is missing or empty — required when using gateway mode"
        fi
      elif [[ "$FLEETS_MODE" == "direct" ]]; then
        log_info "Fleets mode is 'direct' — fleets.existingSecret not required"
      fi

      # Resource quotas
      log_section "6  Resource Quota Check"
      QUOTA_COUNT=$(kubectl get resourcequota -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo 0)
      if [[ "$QUOTA_COUNT" -gt 0 ]]; then
        log_info "Namespace has ${QUOTA_COUNT} ResourceQuota(s) — verify sufficient capacity:"
        kubectl get resourcequota -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r line; do
          echo "         $line"
        done
      else
        log_pass "No ResourceQuota restrictions in namespace"
      fi

      PVC_COUNT=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo 0)
      if [[ "$PVC_COUNT" -gt 0 ]]; then
        log_info "Namespace has ${PVC_COUNT} existing PVC(s)"
      fi

    else
      log_fail "Namespace '${NAMESPACE}' does not exist — create it and re-run this validation script before deploying."
    fi
  else
    log_info "No --namespace specified — skipping namespace checks"
  fi

else
  log_section "3  Kubernetes Pre-Checks"
  log_info "Skipped (--skip-k8s)"
fi

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
PASSED=$((CHECKS - ERRORS - WARNINGS))

log_header "SUMMARY"
echo -e "  Total checks : ${BOLD}${CHECKS}${NC}"
echo -e "  Passed       : ${GREEN}${BOLD}${PASSED}${NC}"
echo -e "  Warnings     : ${YELLOW}${BOLD}${WARNINGS}${NC}"
echo -e "  Failures     : ${RED}${BOLD}${ERRORS}${NC}"
echo ""

if [[ "$ERRORS" -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}❌  CONFIGURATION VALIDATION FAILED — fix ${ERRORS} error(s), then re-run this script before deploying.${NC}\n"
  exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}⚠️  VALIDATION PASSED WITH ${WARNINGS} WARNING(S) — review before deploying.${NC}\n"
  exit 0
else
  echo -e "  ${GREEN}${BOLD}✅  ALL CHECKS PASSED${NC}\n"
  echo -e "  ${GREEN}${BOLD}✅  YOU CAN PROCEED WITH MAI LOCAL AGENT DEPLOYMENT${NC}\n"
  exit 0
fi