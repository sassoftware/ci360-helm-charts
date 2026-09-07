#!/usr/bin/env bash
###############################################################################
# # Setup Prerequisites Tools — maila-setup-prerequisites.sh
#
# ## Synopsis
#
# ```bash
# ./maila-setup-prerequisites.sh --cloud <aws|azure|gcp> [OPTIONS]
# ```
#
# ## Description
#
# CloudShell Environment Bootstrap Script for CI360 Marketing AI (MAI).
#
# This utility automates the validation and installation of CLI tools
# required to deploy CI360 Marketing AI workloads on Kubernetes. It is
# designed to run in cloud-provider shell environments (AWS CloudShell,
# Azure Cloud Shell, GCP Cloud Shell) as well as local Linux, macOS, and
# WSL terminals.
#
# ### What the script does
#
# 1. **Detects the runtime environment** — identifies the operating system,
#    CPU architecture, and whether the session is running inside a
#    cloud-managed shell (AWS CloudShell, Azure Cloud Shell, GCP Cloud Shell).
#
# 2. **Installs or upgrades kubectl** — downloads the pinned (or user-
#    specified) version of `kubectl` and places it in `--install-dir`.
#    The requested version is validated against the minimum before download.
#
# 3. **Verifies Helm (manual install only)** — checks that an acceptable
#    version of Helm (v3.18.x or v3.19.x) is already present on the system.
#    **Helm is NOT auto-installed by this script.** If Helm is missing or
#    outside the supported range the script prints detailed manual install
#    instructions and marks the check as failed.
#
# 4. **Installs or upgrades KEDA** — uses Helm to add the `kedacore`
#    chart repository, install (or upgrade) the KEDA operator into the
#    `keda` namespace, waits for rollout readiness, and verifies the
#    running version. If existing KEDA resources are present but were not
#    originally installed via Helm, the script attempts to adopt them by
#    adding the required Helm ownership labels/annotations before retrying
#    the install.
#
# 5. **Installs or upgrades the cloud-provider CLI** — installs the
#    appropriate CLI for the chosen `--cloud` provider:
#      - **aws**   → AWS CLI v2
#      - **azure** → Azure CLI (`az`)
#      - **gcp**   → Google Cloud CLI (`gcloud`)
#    In cloud-managed shells the provider CLI is pre-installed and cannot
#    be upgraded; the script detects this, prints the current version, and
#    skips the upgrade gracefully.
#
# 6. **Prints a summary report** — shows per-tool status (installed /
#    skipped / failed) and exits with an appropriate code.
#
# ## Prerequisites
#
# The following must be available before running this script:
#
# | Dependency | Purpose |
# |------------|---------|
# | `bash` ≥ 4.0 | Associative arrays (`declare -A`) |
# | `curl` | Downloading binaries |
# | `tar`, `unzip` | Extracting archives |
# | `sort -V` | Version comparison (GNU coreutils) |
# | `sudo` | Installing to system paths (non-CloudShell) |
# | **Helm v3.18.x or v3.19.x** | **Must be installed manually before running this script** |
#
# ### Installing Helm (manual step)
#
# Helm is intentionally excluded from automatic installation. Install it
# before running this script:
#
# ```bash
# # Linux / WSL (amd64)
# curl -fsSL https://get.helm.sh/helm-v3.18.1-linux-amd64.tar.gz | tar -xz
# sudo mv linux-amd64/helm /usr/local/bin/helm
#
# # Linux / WSL (arm64)
# curl -fsSL https://get.helm.sh/helm-v3.18.1-linux-arm64.tar.gz | tar -xz
# sudo mv linux-arm64/helm /usr/local/bin/helm
#
# # macOS (Homebrew)
# brew install helm
#
# # Windows (Chocolatey)
# choco install kubernetes-helm
#
# # Official docs
# # https://helm.sh/docs/intro/install/
# ```
#
# ## Options
#
# | Option | Description |
# |--------|-------------|
# | `-h, --help` | Show help message and exit |
# | `-q, --quiet` | Suppress non-essential output (useful for CI/CD) |
# | `-f, --force` | Force reinstall of all tools even if already installed |
# | `-d, --dry-run` | Show what would be installed without making changes |
# | `--cloud <provider>` | Cloud provider: `aws`, `azure`, or `gcp` **(required)** |
# | `--skip-autocomplete` | Skip shell autocomplete configuration |
# | `--install-dir <path>` | Custom installation directory (default: `~/.local/bin`) |
# | `--tools <list>` | Install only specific tools (comma-separated). Available: `kubectl`, `helm`, `keda`, `aws-cli`, `azure-cli`, `gcloud-cli` |
# | `--retries <n>` | Number of download retry attempts (default: 3) |
# | `--retry-delay <s>` | Delay between retries in seconds (default: 3) |
# | `--kubectl-version <v>` | Specific kubectl version to install (default: v1.33.0). Must be ≥ v1.27.0 |
# | `--helm-version <v>` | Expected Helm version for verification — **only v3.18.x and v3.19.x are accepted**. Helm is NOT auto-installed; the script verifies only |
#
# ## Minimum Required Versions
#
# | Tool | Minimum | Maximum | Auto-Install |
# |------|---------|---------|--------------|
# | kubectl | v1.27.0 | — | ✓ Yes |
# | helm | v3.18.0 | v3.19.x | ✗ No (verify only) |
# | KEDA | v2.19.0 | — | ✓ Yes (via Helm) |
# | aws-cli | 2.18.1 | — | ✓ Yes (AWS only) |
# | azure-cli | 2.83.0 | — | ✓ Yes (Azure only) |
# | gcloud-cli | 512.0.0 | — | ✓ Yes (GCP only) |
#
# ## Cloud Shell Behaviour
#
# | Environment | Detection | Cloud CLI Handling |
# |-------------|-----------|-------------------|
# | AWS CloudShell | `$AWS_EXECUTION_ENV`, `/home/cloudshell-user` | Skip upgrade — managed by AWS |
# | Azure Cloud Shell | `$AZUREPS_HOST_ENVIRONMENT`, `$ACC_CLOUD`, `/opt/azure` | Skip upgrade — managed by Microsoft |
# | GCP Cloud Shell | `$CLOUD_SHELL`, `$DEVSHELL_GCLOUD_CONFIG`, `/google/devshell` | Skip upgrade — managed by Google |
#
# In managed cloud shells the provider CLI is pre-installed and cannot be
# upgraded by end users. The script detects this, reports the current
# version, and skips the upgrade without failing. If the version is below
# the minimum a warning is printed.
#
# ## Examples
#
# ```bash
# # Install all tools for AWS
# ./maila-setup-prerequisites.sh --cloud aws
#
# # Install all tools for Azure
# ./maila-setup-prerequisites.sh --cloud azure
#
# # Install all tools for GCP
# ./maila-setup-prerequisites.sh --cloud gcp
#
# # Install only kubectl (skip helm/keda/cloud-cli)
# ./maila-setup-prerequisites.sh --cloud aws --tools kubectl
#
# # Install only kubectl and verify helm
# ./maila-setup-prerequisites.sh --cloud aws --tools kubectl,helm
#
# # Force reinstall all tools (including KEDA upgrade)
# ./maila-setup-prerequisites.sh --cloud aws --force
#
# # Dry run — show what would happen without making changes
# ./maila-setup-prerequisites.sh --cloud azure --dry-run
#
# # Install to a custom directory
# ./maila-setup-prerequisites.sh --cloud aws --install-dir /opt/bin
#
# # Quiet mode for CI/CD pipelines
# ./maila-setup-prerequisites.sh --cloud azure --quiet
#
# # Increase retries for slow connections
# ./maila-setup-prerequisites.sh --cloud gcp --retries 5 --retry-delay 10
#
# # Use a specific kubectl version
# ./maila-setup-prerequisites.sh --cloud aws --kubectl-version v1.32.0
#
# # Skip shell autocomplete setup
# ./maila-setup-prerequisites.sh --cloud aws --skip-autocomplete
# ```
#
# ## Exit Codes
#
# | Code | Description |
# |------|-------------|
# | 0 | Success (all tools ready, or completed with non-fatal warnings) |
# | 1 | General error |
# | 2 | Invalid arguments (missing `--cloud`, unsupported version, etc.) |
# | 3 | Missing dependencies |
# | 4 | One or more tool installations/verifications failed |
#
###############################################################################

