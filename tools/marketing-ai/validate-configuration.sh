#!/usr/bin/env bash
#
# preflight-check.sh — Pre-deployment cloud & K8s validation
# Reads configuration from the Helm values file automatically.
# No Python/PyYAML required — uses yq or grep/sed fallback.
#
# Usage:
#   ./preflight-check.sh --cloud aws   --values values-aws.yaml   [--namespace my-ns] [OPTIONS]
#   ./preflight-check.sh --cloud azure --values values-azure.yaml [--namespace my-ns] [OPTIONS]
#

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
Usage: $0 --cloud <aws|azure> --values <file> [OPTIONS]

Required:
  --cloud       aws or azure
  --values      Path to the Helm values YAML file

Optional:
  --namespace   K8s namespace (SA annotations, secrets)
  --skip-cloud  Skip cloud CLI checks
  --skip-k8s    Skip Kubernetes checks
  --help        Show this message

Examples:
  $0 --cloud aws   --values values-aws.yaml   --namespace p-sinakm-1802
  $0 --cloud azure --values values-azure.yaml --namespace mai-ns
  $0 --cloud aws   --values values-aws.yaml   --skip-cloud
EOF
exit 0
}

# ─────────────────────────── YAML Parsing ─────────────────────
# Detects yq version and uses appropriate syntax, or falls back to grep/sed

YQ_CMD=""
YQ_VERSION=""

detect_yq() {
  if command -v yq &>/dev/null; then
    # Detect yq version (mikefarah vs kislyuk)
    if yq --version 2>&1 | grep -q "mikefarah"; then
      YQ_CMD="yq_mikefarah"
      YQ_VERSION="mikefarah"
    elif yq --version 2>&1 | grep -q "version"; then
      # mikefarah v4+ just shows "yq version x.x.x"
      YQ_CMD="yq_mikefarah"
      YQ_VERSION="mikefarah"
    else
      YQ_CMD="yq_kislyuk"
      YQ_VERSION="kislyuk"
    fi
  fi
}

# Get a single value from YAML by dot-notation path
# Usage: yaml_get "file.yaml" "global.storageBucket"
yaml_get() {
  local file="$1"
  local key_path="$2"
  local result=""

  if [[ "$YQ_CMD" == "yq_mikefarah" ]]; then
    # mikefarah/yq syntax: .global.storageBucket
    result=$(yq eval ".${key_path}" "$file" 2>/dev/null | grep -v "^null$" || echo "")
  elif [[ "$YQ_CMD" == "yq_kislyuk" ]]; then
    # kislyuk/yq (Python-based) syntax
    result=$(yq -r ".${key_path} // empty" "$file" 2>/dev/null || echo "")
  else
    # Fallback: grep-based extraction (handles simple cases)
    # Convert dot notation to grep pattern
    local key=$(echo "$key_path" | awk -F. '{print $NF}')
    result=$(grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '"' | tr -d "'" | xargs || echo "")
  fi

  # Clean up the result
  result=$(echo "$result" | tr -d '"' | tr -d "'" | xargs 2>/dev/null || echo "$result")
  echo "$result"
}

# Get all unique values for a key name anywhere in the file
# Usage: yaml_grep_all "file.yaml" "storageClassName"
yaml_grep_all() {
  local file="$1"
  local key_name="$2"

  grep -E "^\s*${key_name}:" "$file" 2>/dev/null \
    | sed 's/.*:\s*//' \
    | tr -d '"' | tr -d "'" \
    | xargs -n1 2>/dev/null \
    | sort -u \
    | grep -v "^$" \
    || echo ""
}

# Extract IAM role names from role-arn patterns
# Usage: yaml_extract_iam_roles "file.yaml"
yaml_extract_iam_roles() {
  local file="$1"
  grep -oP 'arn:aws:iam::[0-9]+:role/\K[a-zA-Z0-9_+=,.@-]+' "$file" 2>/dev/null \
    | sort -u \
    || echo ""
}

# Extract Azure identity names from annotations
yaml_extract_azure_identities() {
  local file="$1"
  grep -E "(client-id|aadpodidbinding):" "$file" 2>/dev/null \
    | sed 's/.*:\s*//' \
    | tr -d '"' | tr -d "'" \
    | xargs -n1 2>/dev/null \
    | sort -u \
    | grep -v "^$" \
    || echo ""
}

