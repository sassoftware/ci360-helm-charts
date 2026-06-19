#!/usr/bin/env bash
#
# maila-backup.sh — Backup a Local Agent (Airflow) deployment
#
# Captures:
#   - Airflow Fernet Key (for secret encryption)
#   - Airflow metadata database (PostgreSQL dump)
#   - DAGs PersistentVolumeClaim (as plain folder)
#   - Airflow Variables, Connections, and Pools
#   - Helm release values
#
# Requirements: kubectl, helm, tar
#
# Usage:
#   ./maila-backup.sh --release <name> --namespace <ns> --output <dir> [OPTIONS]
#
# Examples:
#   # Local backup only
#   ./maila-backup.sh --release ci360-analytic-mai --namespace ci360-analytic-mai --output ./backups
#
#   # Backup and upload to S3 (after: aws configure)
#   ./maila-backup.sh --release ci360-analytic-mai --namespace ci360-analytic-mai --output ./backups \
#     --storage-type s3 --storage-path s3://my-bucket/backups
#
#   # Backup and upload to Azure (after: az login)
#   ./maila-backup.sh --release ci360-analytic-mai --namespace ci360-analytic-mai --output ./backups \
#     --storage-type azure --storage-path mycontainer@mystorageaccount
#
#   # Backup and upload to Google Cloud (after: gcloud auth login)
#   ./maila-backup.sh --release ci360-analytic-mai --namespace ci360-analytic-mai --output ./backups \
#     --storage-type gcs --storage-path gs://my-bucket/backups

set -euo pipefail

# ─────────────────────────── Color Control ────────────────────
# Detect if output is being piped (not a TTY) and disable colors automatically
# Can be overridden with --no-color flag
if [[ ! -t 1 ]]; then
  FORCE_NO_COLOR=true
else
  FORCE_NO_COLOR=false
fi

# ─────────────────────────── Colors ───────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────── Logging ──────────────────────────
# Apply colors only if FORCE_NO_COLOR is false
if [[ "$FORCE_NO_COLOR" == "true" ]]; then
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

log_header()  { echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"; }
log_section() { echo -e "\n${BOLD}── $1 ──${NC}"; }
log_info()    { echo -e "  ℹ️  $(date '+%H:%M:%S') $1"; }
log_pass()    { echo -e "  ${GREEN}✅ $(date '+%H:%M:%S') $1${NC}"; }
log_warn()    { echo -e "  ${YELLOW}⚠️  $(date '+%H:%M:%S') $1${NC}"; }
log_fail()    { echo -e "  ${RED}❌ $(date '+%H:%M:%S') $1${NC}"; }

die() { log_fail "$1"; exit 1; }

# ─────────────────────────── Defaults ─────────────────────────
RELEASE="local-agent"
NAMESPACE="airflow"
OUTPUT_DIR="./mai-backup"
STORAGE_TYPE=""
STORAGE_PATH=""
INCLUDE_LOGS=false
DRY_RUN=false
MINIMAL=false
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# ─────────────────────────── Usage ────────────────────────────
usage() {
cat <<EOF
Usage: $0 --release <name> --namespace <ns> --output <dir> [OPTIONS]

Required:
  --release     Helm release name                     (default: local-agent)
  --namespace   Kubernetes namespace                  (default: airflow)
  --output      Directory to write the backup archive (default: ./mai-backup)

Optional:
  --storage-type    Storage backend: s3, azure, gcs   (default: none)
  --storage-path    Path to upload backup             (format depends on storage type)
  --include-logs    Also back up the Airflow logs PVC (skipped by default)
  --minimal         Only back up DAGs folder, Postgres DB, and Helm values
  --dry-run         Print steps without executing
  --no-color        Disable colored output (auto-detected when piping)
  --help            Show this message

Storage Path Formats:
  S3:              s3://bucket-name/path/to/backup
  Azure Blob:      container_name@storage_account_name
  Google Cloud:    gs://bucket-name/path/to/backup

Prerequisites & Credentials (authenticate before running backup):
  S3:              Install 'aws' CLI, then run: aws configure
  Azure Blob:      Install 'az' CLI, then run: az login
  Google Cloud:    Install 'gcloud' CLI, then run: gcloud auth login

Examples:
  $0 --release local-agent --namespace airflow --output ./backups
  $0 --release local-agent --namespace airflow --output ./backups --storage-type s3 --storage-path s3://my-bucket/backups
  $0 --release local-agent --namespace airflow --output ./backups --storage-type azure --storage-path mycontainer@mystorageaccount
  $0 --release local-agent --namespace airflow --output ./backups --storage-type gcs --storage-path gs://my-bucket/backups
EOF
exit 0
}

# ─────────────────────────── Arg Parsing ──────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)         RELEASE="$2";         shift 2 ;;
    --namespace)       NAMESPACE="$2";       shift 2 ;;
    --output)          OUTPUT_DIR="$2";      shift 2 ;;
    --storage-type)    STORAGE_TYPE="$2";    shift 2 ;;
    --storage-path)    STORAGE_PATH="$2";    shift 2 ;;
    --include-logs)    INCLUDE_LOGS=true;    shift ;;
    --minimal)         MINIMAL=true;         shift ;;
    --dry-run)         DRY_RUN=true;         shift ;;
    --no-color)        FORCE_NO_COLOR=true;  shift ;;
    --help|-h)         usage ;;
    *) die "Unknown option: $1. Use --help for usage." ;;
  esac