set -euo pipefail

#######################################
# 1. Global Configuration (variables)
#######################################
MAX_RETRIES=3
RETRY_DELAY=3
INSTALL_DIR="${HOME}/.local/bin"

# Cloud provider (must be specified via --cloud)
CLOUD_PROVIDER=""

# Feature flags
QUIET_MODE=false
FORCE_REINSTALL=false
DRY_RUN=false
SKIP_AUTOCOMPLETE=false
SELECTED_TOOLS=""

# Minimum required versions
MIN_KUBECTL_VERSION="1.27.0"
MIN_HELM_VERSION="3.18.0"
MAX_HELM_VERSION="3.19.999"
MIN_AWS_CLI_VERSION="2.18.1"
MIN_AZURE_CLI_VERSION="2.83.0"
MIN_GCLOUD_CLI_VERSION="512.0.0"
MIN_KEDA_VERSION="2.19.0"

# Pinned versions for installation
KUBECTL_VERSION="v1.33.0"
HELM_REQUIRED_VERSION="3.18.1"
HELM_VERSION="${HELM_REQUIRED_VERSION}"
AWS_CLI_VERSION="2.18.1"
AZURE_CLI_VERSION="2.83.0"
GCLOUD_CLI_VERSION="512.0.0"
KEDA_VERSION="2.19.0"
KEDA_NAMESPACE="keda"

# Platform and architecture (set later by detect_platform)
PLATFORM=""
ARCH=""

# Installation tracking
declare -A PRE_INSTALL_VERSIONS
declare -A INSTALL_STATUS

#######################################
# 2. Logging Functions
#######################################
log_info() {
  if [[ "$QUIET_MODE" == false ]]; then
    echo "[INFO]    $*"
  fi
}

log_success() {
  echo "[SUCCESS] $*"
}

log_warn() {
  echo "[WARN]    $*"
}

log_error() {
  echo "[ERROR]   $*" >&2
}

log_dry_run() {
  echo "[DRY-RUN] $*"
}

#######################################
# 3. Utility Functions
#######################################
command_exists() {
  command -v "$1" &>/dev/null
}

# Compare versions: returns 0 if $1 >= $2
version_gte() {
  local v1="$1"
  local v2="$2"

  # Strip leading 'v' if present
  v1="${v1#v}"
  v2="${v2#v}"

  # Use sort -V for version comparison
  if [[ "$(printf '%s\n%s' "$v2" "$v1" | sort -V | head -n1)" == "$v2" ]]; then
    return 0
  else
    return 1
  fi
}

download_file() {
  local url="$1"
  local output="$2"
  local attempt=0

  while (( attempt < MAX_RETRIES )); do
    if curl -fsSL --retry 3 --retry-delay "$RETRY_DELAY" -o "$output" "$url"; then
      return 0
    fi
    ((attempt++))
    log_warn "Download failed (attempt ${attempt}/${MAX_RETRIES}), retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
  done

  log_error "Failed to download: $url after ${MAX_RETRIES} attempts"
  return 1
}

track_install() {
  local tool="$1"
  local status="$2"
  local detail="${3:-}"
  INSTALL_STATUS["$tool"]="${status}|${detail}"
}

#######################################
# 4. Cloud Shell Detection
#######################################
is_azure_cloudshell() {
  # Azure CloudShell environment variables
  [[ -n "${AZUREPS_HOST_ENVIRONMENT:-}" ]] && return 0
  [[ "${ACC_CLOUD:-}" == "true" ]] && return 0

  # File system checks
  [[ -f "/usr/bin/cloud-init" && -d "/opt/azure" ]] && return 0

  return 1
}

is_aws_cloudshell() {
  # AWS CloudShell environment variables
  [[ "${AWS_EXECUTION_ENV:-}" == "CloudShell" ]] && return 0

  # File system checks
  [[ -d "/home/cloudshell-user" ]] && return 0

  return 1
}

is_gcp_cloudshell() {
  # GCP Cloud Shell environment variables
  [[ "${CLOUD_SHELL:-}" == "true" ]] && return 0
  [[ -n "${DEVSHELL_GCLOUD_CONFIG:-}" ]] && return 0

  # File system checks
  [[ -d "/google/devshell" ]] && return 0

  return 1
}

is_any_cloudshell() {
  is_azure_cloudshell || is_aws_cloudshell || is_gcp_cloudshell
}

#######################################
# 5. Platform Detection
#######################################
detect_platform() {
  local platform="unknown"
  local os_type=""

  # Detect OS
  if [[ -n "${OSTYPE:-}" ]]; then
    case "$OSTYPE" in
      linux*) os_type="linux" ;;
      darwin*) os_type="macos" ;;
      msys*|mingw*|cygwin*) os_type="windows" ;;
      *) os_type="unknown" ;;
    esac
  else
    os_type="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo 'unknown')"
  fi

  # Detect specific environments
  if is_azure_cloudshell; then
    platform="azure-cloudshell"
  elif is_aws_cloudshell; then
    platform="aws-cloudshell"
  elif is_gcp_cloudshell; then
    platform="gcp-cloudshell"
  elif [[ "$os_type" == "windows" ]] || [[ -n "${MSYSTEM:-}" ]]; then
    platform="windows-bash"
  elif [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
    platform="wsl"
  elif [[ "$os_type" == "macos" ]]; then
    platform="macos"
  elif [[ "$os_type" == "linux" ]]; then
    platform="linux"
  fi

  echo "$platform"
}

detect_arch() {
  local arch
  arch="$(uname -m 2>/dev/null || echo 'x86_64')"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;
  esac
}

