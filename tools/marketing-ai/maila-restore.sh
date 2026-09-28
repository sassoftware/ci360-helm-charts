#!/usr/bin/env bash
#
# maila-restore.sh — Restore a Local Agent deployment from a backup archive
#
# Assumes the Helm release is already deployed in the target namespace.
# This script restores data only (no Helm upgrade/install).
#
# Restore order (matches backup order):
#   1. Airflow metadata database (pg_dump SQL)
#   2. DAGs PersistentVolumeClaim contents
#   3. Airflow Variables, Connections, and Pools (unless --minimal)
#
# Requirements: kubectl, tar (no helm or midtier dependency)
#
# Usage:
#   ./maila-restore.sh --release <name> --namespace <ns> --backup <archive>
#
# Options:
#   --release     Helm release name (default: local-agent)
#   --namespace   Kubernetes namespace (default: airflow)
#   --backup      Path to the .tar.gz backup archive created by maila-backup.sh
#   --skip-db     Skip the database restore step
#   --skip-dags   Skip the DAGs PVC restore step
#   --minimal     Only restore database and DAGs (skip Airflow Variables/Connections/Pools)
#   --dry-run     Print steps without executing
#   --help        Show this message
#
# Examples:
#   ./maila-restore.sh --release local-agent --namespace mai --backup ./mai-backup-local-agent-20260601-173203.tar.gz
#   ./maila-restore.sh --release local-agent --namespace mai --backup ./backup.tar.gz --minimal

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
BACKUP_ARCHIVE=""
SKIP_DB=false
SKIP_DAGS=false
MINIMAL=false
DRY_RUN=false
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# ─────────────────────────── Usage ────────────────────────────
usage() {
cat <<EOF
Usage: $0 --release <name> --namespace <ns> --backup <archive> [OPTIONS]

Required:
  --release     Helm release name                              (default: local-agent)
  --namespace   Kubernetes namespace                           (default: airflow)
  --backup      Path to backup archive (.tar.gz)

Optional:
  --skip-db     Skip database restore
  --skip-dags   Skip DAGs PVC restore
  --minimal     Only restore database and DAGs (skip Airflow Variables/Connections/Pools)
  --dry-run     Print steps without executing
  --no-color    Disable colored output (auto-detected when piping)
  --help        Show this message

Examples:
  $0 --release local-agent --namespace mai --backup ./mai-backup-local-agent-20260601-173203.tar.gz
  $0 --release local-agent --namespace mai --backup ./backup.tar.gz --minimal
EOF
exit 0
}

# ─────────────────────────── Arg Parsing ──────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)    RELEASE="$2";          shift 2 ;;
    --namespace)  NAMESPACE="$2";        shift 2 ;;
    --backup)     BACKUP_ARCHIVE="$2";   shift 2 ;;
    --skip-db)    SKIP_DB=true;          shift ;;
    --skip-dags)  SKIP_DAGS=true;        shift ;;
    --minimal)    MINIMAL=true;          shift ;;
    --dry-run)    DRY_RUN=true;          shift ;;
    --no-color)   FORCE_NO_COLOR=true;   shift ;;
    --help|-h)    usage ;;
    *) die "Unknown option: $1. Use --help for usage." ;;
  esac
done

[[ -z "$BACKUP_ARCHIVE" ]] && die "--backup is required. Use --help for usage."
[[ ! -f "$BACKUP_ARCHIVE" ]] && die "Backup archive not found: $BACKUP_ARCHIVE"

# ─────────────────────────── Dry-run wrapper ──────────────────
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
  else
    "$@"
  fi
}

# ─────────────────────────── Confirmation Prompt ──────────────
confirm_destructive() {
  local message="$1"
  echo -e "\n  ${YELLOW}${BOLD}⚠️  WARNING: This is a destructive operation${NC}"
  echo -e "  ${YELLOW}$message${NC}"
  echo -e "  ${CYAN}Type 'yes' to proceed, or anything else to abort: ${NC}"
  read -r confirmation
  if [[ "$confirmation" != "yes" ]]; then
    die "Aborted by user."
  fi
}

# ─────────────────────────── Prerequisites ────────────────────
check_prerequisites() {
  log_section "Checking prerequisites"
  for cmd in kubectl tar; do
    if command -v "$cmd" &>/dev/null; then
      log_pass "$cmd found: $(command -v "$cmd")"
    else
      die "$cmd is required but not found in PATH."
    fi
  done

  log_info "Verifying cluster access..."
  if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    die "Namespace '$NAMESPACE' not found. Ensure the namespace exists before restoring."
  fi
  log_pass "Namespace '$NAMESPACE' accessible"

  log_info "Verifying release '$RELEASE' exists in namespace '$NAMESPACE'..."
  if ! kubectl get deployment -n "$NAMESPACE" -o name 2>/dev/null | grep -q "$RELEASE\|airflow\|scheduler"; then
    log_warn "No obvious Airflow deployment found. Proceeding anyway (release may not be deployed yet)."
  fi
  log_pass "Ready to restore"
}

