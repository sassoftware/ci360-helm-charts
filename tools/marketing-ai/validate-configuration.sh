#!/usr/bin/env bash
#
# validate-configuration.sh — Pre-deployment cloud & K8s validation
# Reads configuration from the Helm values file automatically.
# No Python/PyYAML required — uses yq or grep/sed fallback.
#
# Usage:
#   ./validate-configuration.sh --cloud aws   --values values-aws.yaml   [--namespace my-ns] [OPTIONS]
#   ./validate-configuration.sh --cloud azure --values values-azure.yaml [--namespace my-ns] [OPTIONS]
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
  --cloud         aws or azure
  --values        Path to the Helm values YAML file

Optional:
  --namespace     K8s namespace (SA annotations, secrets)
  --aws-profile   AWS CLI profile name to use (e.g. my-sso-profile)
                  Can also be set via AWS_PROFILE environment variable
  --skip-cloud    Skip cloud CLI checks
  --skip-k8s      Skip Kubernetes checks
  --help          Show this message

Examples:
  $0 --cloud aws --values values-aws.yaml --namespace mai-ns --aws-profile my-sso-profile
  $0 --cloud azure --values values-azure.yaml --namespace mai-ns
  $0 --cloud aws --values values-aws.yaml --skip-cloud AWS_PROFILE=my-sso-profile 
  $0 --cloud aws --values values-aws.yaml
EOF
exit 0
}

# ─────────────────────────── YAML Parsing ─────────────────────
# Detects yq version and uses appropriate syntax, or falls back to grep/sed

YQ_CMD=""
YQ_VERSION=""

# Associative array to store anchor name -> value mappings
declare -A YAML_ANCHORS

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