#######################################
# 6. Version Detection
#######################################
get_tool_version() {
  local tool="$1"
  local version=""

  case "$tool" in
    kubectl)
      version=$(kubectl version --client 2>/dev/null | sed -n 's/.*v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
      version="${version:-0.0.0}"
      ;;
    helm)
      # Try multiple patterns for different helm output formats
      version=$(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^v//')

      if [[ -z "$version" || "$version" == "0.0.0" ]]; then
        version=$(helm version 2>/dev/null | sed -n 's/.*Version:"\(v\?[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?\)".*/\1/p' | sed 's/^v//' | head -1)
      fi

      if [[ -z "$version" || "$version" == "0.0.0" ]]; then
        version=$(helm version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^v//')
      fi

      # Normalize 2-part versions to 3-part (3.18 → 3.18.0)
      if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        version="${version}.0"
      fi

      version="${version:-0.0.0}"
      ;;
    aws|aws-cli)
      version=$(aws --version 2>/dev/null | sed -n 's/aws-cli\/\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
      version="${version:-0.0.0}"
      ;;
    az|azure-cli)
      version=$(az version -o json 2>/dev/null | grep -oE '"azure-cli": "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

      if [[ -z "$version" || "$version" == "0.0.0" ]]; then
        version=$(az version -o tsv 2>/dev/null | head -1 | awk '{print $1}')
      fi

      version="${version:-0.0.0}"
      ;;
    gcloud|gcloud-cli)
      version=$(gcloud version 2>/dev/null | grep "Google Cloud SDK" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

      if [[ -z "$version" || "$version" == "0.0.0" ]]; then
        version=$(gcloud --version 2>/dev/null | grep "Google Cloud SDK" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      fi

      version="${version:-0.0.0}"
      ;;
    keda)
      if ! command_exists kubectl; then
        version="0.0.0"
      elif kubectl get namespace "$KEDA_NAMESPACE" &>/dev/null; then
        version=$(kubectl get deployment keda-operator -n "$KEDA_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

        if [[ -z "$version" || "$version" == "0.0.0" ]]; then
          version=$(kubectl get deployment keda-operator-metrics-apiserver -n "$KEDA_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi

        version="${version:-0.0.0}"
      else
        version="0.0.0"
      fi
      ;;
  esac

  echo "$version"
}

#######################################
# 7. Check if tool should be installed
#######################################
should_install() {
  local tool="$1"
  local min_version="${2:-}"

  # If --tools was specified, skip tools not in the list
  if [[ -n "$SELECTED_TOOLS" ]]; then
    if [[ ",$SELECTED_TOOLS," != *",$tool,"* ]]; then
      log_info "Skipping $tool (not in --tools list)"
      return 1
    fi
  fi

  # Map tool names for command check
  local cmd="$tool"
  case "$tool" in
    aws-cli) cmd="aws" ;;
    azure-cli) cmd="az" ;;
    gcloud-cli) cmd="gcloud" ;;
    keda) cmd="kubectl" ;;
  esac

  # Force reinstall overrides everything
  if [[ "$FORCE_REINSTALL" == true ]]; then
    return 0
  fi

  # If tool is not installed, we need to install it
  if ! command_exists "$cmd"; then
    return 0
  fi

  # If minimum version specified, check if upgrade needed
  if [[ -n "$min_version" ]]; then
    local current_version
    current_version=$(get_tool_version "$tool")
    if ! version_gte "$current_version" "$min_version"; then
      return 0
    fi
  fi

  # Tool exists and meets minimum version
  return 1
}

#######################################
# 8. Installation Functions
#######################################
install_kubectl() {
  log_info "Installing kubectl ${KUBECTL_VERSION} (minimum: v${MIN_KUBECTL_VERSION})..."

  # Validate requested version against minimum
  local requested_ver="${KUBECTL_VERSION#v}"
  if ! version_gte "$requested_ver" "$MIN_KUBECTL_VERSION"; then
    log_error "Requested kubectl version ${KUBECTL_VERSION} is below minimum v${MIN_KUBECTL_VERSION}"
    log_error "Please specify a version >= v${MIN_KUBECTL_VERSION} using --kubectl-version"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install kubectl ${KUBECTL_VERSION}"
    return 0
  fi

  local kubectl_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  if [[ "$ARCH" == "arm64" ]]; then
    kubectl_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl"
  fi

  mkdir -p "$INSTALL_DIR"
  download_file "$kubectl_url" "${INSTALL_DIR}/kubectl"
  chmod +x "${INSTALL_DIR}/kubectl"

  # Verify installation
  if ! "${INSTALL_DIR}/kubectl" version --client &>/dev/null; then
    log_error "kubectl installation verification failed"
    return 1
  fi

  local installed_ver
  installed_ver=$(get_tool_version kubectl)
  log_success "kubectl installed: v${installed_ver}"
}

install_aws_cli() {
  log_info "Installing AWS CLI ${AWS_CLI_VERSION} (minimum: ${MIN_AWS_CLI_VERSION})..."

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install AWS CLI ${AWS_CLI_VERSION}"
    return 0
  fi

  # Check if running in AWS CloudShell (managed environment)
  if is_aws_cloudshell; then
    log_warn "AWS CloudShell detected — AWS CLI is pre-installed and managed by AWS."
    local current_ver
    current_ver=$(get_tool_version aws-cli)
    log_warn "Current version: ${current_ver}"
    log_warn "Cannot upgrade AWS CLI in CloudShell. It is managed by AWS."
    return 1
  fi

  cd /tmp
  local aws_archive="awscliv2.zip"
  download_file "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" "$aws_archive"
  unzip -qo "$aws_archive"

  if [[ -d "/usr/local/aws-cli" ]]; then
    sudo ./aws/install --update
  else
    sudo ./aws/install
  fi

  rm -rf aws "$aws_archive"

  # Verify installation
  if ! aws --version &>/dev/null; then
    log_error "AWS CLI installation verification failed"
    return 1
  fi

  local installed_ver
  installed_ver=$(get_tool_version aws-cli)
  log_success "AWS CLI installed: ${installed_ver}"
}

install_azure_cli() {
  log_info "Installing Azure CLI ${AZURE_CLI_VERSION} (minimum: ${MIN_AZURE_CLI_VERSION})..."

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install Azure CLI ${AZURE_CLI_VERSION}"
    return 0
  fi

  # Check if running in Azure Cloud Shell (managed environment)
  if is_azure_cloudshell; then
    log_warn "Azure Cloud Shell detected — Azure CLI is pre-installed and managed by Microsoft."
    local current_ver
    current_ver=$(get_tool_version azure-cli)
    log_warn "Current version: ${current_ver}"
    log_warn "Cannot upgrade Azure CLI in Cloud Shell. It is managed by Microsoft."

    if ! version_gte "$current_ver" "$MIN_AZURE_CLI_VERSION"; then
      log_warn "Version ${current_ver} is below minimum ${MIN_AZURE_CLI_VERSION}"
      log_warn "Azure Cloud Shell will be updated by Microsoft in future releases."
    fi

    return 1
  fi

  # Install via Microsoft's install script
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

  # Verify installation
  if ! az version &>/dev/null; then
    log_error "Azure CLI installation verification failed"
    return 1
  fi

  local installed_ver
  installed_ver=$(get_tool_version azure-cli)
  log_success "Azure CLI installed: ${installed_ver}"
}