# ─────────────────────────── Get Pod Helper ───────────────────
get_pod() {
  local selector="$1"
  kubectl get pod -n "$NAMESPACE" -l "$selector" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

# ─────────────────────────── PVC Restore via Temp Pod ─────────
restore_pvc() {
  local pvc_name="$1"
  local tar_file="$2"
  local mount_path="/restore-dst"

  if [[ ! -f "$tar_file" ]]; then
    log_warn "Archive '$tar_file' not found in backup — skipping PVC restore"
    return
  fi

  log_info "Restoring PVC '$pvc_name' from $(basename "$tar_file")"

  local temp_pod="mai-restore-pvc-$$"
  local pod_manifest
  pod_manifest=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${temp_pod}
  namespace: ${NAMESPACE}
  labels:
    app: mai-restore-temp
spec:
  restartPolicy: Never
  containers:
    - name: restore
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: pvc-data
          mountPath: ${mount_path}
  volumes:
    - name: pvc-data
      persistentVolumeClaim:
        claimName: ${pvc_name}
EOF
)

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl apply temp pod for PVC $pvc_name"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl cp ${tar_file} → ${NAMESPACE}/${temp_pod}:${mount_path}"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} tar xzf inside pod"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl delete pod ${temp_pod}"
    return
  fi

  log_info "Creating temporary pod to mount PVC..."
  echo "$pod_manifest" | kubectl apply -f - &>/dev/null

  local attempts=0
  until kubectl get pod "$temp_pod" -n "$NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do
    attempts=$((attempts+1))
    if [[ $attempts -gt 30 ]]; then
      kubectl delete pod "$temp_pod" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
      die "Timed out waiting for temp restore pod '$temp_pod'."
    fi
    sleep 2
  done

  log_info "Copying and extracting archive into PVC..."
  
  # Verify tar file exists before attempting copy
  if [[ ! -f "$tar_file" ]]; then
    kubectl delete pod "$temp_pod" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
    die "Tar file not found: $tar_file"
  fi
  
  # Use stdin/stdout for kubectl cp instead of file paths to avoid Windows path issues
  # This is more reliable on Windows with Git Bash
  log_info "Uploading archive via stdin..."
  cat "$tar_file" | kubectl exec -i "$temp_pod" -n "$NAMESPACE" -- \
    sh -c "cat > /tmp/restore.tar.gz"
  
  log_info "Extracting archive in pod..."
  kubectl exec "$temp_pod" -n "$NAMESPACE" -- \
    sh -c "cd ${mount_path} && tar xzf /tmp/restore.tar.gz --strip-components=0"

  kubectl delete pod "$temp_pod" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
  log_pass "PVC '$pvc_name' restored"
}

# ─────────────────────────── PVC Restore from Plain Folder ────
restore_pvc_folder() {
  local pvc_name="$1"
  local folder_path="$2"
  local mount_path="/restore-dst"

  if [[ ! -d "$folder_path" ]]; then
    log_warn "Folder '$folder_path' not found in backup — skipping PVC restore"
    return
  fi

  log_info "Restoring PVC '$pvc_name' from folder"

  local temp_pod="mai-restore-pvc-$$"
  local pod_manifest
  pod_manifest=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${temp_pod}
  namespace: ${NAMESPACE}
  labels:
    app: mai-restore-temp
spec:
  restartPolicy: Never
  containers:
    - name: restore
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: pvc-data
          mountPath: ${mount_path}
  volumes:
    - name: pvc-data
      persistentVolumeClaim:
        claimName: ${pvc_name}
EOF
)

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl apply temp pod for PVC $pvc_name"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Copy folder contents to pod"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} kubectl delete pod ${temp_pod}"
    return
  fi

  log_info "Creating temporary pod to mount PVC..."
  echo "$pod_manifest" | kubectl apply -f - &>/dev/null

  local attempts=0
  until kubectl get pod "$temp_pod" -n "$NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do
    attempts=$((attempts+1))
    if [[ $attempts -gt 30 ]]; then
      kubectl delete pod "$temp_pod" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
      die "Timed out waiting for temp restore pod '$temp_pod'."
    fi
    sleep 2
  done

  log_info "Copying folder contents to PVC..."
  
  # DEBUG: Uncomment the following to see what files are being backed up
  # Useful for verifying all files are present before transfer
  #
  # log_info "Contents of folder being restored:"
  # ls -la "$folder_path"/ | sed 's/^/    /'
  # log_info "Full file listing:"
  # find "$folder_path" -type f | sort | sed 's/^/    /'
  
  # Create tar stream from the local folder and pipe to pod
  # Preserve full directory structure including subdirectories
  # Using --strip-components=1 to remove only the outer folder wrapper
  # This preserves the inner directory structure (e.g., dags/dags/file.py becomes dags/file.py)
  tar czf - -C "$(dirname "$folder_path")" "$(basename "$folder_path")" | \
    kubectl exec -i "$temp_pod" -n "$NAMESPACE" -- \
      sh -c "cd ${mount_path} && tar xzf - --strip-components=1"
  
  # Verify extraction by listing files in PVC
  log_info "Verifying extraction — files in PVC:"
  kubectl exec "$temp_pod" -n "$NAMESPACE" -- \
    sh -c "find ${mount_path} -type f 2>/dev/null" | sed 's/^/    /'

  kubectl delete pod "$temp_pod" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
  log_pass "PVC '$pvc_name' restored"
}