# Parse all YAML anchors from a file and store in YAML_ANCHORS associative array
# Handles format: _varName: &anchorName "value"
parse_yaml_anchors() {
  local file="$1"
  
  # Clear previous anchors
  YAML_ANCHORS=()
  
  # Read file and extract anchor definitions
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Match pattern: _something: &anchorName "value" or &anchorName value
    # Also match: key: &anchorName "value"
    if [[ "$line" =~ \&([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+(.*) ]]; then
      local anchor_name="${BASH_REMATCH[1]}"
      local anchor_value="${BASH_REMATCH[2]}"
      
      # Clean up the value - remove quotes and whitespace
      anchor_value=$(echo "$anchor_value" | tr -d '"' | tr -d "'" | tr -d '\r' | xargs 2>/dev/null || echo "$anchor_value")
      
      # Store in associative array
      YAML_ANCHORS["$anchor_name"]="$anchor_value"
    fi
  done < "$file"
}

# Resolve an anchor reference (*anchorName) to its actual value
# Usage: resolve_anchor "*s3BucketName"
resolve_anchor() {
  local value="$1"
  
  # Check if value is an anchor reference (*anchorName)
  if [[ "$value" =~ ^\*([a-zA-Z_][a-zA-Z0-9_]*)$ ]]; then
    local anchor_name="${BASH_REMATCH[1]}"
    if [[ -n "${YAML_ANCHORS[$anchor_name]:-}" ]]; then
      echo "${YAML_ANCHORS[$anchor_name]}"
      return 0
    fi
  fi
  
  # Return original value if not an anchor reference or anchor not found
  echo "$value"
}

# Check if a value is an unresolved anchor reference
is_unresolved_anchor() {
  local value="$1"
  [[ "$value" =~ ^\*[a-zA-Z_][a-zA-Z0-9_]*$ ]]
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
    # Convert dot notation to grep pattern - get the last key
    local key=$(echo "$key_path" | awk -F. '{print $NF}')
    result=$(grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '\r' | xargs 2>/dev/null || echo "")
  fi

  # Clean up the result - remove surrounding quotes but preserve empty string detection
  result=$(echo "$result" | tr -d '\r' | xargs 2>/dev/null || echo "$result")
  
  # Check if result is just empty quotes "" or ''
  if [[ "$result" == '""' || "$result" == "''" ]]; then
    result=""
  else
    # Remove quotes from non-empty values
    result=$(echo "$result" | tr -d '"' | tr -d "'" | xargs 2>/dev/null || echo "$result")
  fi
  
  # Resolve anchor reference if present
  if is_unresolved_anchor "$result"; then
    result=$(resolve_anchor "$result")
  fi
  
  echo "$result"
}

# Get all unique values for a key name anywhere in the file (resolves anchors)
# Usage: yaml_grep_all "file.yaml" "storageClassName"
yaml_grep_all() {
  local file="$1"
  local key_name="$2"
  local results=""

  while IFS= read -r line; do
    local value=$(echo "$line" | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r' | xargs 2>/dev/null || echo "")
    
    # Resolve anchor if it's a reference
    if is_unresolved_anchor "$value"; then
      value=$(resolve_anchor "$value")
    fi
    
    [[ -n "$value" && "$value" != "null" ]] && results="${results}"$'\n'"${value}"
  done < <(grep -E "^[[:space:]]*${key_name}:" "$file" 2>/dev/null || true)

  echo "$results" | sort -u | grep -v "^$" || echo ""
}

# Get YAML anchor value directly by the anchor variable name
# Usage: yaml_get_anchor "file.yaml" "_storageClassName"
# Handles format: _storageClassName: &storageClassName "gp2"
yaml_get_anchor() {
  local file="$1"
  local anchor_var="$2"
  
  local result=$(grep -E "^${anchor_var}:" "$file" 2>/dev/null | head -1 | sed 's/.*&[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r' | xargs 2>/dev/null || echo "")
  
  echo "$result"
}

# Extract IAM role ARNs from file
# Usage: yaml_extract_iam_roles "file.yaml"
yaml_extract_iam_roles() {
  local file="$1"
  grep -oE 'arn:aws:iam::[0-9]+:role/[a-zA-Z0-9_+=,.@-]+' "$file" 2>/dev/null \
    | sort -u \
    || echo ""
}

# Extract IAM role names only (without full ARN)
yaml_extract_iam_role_names() {
  local file="$1"
  grep -oE 'arn:aws:iam::[0-9]+:role/[a-zA-Z0-9_+=,.@-]+' "$file" 2>/dev/null \
    | sed 's|.*role/||' \
    | sort -u \
    || echo ""
}

# Extract Azure Workload Identity client IDs
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

# Extract Azure Workload Identity from anchor
yaml_extract_azure_identity_anchor() {
  local file="$1"
  grep -E "^_workloadIdentityClientId:" "$file" 2>/dev/null \
    | sed 's/.*&[a-zA-Z_]*[[:space:]]*//' \
    | tr -d '"' | tr -d "'" | tr -d '\r' \
    | xargs 2>/dev/null \
    || echo ""
}

# ─────────────────────────── Parse args ───────────────────────
CLOUD=""
VALUES_FILE=""
NAMESPACE=""
SKIP_CLOUD=false
SKIP_K8S=false
AWS_PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)        CLOUD="$2";        shift 2 ;;
    --values)       VALUES_FILE="$2";  shift 2 ;;
    --namespace)    NAMESPACE="$2";    shift 2 ;;
    --aws-profile)  AWS_PROFILE="$2";  shift 2 ;;
    --skip-cloud)   SKIP_CLOUD=true;   shift ;;
    --skip-k8s)     SKIP_K8S=true;     shift ;;
    --help)         usage ;;
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

# IMPORTANT: Parse YAML anchors FIRST before reading any values
parse_yaml_anchors "$VALUES_FILE"

# ─────────────────────────── Read values ──────────────────────
# Global settings - yaml_get now automatically resolves anchor references
STORAGE_BUCKET=$(yaml_get "$VALUES_FILE" "global.storageBucket")
STORAGE_PREFIX=$(yaml_get "$VALUES_FILE" "global.storagePrefix")
EXTERNAL_GATEWAY_HOST=$(yaml_get "$VALUES_FILE" "global.ExternalGatewayHost")
K8S_AUTH_SECRET_NAME=$(yaml_get "$VALUES_FILE" "global.k8s_auth_secret_name")