# ─────────────────────────── Parse args ───────────────────────
CLOUD=""
VALUES_FILE=""
NAMESPACE=""
SKIP_CLOUD=false
SKIP_K8S=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)      CLOUD="$2";       shift 2 ;;
    --values)     VALUES_FILE="$2"; shift 2 ;;
    --namespace)  NAMESPACE="$2";   shift 2 ;;
    --skip-cloud) SKIP_CLOUD=true;  shift ;;
    --skip-k8s)   SKIP_K8S=true;    shift ;;
    --help)       usage ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage ;;
  esac
done

CLOUD=$(echo "${CLOUD}" | tr '[:upper:]' '[:lower:]')
if [[ "$CLOUD" != "aws" && "$CLOUD" != "azure" ]]; then
  echo -e "${RED}Error: --cloud must be 'aws' or 'azure'${NC}"; usage
fi
if [[ -z "$VALUES_FILE" ]]; then
  echo -e "${RED}Error: --values is required${NC}"; usage
fi
if [[ ! -f "$VALUES_FILE" ]]; then
  echo -e "${RED}Error: values file not found: ${VALUES_FILE}${NC}"; exit 1
fi

# Detect yq availability
detect_yq

# ─────────────────────────── Read values ──────────────────────
STORAGE_BUCKET=$(yaml_get "$VALUES_FILE" "global.storageBucket")
STORAGE_PREFIX=$(yaml_get "$VALUES_FILE" "global.storagePrefix")
REGISTRY_URL=$(yaml_get "$VALUES_FILE" "registry.url")
REMOTE_LOG_FOLDER=$(yaml_get "$VALUES_FILE" "airflow.config.logging.remote_base_log_folder")
EXISTING_SECRET=$(yaml_get "$VALUES_FILE" "fleets.existingSecret")

# Storage classes — collect unique values
STORAGE_CLASSES_RAW=$(yaml_grep_all "$VALUES_FILE" "storageClassName")

# IAM roles (AWS) or identities (Azure)
IAM_ROLES=$(yaml_extract_iam_roles "$VALUES_FILE")
AZURE_IDENTITIES=$(yaml_extract_azure_identities "$VALUES_FILE")

# Azure-specific
AZURE_STORAGE_ACCOUNT=$(yaml_get "$VALUES_FILE" "global.azure.storageAccount")
AZURE_RESOURCE_GROUP=$(yaml_get "$VALUES_FILE" "global.azure.resourceGroup")

# Read connection string from global.azureStorage.connectionString
AZURE_CONNECTION_STRING=$(yaml_get "$VALUES_FILE" "global.azureStorage.connectionString")

# Extract AccountName from connection string: AccountName=<name>;
if [[ -n "$AZURE_CONNECTION_STRING" ]]; then
  AZURE_STORAGE_ACCOUNT=$(echo "$AZURE_CONNECTION_STRING" | grep -oP 'AccountName=\K[^;]+' || echo "")
fi