# ─────────────────────────── DB Restore Helper ────────────────
_restore_db() {
  if [[ ! -f "${BACKUP_DIR}/airflow-db.sql" ]]; then
    die "airflow-db.sql not found in backup archive."
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Discover PostgreSQL pod and restore from airflow-db.sql"
    return
  fi

  # Find the PostgreSQL pod
  POSTGRES_POD=$(get_pod "app.kubernetes.io/component=postgresql,app.kubernetes.io/instance=${RELEASE}") || true
  if [[ -z "$POSTGRES_POD" ]]; then
    POSTGRES_POD=$(get_pod "app.kubernetes.io/component=postgresql,app.kubernetes.io/name=postgresql-ha") || true
  fi

  if [[ -z "$POSTGRES_POD" ]]; then
    die "Could not find a running PostgreSQL pod. Ensure the Helm release is already deployed."
  fi

  log_pass "Found PostgreSQL pod: $POSTGRES_POD"

  # Resolve password inside the pod (same as backup script)
  local pg_pass_cmd='PGPASSWORD=$(cat /opt/bitnami/postgresql/secrets/password 2>/dev/null || cat /run/secrets/password 2>/dev/null || echo "${POSTGRES_PASSWORD:-$POSTGRESQL_PASSWORD}")'

  log_info "Checking for active connections to 'airflow' database..."
  local active_connections
  active_connections=$(kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -c postgresql -- \
    bash -c "${pg_pass_cmd} psql -U postgres -tAc \"SELECT count(*) FROM pg_stat_activity WHERE datname='airflow' AND pid <> pg_backend_pid();\" postgres" 2>/dev/null || echo "0")

  if [[ "$active_connections" -gt 0 ]]; then
    log_warn "Found ${active_connections} active connection(s) to the 'airflow' database."
    log_warn "These are likely live Airflow pods (scheduler, workers, etc.) in this namespace."
    confirm_destructive "Terminate these connections to proceed with schema reset? This will interrupt any running Airflow tasks in namespace '${NAMESPACE}'."
    
    log_info "Terminating active connections..."
    kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -c postgresql -- \
      bash -c "${pg_pass_cmd} psql -U postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='airflow' AND pid <> pg_backend_pid();\" postgres"
    log_pass "Active connections terminated"
  fi

  log_info "Clearing existing schema (DROP SCHEMA public CASCADE)..."
  kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -c postgresql -- \
    bash -c "${pg_pass_cmd} psql -U postgres airflow -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres;'"
  log_pass "Schema cleared"

  log_info "Restoring database from dump (this may take a moment)..."
  kubectl exec -i "$POSTGRES_POD" -n "$NAMESPACE" -c postgresql -- \
    bash -c "${pg_pass_cmd} psql -U postgres airflow" \
    < "${BACKUP_DIR}/airflow-db.sql"

  log_pass "Airflow database restored"
}