# Fleets settings
FLEETS_MODE=$(yaml_get "$VALUES_FILE" "global.fleets.mode")
FLEETS_HOSTNAME=$(yaml_get "$VALUES_FILE" "global.fleets.hostName")
FLEETS_DIRECT_HOST=$(yaml_get "$VALUES_FILE" "global.fleets.directHost")
FLEETS_TENANT=$(yaml_get "$VALUES_FILE" "global.fleets.tenant")
EXISTING_SECRET=$(yaml_get "$VALUES_FILE" "fleets.existingSecret")

# Storage classes — collect from anchors and direct values
STORAGE_CLASS_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_storageClassName")
DAGS_STORAGE_CLASS_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_dagsStorageClassName")
STORAGE_CLASSES_RAW=$(yaml_grep_all "$VALUES_FILE" "storageClassName")
STORAGE_CLASS_PERSISTENCE=$(yaml_grep_all "$VALUES_FILE" "storageClass")

# Combine all storage classes
ALL_STORAGE_CLASSES=""
[[ -n "$STORAGE_CLASS_ANCHOR" ]] && ALL_STORAGE_CLASSES="$STORAGE_CLASS_ANCHOR"
[[ -n "$DAGS_STORAGE_CLASS_ANCHOR" ]] && ALL_STORAGE_CLASSES="${ALL_STORAGE_CLASSES}"$'\n'"${DAGS_STORAGE_CLASS_ANCHOR}"
[[ -n "$STORAGE_CLASSES_RAW" ]] && ALL_STORAGE_CLASSES="${ALL_STORAGE_CLASSES}"$'\n'"${STORAGE_CLASSES_RAW}"
[[ -n "$STORAGE_CLASS_PERSISTENCE" ]] && ALL_STORAGE_CLASSES="${ALL_STORAGE_CLASSES}"$'\n'"${STORAGE_CLASS_PERSISTENCE}"
ALL_STORAGE_CLASSES=$(echo "$ALL_STORAGE_CLASSES" | sort -u | grep -v "^$" || echo "")