done

# ─────────────────────────── Dry-run wrapper ──────────────────
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
  else
    "$@"
  fi
}

# ─────────────────────────── Prerequisites ────────────────────
check_prerequisites() {
  log_section "Checking prerequisites"
  for cmd in kubectl helm tar; do
    if command -v "$cmd" &>/dev/null; then
      log_pass "$cmd found: $(command -v "$cmd")"
    else
      die "$cmd is required but not found in PATH."
    fi
  done

  log_info "Verifying cluster access..."
  if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    die "Namespace '$NAMESPACE' not found. Check your kubectl context and namespace."
  fi
  log_pass "Namespace '$NAMESPACE' accessible"

  log_info "Verifying Helm release..."
  if ! helm status "$RELEASE" -n "$NAMESPACE" &>/dev/null; then
    die "Helm release '$RELEASE' not found in namespace '$NAMESPACE'."
  fi
  log_pass "Helm release '$RELEASE' found"
}

# ─────────────────────────── Resolve Pod Names ────────────────
get_pod() {
  # Usage: get_pod <label-selector>
  local selector="$1"
  kubectl get pod -n "$NAMESPACE" -l "$selector" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

# ─────────────────────────── PVC Backup via Temp Pod ──────────
backup_pvc() {
  local pvc_name="$1"
  local output_folder="$2"
  local mount_path="/backup-src"

  log_info "Backing up PVC '$pvc_name' → ${output_folder}/ (plain folder)"

  local temp_pod="mai-backup-pvc-$$"
  local pod_manifest
  pod_manifest=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${temp_pod}
  namespace: ${NAMESPACE}
  labels:
    app: mai-backup-temp
spec:
  restartPolicy: Never
  containers:
    - name: backup
      image: alpine:latest
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: pvc-data
          mountPath: ${mount_path}
          readOnly: true
  volumes:
    - name: pvc-data
      persistentVolumeClaim:
        claimName: ${pvc_name}
EOF
)

  log_info "Spawning temporary pod '$temp_pod' to mount PVC..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl apply temp pod for PVC $pvc_name"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Copy PVC contents as plain folder using kubectl cp"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl delete pod ${temp_pod}"
    return
  fi

  echo "$pod_manifest" | kubectl apply -f - &>/dev/null

  # Wait for pod to be running
  local attempts=0
  until kubectl get pod "$temp_pod" -n "$NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do
    attempts=$((attempts+1))
    if [[ $attempts -gt 30 ]]; then
      kubectl delete pod "$temp_pod" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
      die "Timed out waiting for temp pod '$temp_pod' to reach Running state."
    fi
    sleep 2
  done

  log_info "Copying PVC contents as plain folder..."
  
  local temp_copy_dir="${WORK_DIR}/.temp-dags-copy"
  mkdir -p "$temp_copy_dir"
  
  # Use kubectl exec with tar to stream data - works cross-platform (Windows + Linux)
  # Stream tar from pod to local tar extraction
  log_info "Streaming PVC contents via tar through kubectl exec..."
  
  kubectl exec "${temp_pod}" -n "$NAMESPACE" -c backup -- \
    sh -c "tar -C '${mount_path}' -cf - ." | tar -xf - -C "$temp_copy_dir"
  
  # Move contents to final location
  if [[ -d "$temp_copy_dir" && $(ls -A "$temp_copy_dir" 2>/dev/null | wc -l) -gt 0 ]]; then
    log_info "Moving copied contents to output folder..."
    mkdir -p "${WORK_DIR}/${output_folder}"
    cp -r "$temp_copy_dir"/* "${WORK_DIR}/${output_folder}/" 2>/dev/null || true
  else
    log_warn "No contents found in PVC"
  fi
  
  rm -rf "$temp_copy_dir"

  DAGS_SIZE=$(du -sh "${WORK_DIR}/${output_folder}" 2>/dev/null | cut -f1 || echo "0")
  log_pass "PVC '$pvc_name' backed up → ${output_folder}/ (${DAGS_SIZE})"

  kubectl delete pod "$temp_pod" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
}

# ─────────────────────────── Storage Upload ───────────────────
upload_to_storage() {
  local archive_path="$1"
  local storage_type="$2"
  local storage_path="$3"
  local archive_filename=$(basename "$archive_path")
  
  if [[ -z "$storage_type" || -z "$storage_path" ]]; then
    return
  fi

  log_section "Uploading backup to storage"
  
  case "$storage_type" in
    s3)
      # Ensure storage_path ends with / so the filename is preserved
      if [[ "$storage_path" != */ ]]; then
        storage_path="${storage_path}/"
      fi
      local s3_destination="${storage_path}${archive_filename}"
      
      log_info "Uploading to S3: $s3_destination"
      if ! command -v aws &>/dev/null; then
        die "AWS CLI is required. Install: https://aws.amazon.com/cli/ then run 'aws configure'"
      fi
      if ! aws sts get-caller-identity &>/dev/null; then
        die "AWS credentials not found or invalid. Run 'aws configure' first"
      fi
      
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} aws s3 cp $archive_path $s3_destination"
      else
        aws s3 cp "$archive_path" "$s3_destination" || die "Failed to upload to S3"
      fi
      log_pass "Backup uploaded to S3: $s3_destination"
      ;;
      
    azure)
      log_info "Uploading to Azure Blob Storage: $storage_path"
      if ! command -v az &>/dev/null; then
        die "Azure CLI is required. Install: https://docs.microsoft.com/cli/azure/install-azure-cli then run 'az login'"
      fi
      if ! az account show &>/dev/null; then
        die "Azure credentials not found. Run 'az login' first"
      fi
      
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} az storage blob upload --file $archive_path --name $(basename $archive_path) --container-name \$container --account-name \$account"
      else
        # Parse container and account from storage_path (format: container_name@storage_account)
        local container="${storage_path%@*}"
        local account="${storage_path#*@}"
        
        if [[ -z "$container" || -z "$account" ]]; then
          die "Invalid Azure storage path format. Use: container_name@storage_account"
        fi
        
        az storage blob upload --file "$archive_path" \
          --name "$archive_filename" \
          --container-name "$container" \
          --account-name "$account" || die "Failed to upload to Azure Blob Storage"
      fi
      log_pass "Backup uploaded to Azure Blob Storage: ${container}/${archive_filename}"
      ;;
      
    gcs)
      # Ensure storage_path ends with / so the filename is preserved
      if [[ "$storage_path" != */ ]]; then
        storage_path="${storage_path}/"
      fi
      local gcs_destination="${storage_path}${archive_filename}"
      
      log_info "Uploading to Google Cloud Storage: $gcs_destination"
      if ! command -v gsutil &>/dev/null; then
        die "Google Cloud SDK is required. Install: https://cloud.google.com/sdk/docs/install then run 'gcloud auth login'"
      fi
      if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        die "Google Cloud credentials not found. Run 'gcloud auth login' first"
      fi
      
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} gsutil cp $archive_path $gcs_destination"
      else
        gsutil cp "$archive_path" "$gcs_destination" || die "Failed to upload to Google Cloud Storage"
      fi
      log_pass "Backup uploaded to Google Cloud Storage: $gcs_destination"
      ;;
      
    *)
      die "Unknown storage type: $storage_type. Supported: s3, azure, gcs"
      ;;
  esac
}