install_gcloud_cli() {
  log_info "Installing Google Cloud CLI ${GCLOUD_CLI_VERSION} (minimum: ${MIN_GCLOUD_CLI_VERSION})..."

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install Google Cloud CLI ${GCLOUD_CLI_VERSION}"
    return 0
  fi

  # Check if running in GCP Cloud Shell (managed environment)
  if is_gcp_cloudshell; then
    log_warn "GCP Cloud Shell detected — gcloud CLI is pre-installed and managed by Google."
    local current_ver
    current_ver=$(get_tool_version gcloud-cli)
    log_warn "Current version: ${current_ver}"
    log_warn "Cannot upgrade gcloud CLI in Cloud Shell. It is managed by Google."

    if ! version_gte "$current_ver" "$MIN_GCLOUD_CLI_VERSION"; then
      log_warn "Version ${current_ver} is below minimum ${MIN_GCLOUD_CLI_VERSION}"
      log_warn "GCP Cloud Shell will be updated by Google in future releases."
    fi

    return 1  # Don't fail - just skip upgrade
  fi

  case "$PLATFORM" in
    macos)
      if command_exists brew; then
        log_info "Installing Google Cloud CLI via Homebrew..."
        brew install --cask google-cloud-sdk
      else
        log_info "Downloading Google Cloud CLI for macOS..."
        cd /tmp
        local gcloud_archive="google-cloud-cli-${GCLOUD_CLI_VERSION}-darwin-${ARCH}.tar.gz"
        download_file "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${gcloud_archive}" "${gcloud_archive}"
        tar -xzf "${gcloud_archive}" -C "$HOME"
        "$HOME/google-cloud-sdk/install.sh" --quiet --path-update=true
        rm -f "${gcloud_archive}"
      fi
      ;;
    windows-bash)
      log_info "For Windows, please install Google Cloud CLI manually:"
      log_info "  Download: https://cloud.google.com/sdk/docs/install#windows"
      log_info "  Or use: (New-Object Net.WebClient).DownloadFile('https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe', 'GoogleCloudSDKInstaller.exe')"
      return 1
      ;;
    *)
      log_info "Downloading Google Cloud CLI for Linux..."
      cd /tmp

      local gcloud_arch="x86_64"
      if [[ "$ARCH" == "arm64" ]]; then
        gcloud_arch="arm"
      fi

      local gcloud_archive="google-cloud-cli-${GCLOUD_CLI_VERSION}-linux-${gcloud_arch}.tar.gz"
      download_file "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${gcloud_archive}" "${gcloud_archive}"

      # Extract to home directory
      tar -xzf "${gcloud_archive}" -C "$HOME"

      # Run install script
      "$HOME/google-cloud-sdk/install.sh" \
        --quiet \
        --path-update=true \
        --command-completion=true \
        --rc-path="${HOME}/.bashrc"

      # Add to current PATH
      export PATH="$HOME/google-cloud-sdk/bin:$PATH"

      rm -f "${gcloud_archive}"
      ;;
  esac

  # Verify installation
  if ! gcloud version &>/dev/null; then
    log_error "Google Cloud CLI installation verification failed"
    return 1
  fi

  local installed_ver
  installed_ver=$(get_tool_version gcloud-cli)
  log_success "Google Cloud CLI installed: ${installed_ver}"
}

install_keda() {
  log_info "Installing/upgrading KEDA ${KEDA_VERSION} in namespace '${KEDA_NAMESPACE}'..."

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install KEDA ${KEDA_VERSION} in namespace '${KEDA_NAMESPACE}'"
    return 0
  fi

  # Ensure helm is available
  if ! command_exists helm; then
    log_error "helm is required to install KEDA but is not available"
    return 1
  fi

  # Ensure kubectl is available
  if ! command_exists kubectl; then
    log_error "kubectl is required to verify KEDA but is not available"
    return 1
  fi

  # Add KEDA Helm repo
  log_info "Adding KEDA Helm repository..."
  if ! helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null; then
    log_warn "KEDA Helm repo may already exist, updating..."
  fi

  log_info "Updating Helm repositories..."
  helm repo update

  # Check if KEDA is already installed via Helm
  local keda_release_exists=false
  if helm status keda -n "$KEDA_NAMESPACE" &>/dev/null; then
    keda_release_exists=true
  fi

  if [[ "$keda_release_exists" == true ]]; then
    log_info "KEDA Helm release found — upgrading to ${KEDA_VERSION}..."
    if ! helm upgrade keda kedacore/keda \
      --namespace "$KEDA_NAMESPACE" \
      --version "$KEDA_VERSION" \
      --wait \
      --timeout 5m; then
      log_error "KEDA upgrade failed"
      return 1
    fi
    log_success "KEDA upgraded to ${KEDA_VERSION}"
  else
    # Check if KEDA resources exist but not managed by Helm
    if kubectl get namespace "$KEDA_NAMESPACE" &>/dev/null; then
      if kubectl get deployment keda-operator -n "$KEDA_NAMESPACE" &>/dev/null; then
        log_warn "KEDA resources exist in namespace '${KEDA_NAMESPACE}' but are not managed by Helm."
        log_warn "Attempting to adopt existing resources..."

        # Label and annotate existing resources for Helm adoption
        local resource_types=("serviceaccount" "deployment" "service")
        for kind in "${resource_types[@]}"; do
          local resources
          resources=$(kubectl get "$kind" -n "$KEDA_NAMESPACE" -o name 2>/dev/null | grep keda || true)
          for resource in $resources; do
            kubectl annotate "$resource" -n "$KEDA_NAMESPACE" \
              meta.helm.sh/release-name=keda \
              meta.helm.sh/release-namespace="$KEDA_NAMESPACE" \
              --overwrite 2>/dev/null || true
            kubectl label "$resource" -n "$KEDA_NAMESPACE" \
              app.kubernetes.io/managed-by=Helm \
              --overwrite 2>/dev/null || true
          done
        done

        # Handle cluster-scoped resources
        for kind in clusterrole clusterrolebinding; do
          local resources
          resources=$(kubectl get "$kind" -o name 2>/dev/null | grep keda || true)
          for resource in $resources; do
            kubectl annotate "$resource" \
              meta.helm.sh/release-name=keda \
              meta.helm.sh/release-namespace="$KEDA_NAMESPACE" \
              --overwrite 2>/dev/null || true
            kubectl label "$resource" \
              app.kubernetes.io/managed-by=Helm \
              --overwrite 2>/dev/null || true
          done
        done

        log_info "Resources annotated. Attempting Helm install..."
      fi
    fi

    log_info "Installing KEDA ${KEDA_VERSION} via Helm..."
    if ! helm install keda kedacore/keda \
      --namespace "$KEDA_NAMESPACE" \
      --create-namespace \
      --version "$KEDA_VERSION" \
      --wait \
      --timeout 5m; then
      log_error "KEDA installation failed"
      log_error ""
      log_error "If you see 'invalid ownership metadata' errors, existing KEDA resources"
      log_error "may need manual cleanup:"
      log_error "  kubectl delete namespace ${KEDA_NAMESPACE}"
      log_error "Then re-run this script."
      return 1
    fi
    log_success "KEDA ${KEDA_VERSION} installed"
  fi

  # Wait for KEDA deployments to be ready
  log_info "Waiting for KEDA deployments to be ready..."

  local keda_deployments=("keda-operator" "keda-operator-metrics-apiserver")
  local wait_timeout=120
  local all_ready=true

  for deploy in "${keda_deployments[@]}"; do
    log_info "  Waiting for ${deploy}..."
    if ! kubectl rollout status deployment/"$deploy" \
      -n "$KEDA_NAMESPACE" \
      --timeout="${wait_timeout}s" 2>/dev/null; then
      log_warn "  ${deploy} did not become ready within ${wait_timeout}s"
      all_ready=false
    else
      log_success "  ${deploy} is ready ✓"
    fi
  done

  if [[ "$all_ready" == false ]]; then
    log_warn "Some KEDA deployments are not ready. Check with:"
    log_warn "  kubectl get pods -n ${KEDA_NAMESPACE}"
    return 1
  fi

  # Verify installed version
  local installed_ver
  installed_ver=$(get_tool_version keda)
  if [[ "$installed_ver" == "0.0.0" ]]; then
    log_warn "Could not determine installed KEDA version, but deployments are running"
  else
    if version_gte "$installed_ver" "$MIN_KEDA_VERSION"; then
      log_success "KEDA version verified: v${installed_ver} (>= v${MIN_KEDA_VERSION} ✓)"
    else
      log_warn "KEDA version v${installed_ver} may not meet minimum v${MIN_KEDA_VERSION}"
    fi
  fi

  return 0
}