# Derive S3 log bucket
S3_LOG_BUCKET=""
if [[ -n "$REMOTE_LOG_FOLDER" && "$REMOTE_LOG_FOLDER" == s3://* ]]; then
  S3_LOG_BUCKET=$(echo "$REMOTE_LOG_FOLDER" | sed 's|s3://||' | cut -d'/' -f1)
fi

# ═══════════════════════════════════════════════════════════════
log_header "MAILA VALIDATION OF CONFIGURATION  ·  ${CLOUD^^}"
echo -e "  Cloud            : ${BOLD}${CLOUD}${NC}"
echo -e "  Values file      : ${BOLD}${VALUES_FILE}${NC}"
echo -e "  YAML parser      : ${BOLD}${YQ_VERSION:-grep/sed fallback}${NC}"
echo -e "  Storage prefix   : ${BOLD}${STORAGE_PREFIX:-<empty>}${NC}"
echo -e "  Storage bucket   : ${BOLD}${STORAGE_BUCKET:-<empty>}${NC}"
echo -e "  Registry URL     : ${BOLD}${REGISTRY_URL:-<empty>}${NC}"
echo -e "  Namespace        : ${BOLD}${NAMESPACE:-<not specified>}${NC}"
echo -e "  Timestamp        : $(date)"

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
  log_info "yq not found — using grep/sed fallback (limited parsing)"
fi

if [[ "$SKIP_CLOUD" == false ]]; then
  if [[ "$CLOUD" == "aws" ]]; then
    command -v aws &>/dev/null \
      && log_pass "AWS CLI installed" \
      || log_fail "AWS CLI is NOT installed"
  else
    command -v az &>/dev/null \
      && log_pass "Azure CLI installed" \
      || log_fail "Azure CLI is NOT installed"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# 1. CLOUD-SPECIFIC CHECKS
# ═══════════════════════════════════════════════════════════════
if [[ "$SKIP_CLOUD" == false ]]; then

  # ───────────────── AWS ──────────────────
  if [[ "$CLOUD" == "aws" ]]; then
    log_section "1  AWS Cloud Validation"

    # 1a. Authentication
    if aws sts get-caller-identity &>/dev/null; then
      ACCT=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null)
      log_pass "AWS credentials valid  (Account: $ACCT)"
    else
      log_fail "AWS credentials invalid — run 'aws configure'"
    fi

    # 1b. S3 bucket
    if [[ -n "$STORAGE_BUCKET" ]]; then
      if aws s3 ls "s3://${STORAGE_BUCKET}" &>/dev/null; then
        log_pass "S3 bucket accessible: s3://${STORAGE_BUCKET}"
      else
        log_fail "S3 bucket NOT accessible: s3://${STORAGE_BUCKET}"
      fi
    else
      log_fail "global.storageBucket is empty — skipping S3 check"
    fi

    # 1c. S3 remote log bucket
    if [[ -n "$S3_LOG_BUCKET" && "$S3_LOG_BUCKET" != "$STORAGE_BUCKET" ]]; then
      if aws s3 ls "s3://${S3_LOG_BUCKET}" &>/dev/null; then
        log_pass "S3 remote log bucket accessible: s3://${S3_LOG_BUCKET}"
      else
        log_fail "S3 remote log bucket NOT accessible: s3://${S3_LOG_BUCKET}"
      fi
    fi

    # 1d. IAM roles
    if [[ -n "$IAM_ROLES" ]]; then
      while IFS= read -r role; do
        [[ -z "$role" ]] && continue
        if aws iam get-role --role-name "$role" &>/dev/null; then
          log_pass "IAM role exists: ${role}"
        else
          log_fail "IAM role NOT found: ${role}"
        fi
      done <<< "$IAM_ROLES"
    else
      log_fail "No IAM role ARNs found in values"
    fi

    # 1e. ECR registry
    if [[ -n "$REGISTRY_URL" ]]; then
      ECR_REGION=$(echo "$REGISTRY_URL" | grep -oP '\.ecr\.\K[a-z0-9-]+' || echo "")
      if [[ -n "$ECR_REGION" ]]; then
        if aws ecr describe-repositories --region "$ECR_REGION" --max-items 1 &>/dev/null; then
          log_pass "ECR registry accessible: ${REGISTRY_URL}"
        else
          log_fail "ECR registry NOT accessible: ${REGISTRY_URL}"
        fi
      fi
    fi
  fi

  # ───────────────── Azure ────────────────
  if [[ "$CLOUD" == "azure" ]]; then
    log_section "1  Azure Cloud Validation"

    # 1a. Authentication
    if az account show &>/dev/null; then
      SUB=$(az account show --query "name" --output tsv 2>/dev/null)
      log_pass "Azure login valid  (Subscription: $SUB)"
    else
      log_fail "Azure login invalid — run 'az login'"
    fi

    # 1b. Storage account
    if [[ -n "$AZURE_STORAGE_ACCOUNT" ]]; then
      if az storage account show --name "$AZURE_STORAGE_ACCOUNT" \
           ${AZURE_RESOURCE_GROUP:+--resource-group "$AZURE_RESOURCE_GROUP"} &>/dev/null; then
        log_pass "Storage account exists: $AZURE_STORAGE_ACCOUNT"

        # 1c. Blob container
        if [[ -n "$STORAGE_BUCKET" ]]; then
          if az storage container show --name "$STORAGE_BUCKET" \
              --connection-string "$AZURE_CONNECTION_STRING" &>/dev/null; then
            log_pass "Blob container accessible: $STORAGE_BUCKET"
          else
            log_fail "Blob container NOT accessible: $STORAGE_BUCKET"
          fi
        fi
      else
        log_fail "Storage account NOT found: $AZURE_STORAGE_ACCOUNT"
      fi
    else
      log_fail "global.azure.storageAccount not set"
    fi

    # 1d. Identities
    if [[ -n "$AZURE_IDENTITIES" ]]; then
      while IFS= read -r identity; do
        [[ -z "$identity" ]] && continue
        if az identity list --query "[?clientId=='$identity']" \
        # if az identity show --name "$identity" \
             ${AZURE_RESOURCE_GROUP:+--resource-group "$AZURE_RESOURCE_GROUP"} &>/dev/null; then
          log_pass "Managed Identity exists: ${identity}"
        else
          log_fail "Identity NOT found: ${identity}"
        fi
      done <<< "$AZURE_IDENTITIES"
    fi

    # 1e. ACR registry
    if [[ -n "$REGISTRY_URL" && "$REGISTRY_URL" == *".azurecr.io"* ]]; then
      ACR_NAME=$(echo "$REGISTRY_URL" | sed 's/.azurecr.io//')
      if az acr show --name "$ACR_NAME" &>/dev/null 2>&1; then
        log_pass "ACR registry exists: $ACR_NAME"
      else
        log_fail "ACR registry NOT found: $ACR_NAME"
      fi
    fi
  fi

else
  log_section "1  Cloud Validation"
  log_info "Skipped (--skip-cloud)"
fi

# ═══════════════════════════════════════════════════════════════
# 2. KUBERNETES PRE-CHECKS
# ═══════════════════════════════════════════════════════════════
if [[ "$SKIP_K8S" == false ]]; then
  log_section "2  Kubernetes Cluster Connectivity"

  # 2a. Cluster reachable
  if kubectl cluster-info &>/dev/null; then
    CLUSTER_EP=$(kubectl cluster-info 2>/dev/null | head -1 | grep -oP 'https?://[^\s]+' || echo "connected")
    log_pass "Cluster reachable: $CLUSTER_EP"
  else
    log_fail "Cannot connect to Kubernetes cluster"
  fi

  # 2b. Node readiness
  READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
  TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)
  [[ "$READY" -gt 0 ]] && log_pass "Nodes ready: ${READY}/${TOTAL}" || log_fail "No nodes Ready"

  # ──────── 2c. Storage classes ────────
  log_section "3  Storage Class Verification"

  if [[ -n "$STORAGE_CLASSES_RAW" ]]; then
    while IFS= read -r sc; do
      sc=$(echo "$sc" | xargs)
      [[ -z "$sc" ]] && continue
      if kubectl get storageclass "$sc" &>/dev/null; then
        PROVISIONER=$(kubectl get storageclass "$sc" -o jsonpath='{.provisioner}' 2>/dev/null)
        log_pass "StorageClass '${sc}' exists (provisioner=${PROVISIONER})"
      else
        log_fail "StorageClass '${sc}' NOT found"
      fi
    done <<< "$STORAGE_CLASSES_RAW"
  else
    log_fail "No storageClassName found in values"
  fi

  # ──────── 2d. Namespace & SA ────────
  if [[ -n "$NAMESPACE" ]]; then
    log_section "4  Namespace & Service Account Checks"

    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
      log_pass "Namespace '${NAMESPACE}' exists"

      ANNOTATION_KEY=$([[ "$CLOUD" == "aws" ]] && echo "eks.amazonaws.com/role-arn" || echo "azure.workload.identity/client-id")
      SA_MATCHES=$(kubectl get serviceaccount -n "$NAMESPACE" -o yaml 2>/dev/null | grep "$ANNOTATION_KEY" || true)

      if [[ -n "$SA_MATCHES" ]]; then
        MATCH_COUNT=$(echo "$SA_MATCHES" | wc -l)
        log_pass "Found ${MATCH_COUNT} SA(s) with '${ANNOTATION_KEY}'"
      else
        log_fail "No SAs with '${ANNOTATION_KEY}' annotation"
      fi

      # Required secrets
      REQUIRED_SECRETS=("$EXISTING_SECRET")
      [[ -n "$EXISTING_SECRET" ]] && REQUIRED_SECRETS+=("$EXISTING_SECRET")

      for secret_name in "${REQUIRED_SECRETS[@]}"; do
        if kubectl get secret "$secret_name" -n "$NAMESPACE" &>/dev/null; then
          log_pass "Secret '${secret_name}' exists"
        else
          log_fail "Secret '${secret_name}' not found"
        fi
      done
    else
      log_info "Namespace '${NAMESPACE}' does not exist yet"
    fi
  fi

else
  log_section "2  Kubernetes Pre-Checks"
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

if [[ "$ERRORS" -gt 0 || "$WARNINGS" -gt 0]] then
  echo -e "  ${RED}${BOLD}❌  MAILA VALIDATION OF CONFIGURATION FAILED — fix ${ERRORS} error(s) before deploying.${NC}\n"
  exit 1
# elif [[ "$WARNINGS" -gt 0 ]]; then
#   echo -e "  ${YELLOW}${BOLD}⚠️   PASSED WITH ${WARNINGS} WARNING(S)${NC}\n"
#   exit 0
else
  echo -e "  ${GREEN}${BOLD}✅  ALL CHECKS PASSED${NC}\n"
  echo -e "  ${GREEN}${BOLD}✅  YOU CAN PROCEED WITH MAILA  DEPLOYMENT\n"
  exit 0
fi