# AWS-specific values
if [[ "$CLOUD" == "aws" ]]; then
  # ─── Set AWS profile for all subsequent AWS CLI calls ─────────
  # If --aws-profile is passed use it, otherwise honour $AWS_PROFILE env var
  if [[ -n "$AWS_PROFILE" ]]; then
    export AWS_PROFILE="$AWS_PROFILE"
  fi

  # Helper: run any aws command with the active profile
  aws_cmd() { 
    if [[ -n "$AWS_PROFILE" ]]; then
      aws "$@" --profile "$AWS_PROFILE"
    else
      aws "$@"
    fi
  }
  
  # IAM roles
  IAM_ROLES=$(yaml_extract_iam_roles "$VALUES_FILE")
  IAM_ROLE_NAMES=$(yaml_extract_iam_role_names "$VALUES_FILE")
  SERVICE_ROLE_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_serviceRole")
  
  # S3 bucket - fallback to anchor if yaml_get didn't resolve
  S3_BUCKET_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_s3BucketName")
  [[ -z "$STORAGE_BUCKET" || "$STORAGE_BUCKET" == "null" ]] && STORAGE_BUCKET="$S3_BUCKET_ANCHOR"
  
  # Remote log folder
  REMOTE_LOG_FOLDER=$(yaml_get "$VALUES_FILE" "airflow.config.logging.remote_base_log_folder")
  [[ -z "$REMOTE_LOG_FOLDER" || "$REMOTE_LOG_FOLDER" == "null" ]] && REMOTE_LOG_FOLDER=$(yaml_get_anchor "$VALUES_FILE" "_remoteBaseLogFolder")
  
  # Extract S3 log bucket from remote_base_log_folder
  S3_LOG_BUCKET=""
  if [[ -n "$REMOTE_LOG_FOLDER" && "$REMOTE_LOG_FOLDER" == s3://* ]]; then
    S3_LOG_BUCKET=$(echo "$REMOTE_LOG_FOLDER" | sed 's|s3://||' | cut -d'/' -f1)
  fi
  
  # ECR registry URL from ExternalGatewayHost
  EXTERNAL_GW_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_externalGatewayHost")
  [[ -z "$EXTERNAL_GATEWAY_HOST" || "$EXTERNAL_GATEWAY_HOST" == "null" ]] && EXTERNAL_GATEWAY_HOST="$EXTERNAL_GW_ANCHOR"
fi

# Azure-specific values
if [[ "$CLOUD" == "azure" ]]; then
  
  # Workload Identity
  AZURE_WORKLOAD_IDENTITY=$(yaml_extract_azure_identity_anchor "$VALUES_FILE")
  [[ -z "$AZURE_WORKLOAD_IDENTITY" ]] && AZURE_WORKLOAD_IDENTITY=$(yaml_extract_azure_workload_identity "$VALUES_FILE" | head -1)
  
  # Node selector (agentpool)
  AGENTPOOL=$(yaml_get_anchor "$VALUES_FILE" "_agentpool")
  
  # ExternalGatewayHost
  EXTERNAL_GW_ANCHOR=$(yaml_get_anchor "$VALUES_FILE" "_externalGatewayHost")
  [[ -z "$EXTERNAL_GATEWAY_HOST" || "$EXTERNAL_GATEWAY_HOST" == "null" ]] && EXTERNAL_GATEWAY_HOST="$EXTERNAL_GW_ANCHOR"

  # Extract AIRFLOW_CONN_WASB_DEFAULT from airflow.extraEnv block
  WASB_CONN_RAW=$(grep -A1 'AIRFLOW_CONN_WASB_DEFAULT' "$VALUES_FILE" 2>/dev/null \
    | grep 'value:' \
    | sed "s/.*value:[[:space:]]*//" \
    | tr -d '\r' \
    | xargs 2>/dev/null \
    || echo "")

  WASB_CONN_TYPE=$(echo "$WASB_CONN_RAW" | sed -n 's/.*"conn_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || echo "")
  WASB_HOST_RAW=$(echo "$WASB_CONN_RAW" | sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || echo "")
  
  # Resolve Helm template reference to actual anchor value
  # Handle pattern: {{ .Values.global.storageAccountName }}.blob.core.windows.net
  if [[ "$WASB_HOST_RAW" =~ \{\{.*\.Values\.global\.storageAccountName.*\}\} ]]; then
    # Try anchor first
    STORAGE_ACCOUNT_NAME=$(yaml_get_anchor "$VALUES_FILE" "_storageAccountName")
    
    # Fallback to direct value
    if [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
      STORAGE_ACCOUNT_NAME=$(yaml_get "$VALUES_FILE" "global.storageAccountName")
    fi
    
    if [[ -n "$STORAGE_ACCOUNT_NAME" && "$STORAGE_ACCOUNT_NAME" != "null" ]]; then
      WASB_HOST="${STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
    else
      # Keep the template string so it's obvious in error messages
      WASB_HOST="$WASB_HOST_RAW"
      log_warn "Could not resolve {{ .Values.global.storageAccountName }} - check _storageAccountName anchor in values file"
    fi
  else
    WASB_HOST="$WASB_HOST_RAW"
  fi
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
  else
    command -v az &>/dev/null \
      && log_pass "Azure CLI installed" \
      || log_fail "Azure CLI is NOT installed"
  fi
fi

# ─────────────────────────── 1. Required Values ───────────────
log_section "1  Required Values Validation"

# Check critical required fields
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

    # Show which profile is active
    if [[ -n "$AWS_PROFILE" ]]; then
      log_info "Using AWS profile: ${AWS_PROFILE}"
    else
      log_info "Using default AWS profile / environment credentials"
    fi

    # 2a. Authentication
    if aws_cmd sts get-caller-identity &>/dev/null; then
      ACCT=$(aws_cmd sts get-caller-identity --query "Account" --output text 2>/dev/null)
      ARN=$(aws_cmd sts get-caller-identity --query "Arn" --output text 2>/dev/null)
      log_pass "AWS credentials valid (Account: $ACCT | ARN: $ARN)"
    else
      log_fail "AWS credentials invalid — run 'aws sso login --profile <profile>' or check IAM role"
    fi

    # 2b. S3 bucket
    if [[ -n "$STORAGE_BUCKET" && ! "$STORAGE_BUCKET" =~ ^\* ]]; then
      if aws_cmd s3 ls "s3://${STORAGE_BUCKET}" &>/dev/null; then
        log_pass "S3 bucket accessible: s3://${STORAGE_BUCKET}"
      else
        log_fail "S3 bucket NOT accessible: s3://${STORAGE_BUCKET}"
      fi
    else
      log_warn "global.storageBucket is empty or unresolved — skipping S3 check"
    fi

    # 2c. S3 remote log bucket (if different from main bucket)
    if [[ -n "$S3_LOG_BUCKET" && ! "$S3_LOG_BUCKET" =~ ^\* && "$S3_LOG_BUCKET" != "$STORAGE_BUCKET" ]]; then
      if aws_cmd s3 ls "s3://${S3_LOG_BUCKET}" &>/dev/null; then
        log_pass "S3 remote log bucket accessible: s3://${S3_LOG_BUCKET}"
      else
        log_fail "S3 remote log bucket NOT accessible: s3://${S3_LOG_BUCKET}"
      fi
    elif [[ -n "$S3_LOG_BUCKET" && "$S3_LOG_BUCKET" == "$STORAGE_BUCKET" ]]; then
      log_info "Remote log bucket same as storage bucket: ${S3_LOG_BUCKET}"
    fi

    # 2d. IAM roles
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

    # 2e. ECR registry access
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

    # 2a. Authentication
    if az account show &>/dev/null; then
      SUB=$(az account show --query "name" --output tsv 2>/dev/null)
      log_pass "Azure login valid (Subscription: $SUB)"
    else
      log_fail "Azure login invalid — run 'az login'"
    fi

    # 2b. Workload Identity
    if [[ -n "$AZURE_WORKLOAD_IDENTITY" && ! "$AZURE_WORKLOAD_IDENTITY" =~ ^\* ]]; then
      # Validate UUID format
      if [[ "$AZURE_WORKLOAD_IDENTITY" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        log_pass "Workload Identity Client ID format is valid: ${AZURE_WORKLOAD_IDENTITY}"

        # Verify the service principal actually exists in Azure AD
        if az ad sp show --id "$AZURE_WORKLOAD_IDENTITY" &>/dev/null 2>&1; then
          SP_NAME=$(az ad sp show --id "$AZURE_WORKLOAD_IDENTITY" --query "displayName" --output tsv 2>/dev/null || echo "unknown")
          log_pass "Workload Identity Client ID exists in Azure AD (displayName: ${SP_NAME})"
        else
          log_fail "Workload Identity Client ID '${AZURE_WORKLOAD_IDENTITY}' NOT found in Azure AD — verify the client ID is correct"
        fi
      else
        log_fail "Workload Identity Client ID '${AZURE_WORKLOAD_IDENTITY}' has invalid UUID format (expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
      fi
    else
      log_fail "Workload Identity Client ID is missing or unresolved — set _workloadIdentityClientId in values file"
    fi

    # 2c. Node pool (agentpool)
    if [[ -n "$AGENTPOOL" && ! "$AGENTPOOL" =~ ^\* ]]; then
      log_info "Node selector agentpool: ${AGENTPOOL}"
    fi

    # 2d. AIRFLOW_CONN_WASB_DEFAULT validation (Workload Identity-based access)
    if [[ -z "$WASB_CONN_RAW" ]]; then
      log_fail "AIRFLOW_CONN_WASB_DEFAULT is missing from airflow.extraEnv — required for Azure blob storage access"
    else
      log_pass "AIRFLOW_CONN_WASB_DEFAULT entry found in airflow.extraEnv"

      # Validate conn_type
      if [[ "$WASB_CONN_TYPE" == "wasb" ]]; then
        log_pass "WASB conn_type is correct: wasb"
      else
        log_fail "WASB conn_type is '${WASB_CONN_TYPE:-<missing>}' — expected 'wasb'"
      fi

      # Validate host field
      if [[ -z "$WASB_HOST" ]]; then
        log_fail "WASB host could not be resolved from template — check global.storageAccountName anchor"
      elif [[ "$WASB_HOST" == *.blob.core.windows.net ]]; then
        log_pass "WASB host is valid: ${WASB_HOST}"
      else
        log_fail "WASB host format is invalid: ${WASB_HOST} (expected: <account-name>.blob.core.windows.net)"
      fi
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

  # 3a. Cluster reachable
  if kubectl cluster-info &>/dev/null; then
    CLUSTER_EP=$(kubectl cluster-info 2>/dev/null | head -1 | grep -oE 'https?://[^\s]+' || echo "connected")
    log_pass "Cluster reachable: $CLUSTER_EP"
  else
    log_fail "Cannot connect to Kubernetes cluster"
  fi

  # 3b. Node readiness
  READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
  TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)
  [[ "$READY" -gt 0 ]] && log_pass "Nodes ready: ${READY}/${TOTAL}" || log_fail "No nodes Ready"

  # ──────── 3c. Storage classes ────────
  log_section "4  Storage Class Verification"

  if [[ -n "$ALL_STORAGE_CLASSES" ]]; then
    while IFS= read -r sc; do
      # Remove whitespace and carriage returns
      sc=$(echo "$sc" | tr -d '\r' | xargs)
      [[ -z "$sc" ]] && continue
      # Skip unresolved anchor references
      [[ "$sc" =~ ^\* ]] && continue
      if kubectl get storageclass "$sc" &>/dev/null; then
        PROVISIONER=$(kubectl get storageclass "$sc" -o jsonpath='{.provisioner}' 2>/dev/null)
        log_pass "StorageClass '${sc}' exists (provisioner=${PROVISIONER})"
      else
        log_fail "StorageClass '${sc}' NOT found in cluster"
      fi
    done <<< "$ALL_STORAGE_CLASSES"
  else
    log_warn "No storageClassName found in values file"
  fi

  # ──────── 3d. Namespace & SA ────────
  if [[ -n "$NAMESPACE" ]]; then
    log_section "5  Namespace & Service Account Checks"

    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
      log_pass "Namespace '${NAMESPACE}' exists"

      # Check for ServiceAccounts with cloud-specific annotations
      ANNOTATION_KEY=$([[ "$CLOUD" == "aws" ]] && echo "eks.amazonaws.com/role-arn" || echo "azure.workload.identity/client-id")
      SA_MATCHES=$(kubectl get serviceaccount -n "$NAMESPACE" -o yaml 2>/dev/null | grep "$ANNOTATION_KEY" || true)

      if [[ -n "$SA_MATCHES" ]]; then
        MATCH_COUNT=$(echo "$SA_MATCHES" | wc -l)
        log_pass "Found ${MATCH_COUNT} SA(s) with '${ANNOTATION_KEY}' annotation"
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
      
      # Check fleets.existingSecret ONLY when mode is "gateway"
      if [[ "$FLEETS_MODE" == "gateway" ]]; then
        # Trim whitespace and quotes from EXISTING_SECRET
        EXISTING_SECRET_CLEAN=$(echo "$EXISTING_SECRET" | tr -d '"' | tr -d "'" | xargs 2>/dev/null || echo "")
        
        if [[ -n "$EXISTING_SECRET_CLEAN" && "$EXISTING_SECRET_CLEAN" != "null" && ! "$EXISTING_SECRET_CLEAN" =~ ^\* ]]; then
          if kubectl get secret "$EXISTING_SECRET_CLEAN" -n "$NAMESPACE" &>/dev/null; then
            log_pass "Fleets secret '${EXISTING_SECRET_CLEAN}' exists"
          else
            log_fail "Fleets secret '${EXISTING_SECRET_CLEAN}' specified but not found in namespace '${NAMESPACE}'"
          fi
        else
          log_fail "fleets.existingSecret is missing or empty — required when using gateway mode (specify in values file)"
        fi
      elif [[ "$FLEETS_MODE" == "direct" ]]; then
        log_info "Fleets mode is 'direct' — fleets.existingSecret not required"
      fi

      # Check for resource quotas
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

      # Check for existing PVCs that might conflict
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