#######################################
# 9. Verify Helm Version (no auto-install)
#######################################
verify_helm_version() {
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would verify helm is between v${MIN_HELM_VERSION} and v${MAX_HELM_VERSION}"
    return 0
  fi

  if ! command_exists helm; then
    log_error "helm is NOT installed."
    log_error ""
    log_error "Please install helm (v${MIN_HELM_VERSION} - v${MAX_HELM_VERSION}) manually:"
    log_error ""
    log_error "  Linux/macOS/WSL:"
    log_error "    curl -fsSL https://get.helm.sh/helm-v3.18.1-linux-${ARCH}.tar.gz | tar -xz"
    log_error "    sudo mv linux-${ARCH}/helm /usr/local/bin/helm"
    log_error ""
    log_error "  macOS (Homebrew):"
    log_error "    brew install helm"
    log_error ""
    log_error "  Windows (Chocolatey):"
    log_error "    choco install kubernetes-helm"
    log_error ""
    log_error "  Official docs: https://helm.sh/docs/intro/install/"
    return 1
  fi

  local installed_ver
  installed_ver=$(get_tool_version helm)

  # Extract major.minor from installed version (e.g., "3.18" from "3.18.1")
  local installed_major_minor="${installed_ver%.*}"  # 3.18

  # Check if version is in acceptable range: 3.18.x or 3.19.x
  if [[ "$installed_major_minor" == "3.18" ]] || [[ "$installed_major_minor" == "3.19" ]]; then
    # Additionally check if it meets minimum patch version for 3.18.x
    if [[ "$installed_major_minor" == "3.18" ]] && ! version_gte "$installed_ver" "$MIN_HELM_VERSION"; then
      log_error "helm version v${installed_ver} is below minimum v${MIN_HELM_VERSION}"
      log_error ""
      log_error "Acceptable versions: v3.18.0 - v3.19.x"
      log_error "Please upgrade to at least v${MIN_HELM_VERSION}"
      return 1
    fi

    log_success "helm version verified: v${installed_ver} (acceptable range: v${MIN_HELM_VERSION} - v${MAX_HELM_VERSION} ✓)"
    return 0
  else
    log_error "helm version mismatch!"
    log_error "  Installed : v${installed_ver}"
    log_error "  Required  : v${MIN_HELM_VERSION} - v${MAX_HELM_VERSION}"
    log_error ""
    log_error "Please install an acceptable version (v3.18.x or v3.19.x) manually:"
    log_error ""
    log_error " Refer the README.md file for installation instructions Or helm official docs: https://helm.sh/docs/intro/install/"
    log_error ""
    log_error ""
    return 1
  fi
}

#######################################
# 10. Verification Functions
#######################################
verify_tool() {
  local tool="$1"
  local min_version="${2:-}"

  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi

  # Map tool names for command check
  local cmd="$tool"
  case "$tool" in
    aws-cli) cmd="aws" ;;
    azure-cli) cmd="az" ;;
    gcloud-cli) cmd="gcloud" ;;
  esac

  if ! command_exists "$cmd"; then
    log_error "$tool is not available after installation"
    return 1
  fi

  local version_output
  local current_version

  case "$tool" in
    kubectl)
      version_output="$("$tool" version --client 2>&1 | head -n1)"
      current_version=$(get_tool_version kubectl)
      ;;
    helm)
      version_output="$("$tool" version --short 2>&1 | head -n1)"
      current_version=$(get_tool_version helm)
      ;;
    aws-cli)
      version_output="$(aws --version 2>&1 | head -n1)"
      current_version=$(get_tool_version aws)
      ;;
    azure-cli)
      version_output="Azure CLI $(az version -o tsv 2>/dev/null | head -1)"
      current_version=$(get_tool_version az)
      ;;
    gcloud-cli)
      version_output="$(gcloud version 2>&1 | grep 'Google Cloud SDK' | head -n1)"
      current_version=$(get_tool_version gcloud-cli)
      ;;
    *)
      version_output="$("$cmd" --version 2>&1 | head -n1)"
      current_version=$(get_tool_version "$tool")
      ;;
  esac

  # Check minimum version if specified
  if [[ -n "$min_version" ]]; then
    if version_gte "$current_version" "$min_version"; then
      log_success "$tool is available: $version_output (>= v${min_version} ✓)"
    else
      log_warn "$tool version $current_version is below minimum $min_version"
      return 1
    fi
  else
    log_success "$tool is available: $version_output"
  fi

  return 0
}

#######################################
# 10. Cloud-Specific Configuration
#######################################
configure_cloud_tools() {
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would configure cloud tools for: $CLOUD_PROVIDER"
    return 0
  fi

  case "$CLOUD_PROVIDER" in
    aws)
      log_info "Configuring AWS environment..."
      if command_exists aws; then
        log_success "AWS CLI is available: $(aws --version)"
      fi
      ;;
    azure)
      log_info "Configuring Azure environment..."
      if command_exists az; then
        log_success "Azure CLI is available: $(az version -o tsv 2>/dev/null | head -n1)"
      fi
      ;;
    gcp)
      log_info "Configuring GCP environment..."
      if command_exists gcloud; then
        log_success "Google Cloud CLI is available: $(gcloud version 2>/dev/null | grep 'Google Cloud SDK' | head -n1)"
      fi
      ;;
  esac
}