# ─────────────────────────── DAGs Restore Helper ──────────────
_restore_dags() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Discover DAGs PVC and restore from dags folder"
    return
  fi

  # Discover DAGs PVC
  DAGS_PVC=$(kubectl get pvc -n "$NAMESPACE" \
    -l "component=dags-pvc" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$DAGS_PVC" ]]; then
    DAGS_PVC=$(kubectl get pvc -n "$NAMESPACE" \
      -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -i dag | head -1 || true)
  fi

  if [[ -z "$DAGS_PVC" ]]; then
    log_warn "No DAGs PVC found in namespace '$NAMESPACE' — skipping"
    return
  fi

  if [[ ! -d "${BACKUP_DIR}/dags" ]]; then
    log_warn "dags folder not found in backup — skipping"
    return
  fi

  # Restore the plain dags folder to the PVC
  log_info "Restoring DAGs folder to PVC '$DAGS_PVC'"
  restore_pvc_folder "$DAGS_PVC" "${BACKUP_DIR}/dags"
}

# ─────────────────────────── Airflow Objects Restore Helper ────
_restore_airflow_objects() {
  # Check if any JSON files exist in backup
  local has_json_files=false
  [[ -f "${BACKUP_DIR}/airflow-variables.json" ]] && has_json_files=true
  [[ -f "${BACKUP_DIR}/airflow-connections.json" ]] && has_json_files=true
  [[ -f "${BACKUP_DIR}/airflow-pools.json" ]] && has_json_files=true

  if [[ "$has_json_files" == "false" ]]; then
    log_info "No Airflow Variables/Connections/Pools JSON files in backup"
    log_info "(All Airflow metadata is covered by the DB restore)"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Discover Airflow scheduler pod and restore Variables/Connections/Pools"
    return
  fi

  # Find scheduler pod (don't require it if no JSON files exist)
  AIRFLOW_POD=$(get_pod "component=scheduler,release=${RELEASE}") || true
  if [[ -z "$AIRFLOW_POD" ]]; then
    log_warn "No running scheduler pod found — skipping Airflow CLI imports (data is in the restored DB)"
    return
  fi

  log_pass "Found Airflow scheduler pod: $AIRFLOW_POD"

  # Restore Variables
  if [[ -f "${BACKUP_DIR}/airflow-variables.json" && -s "${BACKUP_DIR}/airflow-variables.json" ]]; then
    log_info "Importing Airflow Variables..."
    cat "${BACKUP_DIR}/airflow-variables.json" | \
      kubectl exec -i "$AIRFLOW_POD" -n "$NAMESPACE" -- \
        bash -c "cat > /tmp/airflow-variables.json && airflow variables import /tmp/airflow-variables.json"
    log_pass "Airflow Variables imported"
  else
    log_info "No Airflow Variables to restore (file is empty or missing)"
  fi

  # Restore Connections
  if [[ -f "${BACKUP_DIR}/airflow-connections.json" && -s "${BACKUP_DIR}/airflow-connections.json" ]]; then
    log_info "Importing Airflow Connections..."
    cat "${BACKUP_DIR}/airflow-connections.json" | \
      kubectl exec -i "$AIRFLOW_POD" -n "$NAMESPACE" -- \
        bash -c "cat > /tmp/airflow-connections.json && airflow connections import /tmp/airflow-connections.json"
    log_pass "Airflow Connections imported"
  else
    log_info "No Airflow Connections to restore (file is empty or missing)"
  fi

  # Restore Pools
  if [[ -f "${BACKUP_DIR}/airflow-pools.json" && -s "${BACKUP_DIR}/airflow-pools.json" ]]; then
    log_info "Importing Airflow Pools..."
    cat "${BACKUP_DIR}/airflow-pools.json" | \
      kubectl exec -i "$AIRFLOW_POD" -n "$NAMESPACE" -- \
        bash -c "cat > /tmp/airflow-pools.json && airflow pools import /tmp/airflow-pools.json"
    log_pass "Airflow Pools imported"
  else
    log_info "No Airflow Pools to restore (file is empty or missing)"
  fi
}