# ─────────────────────────── Main Backup Logic ────────────────
main() {
  log_header "Local Agent Backup — ${TIMESTAMP}"
  log_info "Release:   $RELEASE"
  log_info "Namespace: $NAMESPACE"
  log_info "Output:    $OUTPUT_DIR"
  [[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN mode — no changes will be made"
  [[ "$MINIMAL"  == "true" ]] && log_warn "MINIMAL mode — only DAGs, Postgres, and Helm values"

  BACKUP_START_TIME=$(date +%s)

  check_prerequisites

  # ── Prepare working directory ──────────────────────────────
  ARCHIVE_NAME="mai-backup-${RELEASE}-${TIMESTAMP}"
  WORK_DIR="${OUTPUT_DIR}/${ARCHIVE_NAME}"
  mkdir -p "$WORK_DIR"
  log_info "Working directory: $WORK_DIR"

  # ── Step 1: Extract Fernet Key ─────────────────────────────
  log_section "Step 1/5 — Extracting Airflow Fernet Key"

  AIRFLOW_POD=$(get_pod "component=scheduler,release=${RELEASE}")
  if [[ -z "$AIRFLOW_POD" ]]; then
    AIRFLOW_POD=$(get_pod "dag=scheduler")
  fi

  if [[ -n "$AIRFLOW_POD" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl exec $AIRFLOW_POD -- python -c 'import os; print(os.environ.get(\"AIRFLOW__CORE__FERNET_KEY\", \"\"))'"
    else
      FERNET_KEY=$(kubectl exec "$AIRFLOW_POD" -n "$NAMESPACE" -- \
        python -c 'import os; print(os.environ.get("AIRFLOW__CORE__FERNET_KEY", ""))' 2>/dev/null || true)
      
      if [[ -n "$FERNET_KEY" && "$FERNET_KEY" != "None" ]]; then
        echo "$FERNET_KEY" > "${WORK_DIR}/fernet-key.txt"
        log_pass "Fernet Key extracted → fernet-key.txt"
      else
        log_warn "Could not extract Fernet Key from environment — it may be stored in a secret"
        echo "NOT_FOUND" > "${WORK_DIR}/fernet-key.txt"
      fi
    fi
  else
    log_warn "No running scheduler pod found — cannot extract Fernet Key"
    echo "NOT_FOUND" > "${WORK_DIR}/fernet-key.txt"
  fi

  # ── Step 2: Postgres dump ──────────────────────────────────
  log_section "Step 2/5 — Dumping Airflow metadata database (pg_dump)"
  
  POSTGRES_POD=$(get_pod "app.kubernetes.io/component=postgresql,app.kubernetes.io/instance=${RELEASE}")
  if [[ -z "$POSTGRES_POD" ]]; then
    POSTGRES_POD=$(get_pod "app.kubernetes.io/component=postgresql,app.kubernetes.io/name=postgresql-ha")
  fi
  if [[ -z "$POSTGRES_POD" ]]; then
    die "Could not find a running Postgres pod. Confirm the release name and namespace."
  fi
  log_info "Using Postgres pod: $POSTGRES_POD"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl exec $POSTGRES_POD -n $NAMESPACE -- pg_dump -U postgres airflow > ${WORK_DIR}/airflow-db.sql"
  else
    kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -c postgresql -- \
      bash -c 'PGPASSWORD=$(cat /opt/bitnami/postgresql/secrets/password 2>/dev/null || cat /run/secrets/password 2>/dev/null || echo "${POSTGRES_PASSWORD:-$POSTGRESQL_PASSWORD}") pg_dump -U postgres airflow' \
      > "${WORK_DIR}/airflow-db.sql"
  fi
  log_pass "Database dump saved → airflow-db.sql"

  # ── Step 3: Back up DAGs PVC ──────────────────────────────
  log_section "Step 3/5 — Backing up DAGs folder (PVC)"

  DAGS_PVC=$(kubectl get pvc -n "$NAMESPACE" \
    -l "component=dags-pvc" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$DAGS_PVC" ]]; then
    DAGS_PVC=$(kubectl get pvc -n "$NAMESPACE" \
      -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -i dag | head -1 || true)
  fi

  if [[ -n "$DAGS_PVC" ]]; then
    backup_pvc "$DAGS_PVC" "dags"
  else
    log_warn "No DAGs PVC found in namespace '$NAMESPACE' — skipping"
  fi

  # ── Step 4: Export Airflow Variables, Connections, Pools ──
  log_section "Step 4/5 — Exporting Airflow Variables, Connections, and Pools"
  if [[ "$MINIMAL" == "true" ]]; then
    log_info "Skipping (--minimal)"
  else
    AIRFLOW_POD=$(get_pod "component=scheduler,release=${RELEASE}")
    if [[ -z "$AIRFLOW_POD" ]]; then
      AIRFLOW_POD=$(get_pod "dag=scheduler")
    fi

    if [[ -n "$AIRFLOW_POD" ]]; then
      log_info "Exporting Airflow Variables..."
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl exec $AIRFLOW_POD -- airflow variables export /tmp/airflow-variables.json"
      else
        kubectl exec "$AIRFLOW_POD" -n "$NAMESPACE" -- \
          bash -c 'airflow variables export /tmp/airflow-variables.json >/dev/null 2>&1 && cat /tmp/airflow-variables.json' \
          > "${WORK_DIR}/airflow-variables.json" 2>/dev/null || {
          log_warn "Failed to export Variables — creating empty file"
          echo "{}" > "${WORK_DIR}/airflow-variables.json"
        }
      fi
      if [[ -s "${WORK_DIR}/airflow-variables.json" ]]; then
        log_pass "Airflow Variables exported → airflow-variables.json"
      else
        log_warn "Airflow Variables export returned empty or failed"
      fi

      log_info "Exporting Airflow Pools..."
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl exec $AIRFLOW_POD -- airflow pools export /tmp/airflow-pools.json"
      else
        kubectl exec "$AIRFLOW_POD" -n "$NAMESPACE" -- \
          bash -c 'airflow pools export /tmp/airflow-pools.json >/dev/null 2>&1 && cat /tmp/airflow-pools.json' \
          > "${WORK_DIR}/airflow-pools.json" 2>/dev/null || {
          log_warn "Failed to export Pools — creating empty file"
          echo "{}" > "${WORK_DIR}/airflow-pools.json"
        }
      fi
      if [[ -s "${WORK_DIR}/airflow-pools.json" ]]; then
        log_pass "Airflow Pools exported → airflow-pools.json"
      else
        log_warn "Airflow Pools export returned empty or failed"
      fi

      log_info "Exporting Airflow Connections..."
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl exec $AIRFLOW_POD -- airflow connections export /tmp/airflow-connections.json"
      else
        kubectl exec "$AIRFLOW_POD" -n "$NAMESPACE" -- \
          bash -c 'airflow connections export /tmp/airflow-connections.json >/dev/null 2>&1 && cat /tmp/airflow-connections.json' \
          > "${WORK_DIR}/airflow-connections.json" 2>/dev/null || {
          log_warn "Failed to export Connections — creating empty file"
          echo "{}" > "${WORK_DIR}/airflow-connections.json"
        }
      fi
      if [[ -s "${WORK_DIR}/airflow-connections.json" ]]; then
        log_pass "Airflow Connections exported → airflow-connections.json"
      else
        log_warn "Airflow Connections export returned empty or failed"
      fi
    else
      log_warn "No running scheduler pod found — skipping Airflow CLI exports (covered by DB dump)"
    fi
  fi

  # ── Step 5: Save Helm values ───────────────────────────────
  log_section "Step 5/5 — Saving Helm values"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} helm get values $RELEASE -n $NAMESPACE -o yaml > ${WORK_DIR}/helm-values.yaml"
  else
    helm get values "$RELEASE" -n "$NAMESPACE" -o yaml > "${WORK_DIR}/helm-values.yaml" 2>/dev/null || \
      helm get values "$RELEASE" -n "$NAMESPACE" > "${WORK_DIR}/helm-values.yaml"
  fi
  log_pass "Helm values saved → helm-values.yaml"

  # ── Write manifest ─────────────────────────────────────────
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} write backup-manifest.txt to ${WORK_DIR}/"
  else
    # Get Helm release chart version (e.g., 0.36.0 from marketing-ai-0.36.0)
    # Strip the known chart name prefix
    HELM_VERSION=$(helm list -n "$NAMESPACE" -o json 2>/dev/null | grep -o "\"chart\":\"[^\"]*" | sed 's/"chart":"\(marketing-ai-\)\?//' | sed 's/".*//' | head -1 || echo "unknown")
    
    cat > "${WORK_DIR}/backup-manifest.txt" <<EOF
backup-version: 1
timestamp: ${TIMESTAMP}
release: ${RELEASE}
mai-release-version: ${HELM_VERSION}
namespace: ${NAMESPACE}
include-logs: ${INCLUDE_LOGS}
files:
$(ls "${WORK_DIR}/" | grep -v backup-manifest.txt | sed 's/^/  - /')
EOF
  fi

  # ── Create final archive ───────────────────────────────────
  log_section "Finalizing archive"
  ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}.tar.gz"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} tar czf ${ARCHIVE_PATH} -C ${OUTPUT_DIR} ${ARCHIVE_NAME}"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} rm -rf ${WORK_DIR}"
  else
    tar czf "$ARCHIVE_PATH" -C "$OUTPUT_DIR" "$ARCHIVE_NAME"
    rm -rf "$WORK_DIR"
  fi

  log_header "Backup Complete"
  if [[ "$DRY_RUN" == "true" ]]; then
    log_pass "Archive (dry-run): ${ARCHIVE_PATH}"
  else
    ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" | cut -f1)
    log_pass "Archive: ${ARCHIVE_PATH}"
    log_pass "Size:    ${ARCHIVE_SIZE}"
  fi
  
  # Calculate elapsed time
  BACKUP_END_TIME=$(date +%s)
  ELAPSED=$((BACKUP_END_TIME - BACKUP_START_TIME))
  MINUTES=$((ELAPSED / 60))
  SECONDS=$((ELAPSED % 60))
  log_pass "Time:    ${MINUTES}m ${SECONDS}s"
  
  # Upload to storage if specified
  if [[ -n "$STORAGE_TYPE" ]]; then
    upload_to_storage "$ARCHIVE_PATH" "$STORAGE_TYPE" "$STORAGE_PATH"
  fi
  
  log_info "To restore, run:"
  echo -e "  ${CYAN}./tools/maila-restore.sh --release ${RELEASE} --namespace ${NAMESPACE} --backup ${ARCHIVE_PATH}${NC}"
}

main "$@"