#######################################
# 11. Capture pre-installation versions
#######################################
capture_pre_install_versions() {
  PRE_INSTALL_VERSIONS[kubectl]=$(get_tool_version kubectl)
  PRE_INSTALL_VERSIONS[helm]=$(get_tool_version helm)
  PRE_INSTALL_VERSIONS[aws-cli]=$(get_tool_version aws)
  PRE_INSTALL_VERSIONS[azure-cli]=$(get_tool_version az)
  PRE_INSTALL_VERSIONS[gcloud-cli]=$(get_tool_version gcloud-cli)
  PRE_INSTALL_VERSIONS[keda]=$(get_tool_version keda)
}

#######################################
# 12. Print Tool Status
#######################################
print_tool_status() {
  local tool="$1"
  local min_version="$2"
  local current_version
  current_version=$(get_tool_version "$tool")

  local status_icon="✗"
  if [[ "$current_version" != "0.0.0" ]] && version_gte "$current_version" "$min_version"; then
    # For helm, also verify it doesn't exceed max version
    if [[ "$tool" == "helm" ]]; then
      if version_gte "$MAX_HELM_VERSION" "$current_version"; then
        status_icon="✓"
      fi
    else
      status_icon="✓"
    fi
  fi

  printf "│  %-12s %-8s (min: %-8s) %s │\n" "$tool:" "$current_version" "$min_version" "$status_icon"
}

#######################################
# 13. Print Summary
#######################################
print_summary() {
  echo ""
  echo "┌───────────────────────────────────────────────────────────┐"
  echo "│  CI360 Marketing AI — Prerequisites Setup                 │"
  echo "│  Cloud Provider: ${CLOUD_PROVIDER}                                       │"
  echo "├───────────────────────────────────────────────────────────┤"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Running in DRY-RUN mode - no changes will be made"
    echo ""
    echo "Would install/verify:"
    echo "  - kubectl   ${KUBECTL_VERSION}           (min: v${MIN_KUBECTL_VERSION})"
    echo "  - helm      v${HELM_REQUIRED_VERSION}    (verify only — exact match required)"
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      echo "  - aws-cli   ${AWS_CLI_VERSION}          (min: ${MIN_AWS_CLI_VERSION})"
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      echo "  - azure-cli ${AZURE_CLI_VERSION}        (min: ${MIN_AZURE_CLI_VERSION})"
    elif [[ "$CLOUD_PROVIDER" == "gcp" ]]; then
      echo "  - gcloud-cli ${GCLOUD_CLI_VERSION}      (min: ${MIN_GCLOUD_CLI_VERSION})"
    fi
  else
    echo "│  Minimum Required Versions:                              │"
    printf "│  %-12s >= v%-41s │\n" "kubectl:" "${MIN_KUBECTL_VERSION}"
    printf "│  %-12s v%-5s - v%-32s │\n" "helm:" "${MIN_HELM_VERSION}" "${MAX_HELM_VERSION}"
    printf "│  %-12s >= v%-41s │\n" "keda:" "${MIN_KEDA_VERSION}"
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      printf "│  %-12s >= %-42s │\n" "aws-cli:" "${MIN_AWS_CLI_VERSION}"
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      printf "│  %-12s >= %-42s │\n" "azure-cli:" "${MIN_AZURE_CLI_VERSION}"
    elif [[ "$CLOUD_PROVIDER" == "gcp" ]]; then
      printf "│  %-12s >= %-42s │\n" "gcloud-cli:" "${MIN_GCLOUD_CLI_VERSION}"
    fi
    echo "├───────────────────────────────────────────────────────────┤"
    echo "│  Current Tool Status:                                     │"
    print_tool_status "kubectl" "$MIN_KUBECTL_VERSION"
    print_tool_status "helm" "$MIN_HELM_VERSION"
    print_tool_status "keda" "$MIN_KEDA_VERSION"
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      print_tool_status "aws-cli" "$MIN_AWS_CLI_VERSION"
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      print_tool_status "azure-cli" "$MIN_AZURE_CLI_VERSION"
    elif [[ "$CLOUD_PROVIDER" == "gcp" ]]; then
      print_tool_status "gcloud-cli" "$MIN_GCLOUD_CLI_VERSION"
    fi

    # Compatibility check
    local tools_to_check=("kubectl" "helm" "keda")
    local min_versions=("$MIN_KUBECTL_VERSION" "$MIN_HELM_VERSION" "$MIN_KEDA_VERSION")
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      tools_to_check+=("aws-cli")
      min_versions+=("$MIN_AWS_CLI_VERSION")
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      tools_to_check+=("azure-cli")
      min_versions+=("$MIN_AZURE_CLI_VERSION")
    elif [[ "$CLOUD_PROVIDER" == "gcp" ]]; then
      tools_to_check+=("gcloud-cli")
      min_versions+=("$MIN_GCLOUD_CLI_VERSION")
    fi

    local all_good=true
    for i in "${!tools_to_check[@]}"; do
      local ver
      ver=$(get_tool_version "${tools_to_check[$i]}")
      if [[ "$ver" == "0.0.0" ]] || ! version_gte "$ver" "${min_versions[$i]}"; then
        all_good=false
        break
      fi
      # For helm, also check it doesn't exceed the max version
      if [[ "${tools_to_check[$i]}" == "helm" ]] && ! version_gte "$MAX_HELM_VERSION" "$ver"; then
        all_good=false
        break
      fi
    done

    echo "├───────────────────────────────────────────────────────────┤"
    if [[ "$all_good" == true ]]; then
      echo "│  Status: ALL TOOLS MEET MINIMUM VERSIONS ✓                │"
    else
      echo "│  Status: SOME TOOLS NEED INSTALLATION/UPGRADE/DOWNGRADE   │"
    fi
  fi

  echo "└───────────────────────────────────────────────────────────┘"
  echo ""
}