# ─────────────────────────── Main Restore Logic ───────────────
main() {
  log_header "Local Agent Restore — ${TIMESTAMP}"
  log_info "Release:   $RELEASE"
  log_info "Namespace: $NAMESPACE"
  log_info "Backup:    $BACKUP_ARCHIVE"
  [[ "$DRY_RUN"   == "true" ]] && log_warn "DRY-RUN mode — no changes will be made"
  [[ "$MINIMAL"   == "true" ]] && log_warn "--minimal: Only database and DAGs will be restored"
  [[ "$SKIP_DB"   == "true" ]] && log_warn "--skip-db: Database restore will be skipped"
  [[ "$SKIP_DAGS" == "true" ]] && log_warn "--skip-dags: DAGs PVC restore will be skipped"

  RESTORE_START_TIME=$(date +%s)

  check_prerequisites

  # ── Extract backup archive ─────────────────────────────────
  log_section "Extracting backup archive"
  WORK_DIR=$(mktemp -d)
  BACKUP_DIR="${HOME}/.mai-restore-$$"
  
  cleanup() {
    rm -rf "$WORK_DIR" "$BACKUP_DIR" 2>/dev/null || true
  }
  trap 'cleanup' EXIT

  if [[ "$DRY_RUN" == "false" ]]; then
    tar xzf "$BACKUP_ARCHIVE" -C "$WORK_DIR"
    # Extract the nested backup subdirectory to a persistent location
    # Use tar instead of cp to avoid Windows file permission issues
    local nested_backup=$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    if [[ -n "$nested_backup" && -d "$nested_backup" ]]; then
      mkdir -p "$BACKUP_DIR"
      tar cf - -C "$nested_backup" . | tar xf - -C "$BACKUP_DIR"
    else
      die "Could not find extracted backup directory in archive"
    fi
  fi

  log_pass "Backup extracted to: $BACKUP_DIR"

  # Read and display the manifest
  if [[ -f "${BACKUP_DIR}/backup-manifest.txt" ]]; then
    log_info "Backup manifest:"
    sed 's/^/    /' "${BACKUP_DIR}/backup-manifest.txt"
  fi

  # DEBUG: Uncomment the following section to show detailed backup structure
  # Useful for troubleshooting missing files or directory structure issues
  #
  # log_info "Backup directory structure:"
  # log_info "Top-level contents:"
  # ls -la "$BACKUP_DIR"/ | sed 's/^/    /'
  # 
  # if [[ -d "${BACKUP_DIR}/dags" ]]; then
  #   log_info "Contents of dags folder:"
  #   ls -la "${BACKUP_DIR}/dags"/ | sed 's/^/    /'
  #   log_info "All files under dags (recursive):"
  #   find "${BACKUP_DIR}/dags" -type f | sort | sed 's/^/    /'
  #   log_info "Full dags tree structure:"
  #   tree "${BACKUP_DIR}/dags" 2>/dev/null || find "${BACKUP_DIR}/dags" | sed 's/^/    /'
  # fi

  # Determine step count
  if [[ "$MINIMAL" == "true" ]]; then
    TOTAL_STEPS=2
  else
    TOTAL_STEPS=3
  fi

  # ─────────────────────────────────────────────────────────────
  # STEP 1: Restore Airflow Database
  # ─────────────────────────────────────────────────────────────
  log_section "Step 1/${TOTAL_STEPS} — Restoring Airflow metadata database"
  if [[ "$SKIP_DB" == "true" ]]; then
    log_info "Skipping (--skip-db)"
  else
    _restore_db
  fi

  # ─────────────────────────────────────────────────────────────
  # STEP 2: Restore DAGs PVC
  # ─────────────────────────────────────────────────────────────
  log_section "Step 2/${TOTAL_STEPS} — Restoring DAGs PVC"
  if [[ "$SKIP_DAGS" == "true" ]]; then
    log_info "Skipping (--skip-dags)"
  else
    _restore_dags
  fi

  # ─────────────────────────────────────────────────────────────
  # STEP 3: Restore Airflow Variables, Connections, Pools (if not --minimal)
  # ─────────────────────────────────────────────────────────────
  if [[ "$MINIMAL" == "false" ]]; then
    log_section "Step 3/${TOTAL_STEPS} — Restoring Airflow Variables, Connections, and Pools"
    _restore_airflow_objects
  else
    log_info "--minimal: Skipping Airflow Variables/Connections/Pools"
  fi

  # ── Done ───────────────────────────────────────────────────────
  log_header "Restore Complete"
  log_pass "Release '$RELEASE' data restored in namespace '$NAMESPACE'"
  
  # Calculate elapsed time
  RESTORE_END_TIME=$(date +%s)
  ELAPSED=$((RESTORE_END_TIME - RESTORE_START_TIME))
  MINUTES=$((ELAPSED / 60))
  SECONDS=$((ELAPSED % 60))
  log_pass "Time:    ${MINUTES}m ${SECONDS}s"
  
  log_info "Recommended next steps:"
  echo -e "  1. Verify the Helm release is deployed: kubectl get all -n $NAMESPACE"
  echo -e "  2. Check Airflow pod status: kubectl get pods -n $NAMESPACE | grep airflow"
  echo -e "  3. Verify DAGs are visible in the Airflow UI"
  echo -e "  4. Check that Variables and Connections are present"
  echo -e "  5. Trigger a test DAG run to confirm end-to-end function"
}

main "$@"