#######################################
# 14. Usage / Help
#######################################
usage() {
  cat <<EOF
Usage: $(basename "$0") --cloud <aws|azure|gcp> [OPTIONS]

CloudShell Environment Bootstrap Script for CI360 Marketing AI (MAI)

Required:
  --cloud <provider>          Cloud provider: aws, azure, or gcp

Options:
  -h, --help                  Show this help message and exit
  -q, --quiet                 Suppress non-essential output (useful for CI/CD)
  -f, --force                 Force reinstall of all tools even if already installed
  -d, --dry-run               Show what would be installed without making changes
  --skip-autocomplete         Skip shell autocomplete configuration
  --install-dir <path>        Custom installation directory (default: ~/.local/bin)
  --tools <list>              Install only specific tools (comma-separated)
                              Available: kubectl,helm,aws-cli,azure-cli,gcloud-cli
  --retries <n>               Number of retry attempts (default: 3)
  --retry-delay <s>           Delay between retries in seconds (default: 3)
  --kubectl-version <version> Specific kubectl version (default: ${KUBECTL_VERSION})
  --helm-version <version>    Specific helm version — NOTE: only v3.18.x and v3.19.x are supported.
                              Auto-install is disabled; script will verify only.

Minimum Required Versions:
  kubectl:    >= v${MIN_KUBECTL_VERSION}
  helm:       >= v${MIN_HELM_VERSION} (and <= v${MAX_HELM_VERSION})
              Acceptable: v3.18.x or v3.19.x (no auto-install)
  keda:       >= v${MIN_KEDA_VERSION} (installed to cluster)
  aws-cli:    >= ${MIN_AWS_CLI_VERSION} (AWS only)
  azure-cli:  >= ${MIN_AZURE_CLI_VERSION} (Azure only)
  gcloud-cli: >= ${MIN_GCLOUD_CLI_VERSION} (GCP only)

Pinned Installation Versions:
  kubectl:    ${KUBECTL_VERSION}
  helm:       v${MIN_HELM_VERSION} - v${MAX_HELM_VERSION} (verify only — install manually if outside range)
  keda:       ${KEDA_VERSION} (Helm chart installed to ${KEDA_NAMESPACE} namespace)
  aws-cli:    ${AWS_CLI_VERSION}
  azure-cli:  ${AZURE_CLI_VERSION}
  gcloud-cli: ${GCLOUD_CLI_VERSION}

Examples:
  # Install all tools for AWS
  $(basename "$0") --cloud aws

  # Install all tools for Azure
  $(basename "$0") --cloud azure

  # Install all tools for GCP
  $(basename "$0") --cloud gcp

  # Install only kubectl and helm for AWS
  $(basename "$0") --cloud aws --tools kubectl,helm

  # Force reinstall all tools
  $(basename "$0") --cloud aws --force

  # Dry run to see what would be installed
  $(basename "$0") --cloud azure --dry-run

  # Install to custom directory
  $(basename "$0") --cloud aws --install-dir /opt/bin

  # Skip autocomplete
  $(basename "$0") --cloud aws --skip-autocomplete

  # Quiet mode for CI/CD pipelines
  $(basename "$0") --cloud azure --quiet

  # Install specific kubectl version (helm will be verified only)
  $(basename "$0") --cloud aws --kubectl-version v1.32.0

Supported Cloud Environments:
  - AWS CloudShell (Amazon Linux / yum)
  - Azure Cloud Shell (Ubuntu / apt)
  - GCP Cloud Shell (Debian / apt)

Exit Codes:
  0    Success
  1    General error
  2    Invalid arguments
  3    Missing dependencies
  4    Installation failed

EOF
  exit 0
}

#######################################
# 15. Parse Arguments
#######################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        ;;
      -q|--quiet)
        QUIET_MODE=true
        shift
        ;;
      -f|--force)
        FORCE_REINSTALL=true
        shift
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      --cloud)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --cloud requires a provider argument (aws, azure, or gcp)"
          exit 2
        fi
        CLOUD_PROVIDER="$2"
        if [[ "$CLOUD_PROVIDER" != "aws" && "$CLOUD_PROVIDER" != "azure" && "$CLOUD_PROVIDER" != "gcp" ]]; then
          echo "[ERROR] Invalid cloud provider: $CLOUD_PROVIDER. Must be 'aws', 'azure', or 'gcp'"
          exit 2
        fi
        shift 2
        ;;
      --skip-autocomplete)
        SKIP_AUTOCOMPLETE=true
        shift
        ;;
      --install-dir)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --install-dir requires a path argument"
          exit 2
        fi
        INSTALL_DIR="$2"
        shift 2
        ;;
      --tools)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --tools requires a comma-separated list"
          exit 2
        fi
        SELECTED_TOOLS="$2"
        shift 2
        ;;
      --retries)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --retries requires a number"
          exit 2
        fi
        MAX_RETRIES="$2"
        shift 2
        ;;
      --retry-delay)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --retry-delay requires a number"
          exit 2
        fi
        RETRY_DELAY="$2"
        shift 2
        ;;
      --kubectl-version)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --kubectl-version requires a version string"
          exit 2
        fi
        KUBECTL_VERSION="$2"
        shift 2
        ;;
      --helm-version)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --helm-version requires a version string"
          exit 2
        fi
        # Strip leading 'v' for validation
        local helm_input="${2#v}"
        local helm_major_minor="${helm_input%.*}"
        if [[ "$helm_major_minor" != "3.18" && "$helm_major_minor" != "3.19" ]]; then
          echo "[ERROR] Invalid helm version: $2"
          echo "[ERROR] Only v3.18.x or v3.19.x are supported (acceptable range: v${MIN_HELM_VERSION} - v${MAX_HELM_VERSION})"
          echo "[ERROR] Examples: --helm-version v3.18.1, --helm-version v3.19.0"
          exit 2
        fi
        HELM_VERSION="$helm_input"
        shift 2
        ;;
    esac
  done

  # Validate required arguments
  if [[ -z "$CLOUD_PROVIDER" ]]; then
    echo "[ERROR] --cloud is required. Please specify 'aws', 'azure', or 'gcp'"
    echo "Use --help for usage information"
    exit 2
  fi
}

#######################################
# 16. Main Execution
#######################################
main() {
  parse_args "$@"

  # Detect platform and architecture
  PLATFORM=$(detect_platform)
  ARCH=$(detect_arch)

  # Ensure install directory exists and is in PATH
  mkdir -p "$INSTALL_DIR"
  if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    export PATH="${INSTALL_DIR}:${PATH}"
  fi

  # Capture pre-install state
  capture_pre_install_versions

  # Print summary
  print_summary

  log_info "Platform: ${PLATFORM} | Arch: ${ARCH} | Cloud: ${CLOUD_PROVIDER}"
  echo "|----------------------------------------------------------------|"
  log_info "Install directory: ${INSTALL_DIR}"
  log_info "Starting environment validation and tool installation..."
  echo ""

  # Install kubectl
  if should_install kubectl "$MIN_KUBECTL_VERSION"; then
    if install_kubectl; then
      track_install "kubectl" "installed" "new/upgraded"
    else
      track_install "kubectl" "failed" "installation error"
    fi
  else
    track_install "kubectl" "skipped" "meets minimum"
    log_info "kubectl already meets minimum version (use --force to reinstall)"
    echo ""
  fi
  verify_tool kubectl "$MIN_KUBECTL_VERSION" || true

  # Verify helm (no auto-install)
  if [[ -z "$SELECTED_TOOLS" ]] || [[ ",$SELECTED_TOOLS," == *",helm,"* ]]; then
    if verify_helm_version; then
      track_install "helm" "skipped" "meets requirement"
    else
      track_install "helm" "failed" "version check failed"
    fi
  fi

  # Install/verify KEDA
    if [[ -z "$SELECTED_TOOLS" ]] || [[ ",$SELECTED_TOOLS," == *",keda,"* ]]; then
    log_info "Checking KEDA installation in namespace '${KEDA_NAMESPACE}'..."
    local keda_ver
    keda_ver=$(get_tool_version keda)
    if [[ "$DRY_RUN" == true ]]; then
      log_dry_run "Would verify/install KEDA >= v${MIN_KEDA_VERSION} in namespace '${KEDA_NAMESPACE}'"
      track_install "keda" "skipped" "dry-run"
    elif [[ "$keda_ver" == "0.0.0" ]]; then
      log_warn "KEDA is not installed in namespace '${KEDA_NAMESPACE}'"
      log_info "Attempting to install KEDA ${KEDA_VERSION}..."
      if install_keda; then
        track_install "keda" "installed" "new install (v${KEDA_VERSION})"
      else
        track_install "keda" "failed" "installation error"
      fi
    elif version_gte "$keda_ver" "$MIN_KEDA_VERSION"; then
      if [[ "$FORCE_REINSTALL" == true ]]; then
        log_info "Force reinstall requested for KEDA..."
        if install_keda; then
          track_install "keda" "installed" "force upgraded to v${KEDA_VERSION}"
        else
          track_install "keda" "failed" "upgrade error"
        fi
      else
        log_success "KEDA version verified: v${keda_ver} (>= v${MIN_KEDA_VERSION} ✓)"
        track_install "keda" "skipped" "meets minimum (v${keda_ver})"
      fi
    else
      log_warn "KEDA version v${keda_ver} is below minimum v${MIN_KEDA_VERSION}"
      log_info "Attempting to upgrade KEDA to ${KEDA_VERSION}..."
      if install_keda; then
        track_install "keda" "installed" "upgraded from v${keda_ver} to v${KEDA_VERSION}"
      else
        track_install "keda" "failed" "upgrade from v${keda_ver} failed"
      fi
    fi
  fi

  # Install cloud-specific CLI
  case "$CLOUD_PROVIDER" in
    aws)
      if should_install aws-cli "$MIN_AWS_CLI_VERSION"; then
        if install_aws_cli; then
          track_install "aws-cli" "installed" "new/upgraded"
        else
          track_install "aws-cli" "failed" "installation error"
        fi
      else
        track_install "aws-cli" "skipped" "meets minimum"
        log_info "AWS CLI already meets minimum version (use --force to reinstall)"
      fi
      verify_tool aws-cli "$MIN_AWS_CLI_VERSION" || true
      ;;
    azure)
      if should_install azure-cli "$MIN_AZURE_CLI_VERSION"; then
        if install_azure_cli; then
          track_install "azure-cli" "installed" "new/upgraded"
        else
          local current_ver
          current_ver=$(get_tool_version azure-cli)

          if is_azure_cloudshell && [[ "$current_ver" != "0.0.0" ]]; then
            track_install "azure-cli" "skipped" "CloudShell managed (v${current_ver})"

            if ! version_gte "$current_ver" "$MIN_AZURE_CLI_VERSION"; then
              log_warn "Azure CLI v${current_ver} is below minimum v${MIN_AZURE_CLI_VERSION}"
              log_warn "In Azure Cloud Shell, Azure CLI is managed by Microsoft and will be updated in future releases."
            fi
          else
            track_install "azure-cli" "failed" "installation error"
          fi
        fi
      else
        track_install "azure-cli" "skipped" "meets minimum"
        log_info "Azure CLI already meets minimum version (use --force to reinstall)"
      fi
      verify_tool azure-cli "$MIN_AZURE_CLI_VERSION" || true
      ;;
    gcp)
      if should_install gcloud-cli "$MIN_GCLOUD_CLI_VERSION"; then
        if install_gcloud_cli; then
          track_install "gcloud-cli" "installed" "new/upgraded"
        else
          local current_ver
          current_ver=$(get_tool_version gcloud-cli)

          if is_gcp_cloudshell && [[ "$current_ver" != "0.0.0" ]]; then
            track_install "gcloud-cli" "skipped" "CloudShell managed (v${current_ver})"

            if ! version_gte "$current_ver" "$MIN_GCLOUD_CLI_VERSION"; then
              log_warn "Google Cloud CLI v${current_ver} is below minimum v${MIN_GCLOUD_CLI_VERSION}"
              log_warn "In GCP Cloud Shell, gcloud CLI is managed by Google and will be updated in future releases."
            fi
          else
            track_install "gcloud-cli" "failed" "installation error"
          fi
        fi
      else
        track_install "gcloud-cli" "skipped" "meets minimum"
        log_info "Google Cloud CLI already meets minimum version (use --force to reinstall)"
        echo ""
      fi
      verify_tool gcloud-cli "$MIN_GCLOUD_CLI_VERSION" || true
      ;;
  esac

  # Configure cloud tools
  configure_cloud_tools

  # Final status
  echo ""
  echo "┌───────────────────────────────────────────────────────────┐"
  echo "│  Installation Summary                                     │"
  echo "├───────────────────────────────────────────────────────────┤"

  local has_failures=false
  local has_cli_warning=false

  for tool in "${!INSTALL_STATUS[@]}"; do
    local status_entry="${INSTALL_STATUS[$tool]}"
    local status="${status_entry%%|*}"
    local detail="${status_entry#*|}"

    local icon="?"
    case "$status" in
      installed) icon="✓" ;;
      skipped)   icon="–" ;;
      failed)    icon="✗"; has_failures=true ;;
    esac

    printf "│  [%s] %-12s %s\n" "$icon" "$tool" "$detail"
  done

  # Check for cloud CLI version warnings
  if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
    local azure_ver
    azure_ver=$(get_tool_version azure-cli)
    if [[ "$azure_ver" != "0.0.0" ]] && ! version_gte "$azure_ver" "$MIN_AZURE_CLI_VERSION"; then
      has_cli_warning=true
    fi
  elif [[ "$CLOUD_PROVIDER" == "gcp" ]]; then
    local gcloud_ver
    gcloud_ver=$(get_tool_version gcloud-cli)
    if [[ "$gcloud_ver" != "0.0.0" ]] && ! version_gte "$gcloud_ver" "$MIN_GCLOUD_CLI_VERSION"; then
      has_cli_warning=true
    fi
  fi

  echo "├───────────────────────────────────────────────────────────┤"

  if [[ "$has_failures" == true ]]; then
    echo "│  Result: SOME REQUIREMENTS FAILED                         │"
    echo "└───────────────────────────────────────────────────────────┘"
    exit 4
  elif [[ "$has_cli_warning" == true ]]; then
    echo "│  Result: COMPLETED WITH WARNINGS                          │"
    echo "└───────────────────────────────────────────────────────────┘"
    exit 0
  else
    echo "│  Result: ALL TOOLS READY ✓                                │"
    echo "└───────────────────────────────────────────────────────────┘"
    exit 0
  fi
}

# Execute main function
main "$@"