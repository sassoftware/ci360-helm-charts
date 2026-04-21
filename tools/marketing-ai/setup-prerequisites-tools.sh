#!/usr/bin/env bash
###############################################################################
# # Setup Prerequisites Tools

# ## Synopsis

# ```bash
# ./setup-prerequisites-tools.sh [OPTIONS]
# ```

# ## Description

# CloudShell Environment Bootstrap Script for CI360 Marketing AI (MAI). Automatically installs and configures required CLI tools.

# ## Options

# | Option | Description |
# |--------|-------------|
# | `-h, --help` | Show help message and exit |
# | `-q, --quiet` | Suppress non-essential output (useful for CI/CD) |
# | `-f, --force` | Force reinstall of all tools even if already installed |
# | `-d, --dry-run` | Show what would be installed without making changes |
# | `--cloud <provider>` | Cloud provider: aws, azure (required) |
# | `--skip-autocomplete` | Skip shell autocomplete configuration |
# | `--install-dir <path>` | Custom installation directory (default: `~/.local/bin`) |
# | `--tools <list>` | Install only specific tools (comma-separated) |
# | `--retries <n>` | Number of retry attempts (default: 3) |
# | `--retry-delay <s>` | Delay between retries in seconds (default: 3) |
# | `--kubectl-version <v>` | Specific kubectl version to install (default: v1.33.0) |
# | `--helm-version <v>` | Specific helm version to install (default: v3.18.XX or v3.19.XX) |

# ## Examples

# ```bash
# # Install all tools for AWS
# ./setup-prerequisites-tools.sh --cloud aws

# # Install all tools for Azure
# ./setup-prerequisites-tools.sh --cloud azure

# # Install only kubectl and helm
# ./setup-prerequisites-tools.sh --cloud aws --tools kubectl,helm

# # Force reinstall all tools
# ./setup-prerequisites-tools.sh --cloud aws --force

# # Dry run to see what would be installed
# ./setup-prerequisites-tools.sh --cloud aws --dry-run

# # Install to custom directory
# ./setup-prerequisites-tools.sh --cloud aws --install-dir /opt/bin

# # Skip autocomplete
# ./setup-prerequisites-tools.sh --cloud aws --skip-autocomplete

# # Quiet mode for CI/CD pipelines
# ./setup-prerequisites-tools.sh --cloud azure --quiet

# # Increase retries for slow connections
# ./setup-prerequisites-tools.sh --cloud aws --retries 5 --retry-delay 10
# ```

# ## Exit Codes

# | Code | Description |
# |------|-------------|
# | 0 | Success |
# | 1 | General error |
# | 2 | Invalid arguments |
# | 3 | Missing dependencies |
# | 4 | Installation failed |

# ## Minimum Required Versions

# | Tool | Minimum Version |
# |------|-----------------|
# | kubectl | v1.27.0 |
# | helm | v3.18.1 |
# | aws-cli | 2.18.1 (AWS only) |
# | azure-cli | 2.83.0 (Azure only) |
###############################################################################

# Self-heal line endings if running with CRLF
if [[ "$(file "$0" 2>/dev/null)" == *"CRLF"* ]] || [[ "$(head -1 "$0" 2>/dev/null)" == *$'\r' ]]; then
  echo "[WARN] Detected Windows line endings (CRLF). Converting to Unix (LF)..."
  if command -v dos2unix &>/dev/null; then
    dos2unix "$0" 2>/dev/null || sed -i 's/\r$//' "$0"
  else
    sed -i 's/\r$//' "$0"
  fi
  echo "[INFO] Line endings fixed. Re-executing script..."
  exec bash "$0" "$@"
fi

set -euo pipefail

#######################################
# Detect if running in Cloud Shell
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

is_any_cloudshell() {
  is_azure_cloudshell || is_aws_cloudshell
}

#######################################
# Platform Detection
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
  elif [[ "$os_type" == "windows" ]] || [[ -n "${MSYSTEM:-}" ]]; then
    # Git Bash, MSYS2, or similar on Windows
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

PLATFORM=$(detect_platform)

#######################################
# Detect Architecture
#######################################
get_arch() {
  local arch
  arch="$(uname -m 2>/dev/null || echo 'x86_64')"
  
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;  # default fallback
  esac
}

ARCH=$(get_arch)

#######################################
# Global Configuration
#######################################
MAX_RETRIES=3
RETRY_DELAY=3
INSTALL_DIR="${HOME}/.local/bin"

# Cloud provider (must be specified via --cloud)
CLOUD_PROVIDER=""

# Minimum required versions
MIN_KUBECTL_VERSION="1.27.0"
MIN_HELM_VERSION="3.18.0"
MAX_HELM_VERSION="3.19.999"
MIN_AWS_CLI_VERSION="2.18.1"
MIN_AZURE_CLI_VERSION="2.83.0"
MIN_KEDA_VERSION="2.19.0"

# Pinned versions for installation
KUBECTL_VERSION="v1.33.0"
HELM_REQUIRED_VERSION="3.18.1"
HELM_VERSION="${HELM_REQUIRED_VERSION}"
AWS_CLI_VERSION="2.18.1"
AZURE_CLI_VERSION="2.83.0"
KEDA_VERSION="2.19.0"
KEDA_NAMESPACE="keda"

# Default options
SKIP_AUTOCOMPLETE=false
FORCE_REINSTALL=false
QUIET_MODE=false
DRY_RUN=false
TOOLS_ONLY=""

# Track what was installed during this run
declare -A INSTALLED_THIS_RUN=()
declare -A SKIPPED_THIS_RUN=()
declare -A FAILED_THIS_RUN=()
declare -A PRE_INSTALL_VERSIONS=()

# Track mandatory failures
MANDATORY_FAILED=false

#######################################
# Logging Helpers
#######################################
log_info() {
  [[ "$QUIET_MODE" == true ]] && return
  echo "[INFO]  $*"
}

log_warn()    { echo "[WARN]  $*" >&2; }
log_error()   { echo "[ERROR] $*" >&2; }

log_success() {
  [[ "$QUIET_MODE" == true ]] && return
  echo "[SUCCESS] $*"
}

log_dry_run() {
  echo "[DRY-RUN] $*"
}

#######################################
# Version Comparison
#######################################
version_gte() {
  local ver1="$1"
  local ver2="$2"
  
  # Remove 'v' prefix if present
  ver1="${ver1#v}"
  ver2="${ver2#v}"
  
  # Use sort -V for version comparison
  if [[ "$(printf '%s\n%s' "$ver2" "$ver1" | sort -V | head -n1)" == "$ver2" ]]; then
    return 0  # ver1 >= ver2
  else
    return 1  # ver1 < ver2
  fi
}

#######################################
# Extract version number from tool output
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
      # Pattern 1: "v3.18.1+g..." (helm version --short)
      version=$(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^v//')
      
      # Pattern 2: version.BuildInfo{Version:"v3.18"...} (helm version)
      # IMPORTANT: Match Version: field specifically, NOT GoVersion:
      if [[ -z "$version" || "$version" == "0.0.0" ]]; then
        # Use sed to extract only from Version: field (before GoVersion appears)
        version=$(helm version 2>/dev/null | sed -n 's/.*Version:"\(v\?[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?\)".*/\1/p' | sed 's/^v//' | head -1)
      fi
      
      # Pattern 3: Try --client flag
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
      # Try JSON output first (more reliable)
      version=$(az version -o json 2>/dev/null | grep -oE '"azure-cli": "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      
      # Fallback to TSV output
      if [[ -z "$version" || "$version" == "0.0.0" ]]; then
        version=$(az version -o tsv 2>/dev/null | head -1 | awk '{print $1}')
      fi
      
      version="${version:-0.0.0}"
      ;;
    keda)
      # Check if KEDA is installed in the cluster
      if ! command_exists kubectl; then
        version="0.0.0"
      elif kubectl get namespace "$KEDA_NAMESPACE" &>/dev/null; then
        # Try to get KEDA operator version from deployment
        version=$(kubectl get deployment keda-operator -n "$KEDA_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        
        # Fallback: check keda-operator-metrics-apiserver
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
# Command Check
#######################################
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

#######################################
# Detect Package Manager
#######################################
detect_pkg_manager() {
  if command_exists apt-get; then
    echo "apt"
  elif command_exists yum; then
    echo "yum"
  elif command_exists apk; then
    echo "apk"
  elif command_exists brew; then
    echo "brew"
  elif command_exists choco; then
    echo "choco"
  else
    echo "none"
  fi
}

#######################################
# Download Helper (cross-platform)
#######################################
download_file() {
  local url="$1"
  local output="$2"
  
  if command_exists curl; then
    retry curl -fsSL "$url" -o "$output"
  elif command_exists wget; then
    retry wget -q "$url" -O "$output"
  else
    log_error "Neither curl nor wget is available. Cannot download files."
    return 1
  fi
}

#######################################
# Retry Wrapper
#######################################
retry() {
  local n=1
  local cmd="$*"
  until [ $n -gt "$MAX_RETRIES" ]; do
    if eval "$cmd"; then
      return 0
    fi
    log_warn "Attempt $n failed. Retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
    n=$((n + 1))
  done
  log_error "Command failed after ${MAX_RETRIES} attempts: $cmd"
  return 1
}

#######################################
# Install KEDA (Kubernetes Event Driven Autoscaler)
#######################################
install_keda() {
  log_info "Installing KEDA ${KEDA_VERSION} (minimum: ${MIN_KEDA_VERSION})..."
  
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install KEDA ${KEDA_VERSION} to namespace ${KEDA_NAMESPACE}"
    return 0
  fi
  
  # Verify kubectl and helm are available
  if ! command_exists kubectl; then
    log_error "kubectl is required to install KEDA"
    return 1
  fi
  
  if ! command_exists helm; then
    log_error "helm is required to install KEDA"
    return 1
  fi
  
  # Check cluster connectivity
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Please configure kubectl first."
    return 1
  fi
  
  # Add KEDA Helm repository
  log_info "Adding KEDA Helm repository..."
  if ! helm repo add kedacore https://kedacore.github.io/charts &>/dev/null; then
    log_warn "KEDA repo already exists, updating..."
  fi
  
  retry helm repo update
  
  # Create namespace if it doesn't exist
  if ! kubectl get namespace "$KEDA_NAMESPACE" &>/dev/null; then
    log_info "Creating namespace: ${KEDA_NAMESPACE}"
    kubectl create namespace "$KEDA_NAMESPACE"
  fi
  
  # Install or upgrade KEDA
  log_info "Installing KEDA ${KEDA_VERSION} via Helm..."
  if helm list -n "$KEDA_NAMESPACE" 2>/dev/null | grep -q "^keda"; then
    log_info "KEDA already installed, upgrading..."
    retry helm upgrade keda kedacore/keda \
      --namespace "$KEDA_NAMESPACE" \
      --version "$KEDA_VERSION" \
      --wait \
      --timeout 5m
  else
    retry helm install keda kedacore/keda \
      --namespace "$KEDA_NAMESPACE" \
      --version "$KEDA_VERSION" \
      --wait \
      --timeout 5m
  fi
  
  # Wait for KEDA operator to be ready
  log_info "Waiting for KEDA operator to be ready..."
  if ! kubectl wait --for=condition=available \
    --timeout=180s \
    deployment/keda-operator \
    deployment/keda-operator-metrics-apiserver \
    -n "$KEDA_NAMESPACE" 2>/dev/null; then
    log_warn "KEDA operator deployment wait timed out, checking manually..."
    
    # Check if pods are running
    local ready_pods
    ready_pods=$(kubectl get pods -n "$KEDA_NAMESPACE" --field-selector=status.phase=Running 2>/dev/null | grep -c "keda-operator" || echo "0")
    
    if [[ "$ready_pods" -lt 2 ]]; then
      log_error "KEDA operator pods are not running"
      kubectl get pods -n "$KEDA_NAMESPACE"
      return 1
    fi
  fi
  
  log_success "KEDA ${KEDA_VERSION} installed successfully"
  return 0
}

#######################################
# Install kubectl (cross-platform)
#######################################
install_kubectl() {
  log_info "Installing kubectl ${KUBECTL_VERSION} (minimum: v${MIN_KUBECTL_VERSION})..."
  
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install kubectl ${KUBECTL_VERSION} to ${INSTALL_DIR}/kubectl"
    return 0
  fi
  
  # Validate requested version meets minimum
  local requested_ver="${KUBECTL_VERSION#v}"
  if ! version_gte "$requested_ver" "$MIN_KUBECTL_VERSION"; then
    log_error "Requested kubectl version ${KUBECTL_VERSION} is below minimum v${MIN_KUBECTL_VERSION}"
    return 1
  fi
  
  local os_name="linux"
  case "$PLATFORM" in
    macos) os_name="darwin" ;;
    windows-bash|wsl) os_name="linux" ;;
    *) os_name="linux" ;;
  esac
  
  local download_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${os_name}/${ARCH}/kubectl"
  local kubectl_bin="${INSTALL_DIR}/kubectl"
  
  # Windows needs .exe extension
  if [[ "$PLATFORM" == "windows-bash" ]]; then
    kubectl_bin="${kubectl_bin}.exe"
    download_url="${download_url}.exe"
  fi
  
  log_info "Downloading kubectl ${KUBECTL_VERSION} from ${download_url}..."
  download_file "$download_url" "$kubectl_bin"
  
  chmod +x "$kubectl_bin" 2>/dev/null || true
  
  # Verify the binary works
  if ! "$kubectl_bin" version --client &>/dev/null; then
    log_error "kubectl binary verification failed"
    return 1
  fi
  
  log_success "kubectl ${KUBECTL_VERSION} installed to ${kubectl_bin}"
}

#######################################
# Verify Helm Version (no auto-install)
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
    log_error "  Linux/macOS/WSL (v3.18.1):"
    log_error "    curl -fsSL https://get.helm.sh/helm-v3.18.1-linux-${ARCH}.tar.gz | tar -xz"
    log_error "    sudo mv linux-${ARCH}/helm /usr/local/bin/helm"
    log_error ""
    log_error "  Linux/macOS/WSL (v3.19.0):"
    log_error "    curl -fsSL https://get.helm.sh/helm-v3.19.0-linux-${ARCH}.tar.gz | tar -xz"
    log_error "    sudo mv linux-${ARCH}/helm /usr/local/bin/helm"
    log_error ""
    log_error "  macOS (Homebrew):"
    log_error "    brew install helm"
    log_error ""
    log_error "  Official docs: https://helm.sh/docs/intro/install/"
    return 1
  fi
}

#######################################
# Verify KEDA Installation
#######################################
verify_keda() {
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would verify KEDA >= v${MIN_KEDA_VERSION}"
    return 0
  fi

  if ! command_exists kubectl; then
    log_error "kubectl is required to verify KEDA"
    return 1
  fi

  # Check if KEDA namespace exists
  if ! kubectl get namespace "$KEDA_NAMESPACE" &>/dev/null; then
    log_error "KEDA namespace '${KEDA_NAMESPACE}' not found"
    return 1
  fi

  local installed_ver
  installed_ver=$(get_tool_version keda)
  
  if [[ "$installed_ver" == "0.0.0" ]]; then
    log_error "KEDA version could not be determined"
    return 1
  fi

  # Check version
  if ! version_gte "$installed_ver" "$MIN_KEDA_VERSION"; then
    log_warn "KEDA version ${installed_ver} is below minimum ${MIN_KEDA_VERSION}"
    return 1
  fi

  # Check if KEDA operator is running
  local operator_status
  operator_status=$(kubectl get deployment keda-operator -n "$KEDA_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
  
  if [[ "$operator_status" != "True" ]]; then
    log_error "KEDA operator is not available"
    kubectl get pods -n "$KEDA_NAMESPACE"
    return 1
  fi

  log_success "KEDA is available: v${installed_ver} (>= v${MIN_KEDA_VERSION} ✓)"
  return 0
}

#######################################
# Install AWS CLI (cross-platform)
#######################################
install_aws_cli() {
  log_info "Installing AWS CLI ${AWS_CLI_VERSION} (minimum: ${MIN_AWS_CLI_VERSION})..."
  
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install AWS CLI ${AWS_CLI_VERSION}"
    return 0
  fi
  
  case "$PLATFORM" in
    macos)
      log_info "Downloading AWS CLI for macOS..."
      cd /tmp
      download_file "https://awscli.amazonaws.com/AWSCLIV2.pkg" "AWSCLIV2.pkg"
      sudo installer -pkg AWSCLIV2.pkg -target /
      rm -f AWSCLIV2.pkg
      ;;
    windows-bash)
      log_info "For Windows, please install AWS CLI manually:"
      log_info "  Download: https://awscli.amazonaws.com/AWSCLIV2.msi"
      log_info "  Or use: msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi"
      return 1
      ;;
    *)
      log_info "Downloading AWS CLI v2 for Linux..."
      cd /tmp
      download_file "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" "awscliv2.zip"
      
      # Install unzip if needed
      if ! command_exists unzip; then
        case "$PKG_MANAGER" in
          apt) sudo apt-get install -y -qq unzip ;;
          yum) sudo yum install -y -q unzip ;;
          *) log_error "unzip not available"; return 1 ;;
        esac
      fi
      
      unzip -q -o awscliv2.zip
      
      # Install or update
      if [[ -d /usr/local/aws-cli ]]; then
        log_info "Updating existing AWS CLI installation..."
        sudo ./aws/install --update
      else
        log_info "Installing AWS CLI..."
        sudo ./aws/install
      fi
      
      rm -rf aws awscliv2.zip
      ;;
  esac
  
  # Verify installation
  if ! aws --version &>/dev/null; then
    log_error "AWS CLI installation verification failed"
    return 1
  fi
  
  log_success "AWS CLI installed: $(aws --version)"
}

#######################################
# Install Azure CLI (cross-platform)
#######################################
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
    
    return 1  # Don't fail - just skip upgrade
  fi
  
  case "$PLATFORM" in
    macos)
      if command_exists brew; then
        log_info "Installing Azure CLI via Homebrew..."
        brew update && brew install azure-cli
      else
        log_error "Homebrew not found. Please install from: https://brew.sh"
        return 1
      fi
      ;;
    windows-bash)
      log_info "For Windows, please install Azure CLI manually:"
      log_info "  Download: https://aka.ms/installazurecliwindows"
      log_info "  Or use: winget install -e --id Microsoft.AzureCLI"
      return 1
      ;;
    *)
      case "$PKG_MANAGER" in
        apt)
          log_info "Installing Azure CLI via Microsoft repository..."
          retry sudo apt-get update -qq
          retry sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl apt-transport-https lsb-release gnupg
          
          sudo mkdir -p /etc/apt/keyrings
          curl -sLS https://packages.microsoft.com/keys/microsoft.asc | \
            gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
          sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
          
          # Add Azure CLI repository
          if ! command -v lsb_release &>/dev/null; then
            log_error "lsb_release not found. Cannot determine distribution codename."
            return 1
          fi
          AZ_DIST=$(lsb_release -cs)
          echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" | \
            sudo tee /etc/apt/sources.list.d/azure-cli.list
          
          retry sudo apt-get update -qq
          retry sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq azure-cli
          ;;
        yum)
          log_info "Installing Azure CLI via Microsoft repository..."
          sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
          
          sudo tee /etc/yum.repos.d/azure-cli.repo << 'EOF'
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
          
          retry sudo yum install -y -q azure-cli
          ;;
        *)
          log_info "Installing Azure CLI via pip (with --user flag)..."
          if command_exists pip3; then
            pip3 install --user azure-cli
          elif command_exists pip; then
            pip install --user azure-cli
          else
            log_error "pip/pip3 not available. Cannot install Azure CLI."
            return 1
          fi
          ;;
      esac
      ;;
  esac
  
  # Verify installation
  if ! az version &>/dev/null; then
    log_error "Azure CLI installation verification failed"
    return 1
  fi
  
  local installed_ver
  installed_ver=$(get_tool_version azure-cli)
  log_success "Azure CLI installed: ${installed_ver}"
}
#######################################
# Usage / Help
#######################################
usage() {
  cat <<EOF
Usage: $(basename "$0") --cloud <aws|azure> [OPTIONS]

CloudShell Environment Bootstrap Script for CI360 Marketing AI (MAI)

Required:
  --cloud <provider>          Cloud provider: aws or azure

Options:
  -h, --help                  Show this help message and exit
  -q, --quiet                 Suppress non-essential output (useful for CI/CD)
  -f, --force                 Force reinstall of all tools even if already installed
  -d, --dry-run               Show what would be installed without making changes
  --skip-autocomplete         Skip shell autocomplete configuration
  --install-dir <path>        Custom installation directory (default: ~/.local/bin)
  --tools <list>              Install only specific tools (comma-separated)
                              Available: kubectl,helm,aws-cli,azure-cli
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

Pinned Installation Versions:
  kubectl:    ${KUBECTL_VERSION}
  helm:       v${MIN_HELM_VERSION} - v${MAX_HELM_VERSION} (verify only — install manually if outside range)
    keda:       ${KEDA_VERSION} (Helm chart installed to ${KEDA_NAMESPACE} namespace)
  aws-cli:    ${AWS_CLI_VERSION}
  azure-cli:  ${AZURE_CLI_VERSION}

Examples:
  # Install all tools for AWS
  $(basename "$0") --cloud aws

  # Install all tools for Azure
  $(basename "$0") --cloud azure

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
# Parse Arguments
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
          echo "[ERROR] --cloud requires a provider argument (aws or azure)"
          exit 2
        fi
        CLOUD_PROVIDER="$2"
        if [[ "$CLOUD_PROVIDER" != "aws" && "$CLOUD_PROVIDER" != "azure" ]]; then
          echo "[ERROR] Invalid cloud provider: $CLOUD_PROVIDER. Must be 'aws' or 'azure'"
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
        TOOLS_ONLY="$2"
        shift 2
        ;;
      --retries)
        if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
          echo "[ERROR] --retries requires a numeric argument"
          exit 2
        fi
        MAX_RETRIES="$2"
        shift 2
        ;;
      --retry-delay)
        if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
          echo "[ERROR] --retry-delay requires a numeric argument"
          exit 2
        fi
        RETRY_DELAY="$2"
        shift 2
        ;;
      --kubectl-version)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --kubectl-version requires a version argument (e.g., v1.33.0)"
          exit 2
        fi
        KUBECTL_VERSION="$2"
        shift 2
        ;;
      --helm-version)
        if [[ -z "${2:-}" ]]; then
          echo "[ERROR] --helm-version requires a version argument (e.g., v3.18.1 or v3.19.0)"
          exit 2
        fi
        # Remove 'v' prefix for comparison
        local requested_helm="${2#v}"
        local requested_major_minor="${requested_helm%.*}"
        
        # Only accept 3.18.x or 3.19.x
        if [[ "$requested_major_minor" != "3.18" ]] && [[ "$requested_major_minor" != "3.19" ]]; then
          echo "[ERROR] helm auto-install is disabled. Only v3.18.x and v3.19.x are supported."
          echo "        Please install helm v3.18.x or v3.19.x manually before running this script."
          exit 2
        fi
        
        # Update HELM_REQUIRED_VERSION for display purposes only
        HELM_REQUIRED_VERSION="$requested_helm"
        shift 2
        ;;
      -*)
        echo "[ERROR] Unknown option: $1"
        echo "Use --help for usage information"
        exit 2
        ;;
      *)
        echo "[ERROR] Unexpected argument: $1"
        echo "Use --help for usage information"
        exit 2
        ;;
    esac
  done
  
  # Validate required arguments
  if [[ -z "$CLOUD_PROVIDER" ]]; then
    echo "[ERROR] --cloud is required. Please specify 'aws' or 'azure'"
    echo "Use --help for usage information"
    exit 2
  fi
}

#######################################
# Check if tool version meets minimum
#######################################
check_version() {
  local tool="$1"
  local min_version="$2"
  local current_version
  
  current_version=$(get_tool_version "$tool")
  
  if version_gte "$current_version" "$min_version"; then
    return 0  # Version is OK
  else
    return 1  # Version is too old
  fi
}

#######################################
# Check if tool should be installed
#######################################
should_install() {
  local tool="$1"
  local min_version="${2:-}"
  
  # Map tool names for command check
  local cmd="$tool"
  case "$tool" in
    aws-cli) cmd="aws" ;;
    azure-cli) cmd="az" ;;
    keda) cmd="kubectl" ;;  # KEDA requires kubectl to check
  esac
  
  # If specific tools requested, check if this one is in the list
  if [[ -n "$TOOLS_ONLY" ]]; then
    if ! echo "$TOOLS_ONLY" | tr ',' '\n' | grep -qx "$tool"; then
      return 1
    fi
  fi
  
  # Force reinstall
  if [[ "$FORCE_REINSTALL" == true ]]; then
    return 0
  fi
  
  # Special handling for KEDA (cluster-based tool)
  if [[ "$tool" == "keda" ]]; then
    # Check if kubectl is available
    if ! command_exists kubectl; then
      log_warn "kubectl is required to check KEDA status"
      return 0  # Should install (kubectl will be installed first)
    fi
    
    # Check if KEDA namespace exists
    if ! kubectl get namespace "$KEDA_NAMESPACE" &>/dev/null; then
      return 0  # KEDA not installed, should install
    fi
    
    # Check KEDA version
    local keda_ver
    keda_ver=$(get_tool_version keda)
    
    if [[ "$keda_ver" == "0.0.0" ]]; then
      return 0  # Version couldn't be determined, should (re)install
    fi
    
    # Check if version meets minimum
    if [[ -n "$min_version" ]] && ! version_gte "$keda_ver" "$min_version"; then
      log_warn "KEDA version ${keda_ver} is below minimum ${min_version}"
      return 0  # Should upgrade
    fi
    
    # KEDA is installed and meets minimum version
    return 1  # Should NOT install
  fi
  
  # Check if not installed (for binary tools)
  if ! command_exists "$cmd"; then
    return 0
  fi
  
  # Check if version is too old
  if [[ -n "$min_version" ]]; then
    if ! check_version "$tool" "$min_version"; then
      log_warn "$tool version $(get_tool_version "$tool") is below minimum $min_version"
      return 0  # Should upgrade
    fi
  fi
  
  return 1  # Already installed and version is OK
}

#######################################
# Capture pre-installation versions
#######################################
capture_pre_install_versions() {
  PRE_INSTALL_VERSIONS[kubectl]=$(get_tool_version kubectl)
  PRE_INSTALL_VERSIONS[helm]=$(get_tool_version helm)
  PRE_INSTALL_VERSIONS[aws-cli]=$(get_tool_version aws)
  PRE_INSTALL_VERSIONS[azure-cli]=$(get_tool_version az)
  PRE_INSTALL_VERSIONS[keda]=$(get_tool_version keda)
}

#######################################
# Track installation result
#######################################
track_install() {
  local tool="$1"
  local result="$2"  # installed, skipped, failed
  local reason="${3:-}"
  
  case "$result" in
    installed)
      INSTALLED_THIS_RUN[$tool]="$reason"
      ;;
    skipped)
      SKIPPED_THIS_RUN[$tool]="$reason"
      ;;
    failed)
      FAILED_THIS_RUN[$tool]="$reason"
      # All tools are mandatory now
      MANDATORY_FAILED=true
      ;;
  esac
}

#######################################
# Detect Package Manager
#######################################
detect_pkg_manager() {
  if command_exists apt-get; then
    echo "apt"
  elif command_exists yum; then
    echo "yum"
  elif command_exists apk; then
    echo "apk"
  else
    echo "none"
  fi
}

#######################################
# Install via Package Manager
#######################################
install_pkg() {
  local pkg="$1"

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install package: $pkg via $PKG_MANAGER"
    return 0
  fi

  case "$PKG_MANAGER" in
    apt)
      log_info "Updating apt package index..."
      retry sudo apt-get update -qq
      log_info "Installing $pkg via apt..."
      retry sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"
      ;;
    yum)
      log_info "Installing $pkg via yum..."
      retry sudo yum install -y -q "$pkg"
      ;;
    apk)
      log_info "Installing $pkg via apk..."
      retry sudo apk add --no-cache "$pkg"
      ;;
    *)
      log_error "No supported package manager found for $pkg"
      return 1
      ;;
  esac
}

#######################################
# Verify Installation
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
# Cloud-Specific Configuration
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
  esac
}

#######################################
# Post-Installation Configuration
#######################################
configure_environment() {
  if [[ "$SKIP_AUTOCOMPLETE" == true ]]; then
    log_info "Skipping autocomplete configuration (--skip-autocomplete)"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would configure shell environment and autocomplete"
    return 0
  fi

  log_info "Configuring environment..."
  
  # Detect shell config file
  local shell_rc=""
  
  if [[ -n "${BASH_VERSION:-}" ]]; then
    if [[ -f "$HOME/.bashrc" ]]; then
      shell_rc="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
      shell_rc="$HOME/.bash_profile"
    elif [[ -f "$HOME/.profile" ]]; then
      shell_rc="$HOME/.profile"
    fi
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    shell_rc="$HOME/.zshrc"
  fi
  
  # Add to PATH
  if [[ -n "$shell_rc" && -f "$shell_rc" ]]; then
    if ! grep -q "${INSTALL_DIR}" "$shell_rc" 2>/dev/null; then
      echo "" >> "$shell_rc"
      echo "# Added by setup-prerequisites-tools.sh" >> "$shell_rc"
      echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$shell_rc"
      log_success "Added ${INSTALL_DIR} to PATH in $shell_rc"
    else
      log_info "${INSTALL_DIR} already in PATH"
    fi
    
    # Configure autocomplete (Bash only)
    if [[ -n "${BASH_VERSION:-}" ]]; then
      if command_exists kubectl && ! grep -q "kubectl completion" "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# kubectl autocomplete" >> "$shell_rc"
        echo "source <(kubectl completion bash)" >> "$shell_rc"
        log_success "Enabled kubectl autocomplete"
      fi
      
      if command_exists helm && ! grep -q "helm completion" "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# helm autocomplete" >> "$shell_rc"
        echo "source <(helm completion bash)" >> "$shell_rc"
        log_success "Enabled helm autocomplete"
      fi
    fi
  fi
}
#######################################
# Print Summary
#######################################
print_summary() {
  if [[ "$QUIET_MODE" == true ]]; then
    return
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "                    Installation Summary"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Cloud Provider   : $CLOUD_PROVIDER"
  echo "Install Directory: $INSTALL_DIR"
  echo ""
  
  if [[ "$DRY_RUN" == true ]]; then
    echo "Mode: DRY-RUN (no changes made)"
    echo ""
    echo "Would install/verify:"
    echo "  - kubectl   ${KUBECTL_VERSION}           (min: v${MIN_KUBECTL_VERSION})"
    echo "  - helm      v${HELM_REQUIRED_VERSION}    (verify only — exact match required)"
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      echo "  - aws-cli   ${AWS_CLI_VERSION}          (min: ${MIN_AWS_CLI_VERSION})"
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      echo "  - azure-cli ${AZURE_CLI_VERSION}        (min: ${MIN_AZURE_CLI_VERSION})"
    fi
  else
    # Section 1: Minimum Required Versions
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ Minimum Required Versions                                   │"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│  %-12s >= v%-41s │\n" "kubectl:" "${MIN_KUBECTL_VERSION}"
    printf "│  %-12s v%-5s - v%-32s │\n" "helm:" "${MIN_HELM_VERSION}" "${MAX_HELM_VERSION}"
    printf "│  %-12s >= v%-41s │\n" "keda:" "${MIN_KEDA_VERSION}"
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      printf "│  %-12s >= %-42s │\n" "aws-cli:" "${MIN_AWS_CLI_VERSION}"
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      printf "│  %-12s >= %-42s │\n" "azure-cli:" "${MIN_AZURE_CLI_VERSION}"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Section 2: Installation Actions This Run
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ Installation Actions (This Run)                             │"
    echo "├─────────────────────────────────────────────────────────────┤"
    
    local has_actions=false
    local tool
    local new_ver
    local old_ver
    local cur_ver
    local reason
    
    # Installed tools
    if [[ ${#INSTALLED_THIS_RUN[@]} -gt 0 ]]; then
      has_actions=true
      echo "│ ⬇ INSTALLED:                                                │"
      for tool in "${!INSTALLED_THIS_RUN[@]}"; do
        new_ver=$(get_tool_version "$tool")
        old_ver="${PRE_INSTALL_VERSIONS[$tool]:-0.0.0}"
        if [[ "$old_ver" == "0.0.0" ]]; then
          printf "│   ✓ %-10s %-10s %-32s │\n" "$tool:" "$new_ver" "(new install)"
        else
          printf "│   ✓ %-10s %-6s → %-6s %-22s │\n" "$tool:" "$old_ver" "$new_ver" "(upgraded)"
        fi
      done
    fi
    
    # Skipped tools (already compatible)
    if [[ ${#SKIPPED_THIS_RUN[@]} -gt 0 ]]; then
      has_actions=true
      echo "│ ○ SKIPPED (already compatible):                             │"
      for tool in "${!SKIPPED_THIS_RUN[@]}"; do
        cur_ver=$(get_tool_version "$tool")
        reason="${SKIPPED_THIS_RUN[$tool]}"
        # Fix formatting - align columns properly
        printf "│   ○ %-10s %-10s %-32s │\n" "$tool:" "$cur_ver" "($reason)"
      done
    fi
    
    # Failed tools
    if [[ ${#FAILED_THIS_RUN[@]} -gt 0 ]]; then
      has_actions=true
      echo "│ ✗ FAILED:                                                   │"
      for tool in "${!FAILED_THIS_RUN[@]}"; do
        reason="${FAILED_THIS_RUN[$tool]}"
        printf "│   ✗ %-10s %-44s │\n" "$tool:" "$reason"
      done
    fi
    
    if [[ "$has_actions" == false ]]; then
      echo "│   No actions taken                                          │"
    fi
    
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Section 3: Current Tool Status
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ Current Tool Status                                         │"
    echo "├─────────────────────────────────────────────────────────────┤"
    
    # Helper function for status display
    print_tool_status() {
      local tool="$1"
      local min_ver="$2"
      local cmd="$tool"
      local display_name="$tool"
      local cur_ver
      local status
      local status_text
      
      case "$tool" in
        aws-cli) cmd="aws"; display_name="aws-cli" ;;
        azure-cli) cmd="az"; display_name="azure-cli" ;;
      esac
      
      if command_exists "$cmd"; then
        cur_ver=$(get_tool_version "$tool")
        status="✓"
        status_text="OK"
        if ! version_gte "$cur_ver" "$min_ver"; then
          status="⚠"
          status_text="UPGRADE NEEDED"
        fi
        printf "│  %s %-11s %-12s %-28s │\n" "$status" "${display_name}:" "$cur_ver" "($status_text)"
      else
        printf "│  ✗ %-11s %-12s %-28s │\n" "${display_name}:" "---" "(NOT INSTALLED)"
      fi
    }
    
    print_tool_status "kubectl" "$MIN_KUBECTL_VERSION"
    
    # Helm status with range check
    local helm_ver
    helm_ver=$(get_tool_version helm)
    local helm_major_minor="${helm_ver%.*}"
    
    if command_exists helm; then
      # Check if in acceptable range (3.18.x or 3.19.x)
      if ([[ "$helm_major_minor" == "3.18" ]] && version_gte "$helm_ver" "$MIN_HELM_VERSION") || [[ "$helm_major_minor" == "3.19" ]]; then
        printf "│  ✓ %-11s %-12s %-28s │\n" "helm:" "$helm_ver" "(OK)"
      else
        printf "│  ✗ %-11s %-12s %-28s │\n" "helm:" "$helm_ver" "(REQUIRED: v${MIN_HELM_VERSION}-v${MAX_HELM_VERSION})"
      fi
    else
      printf "│  ✗ %-11s %-12s %-28s │\n" "helm:" "---" "(NOT INSTALLED)"
    fi

    # KEDA status - cluster-based check
    local keda_ver
    keda_ver=$(get_tool_version keda)
    
    if [[ "$keda_ver" != "0.0.0" ]]; then
      if version_gte "$keda_ver" "$MIN_KEDA_VERSION"; then
        printf "│  ✓ %-11s %-12s %-28s │\n" "keda:" "$keda_ver" "(OK)"
      else
        printf "│  ⚠ %-11s %-12s %-28s │\n" "keda:" "$keda_ver" "(UPGRADE NEEDED)"
      fi
    else
      printf "│  ✗ %-11s %-12s %-28s │\n" "keda:" "---" "(NOT INSTALLED)"
    fi

    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      print_tool_status "aws-cli" "$MIN_AWS_CLI_VERSION"
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      print_tool_status "azure-cli" "$MIN_AZURE_CLI_VERSION"
    fi
    
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Legend: ✓ = OK  ⚠ = Below minimum  ✗ = Not installed        │"
    echo "└─────────────────────────────────────────────────────────────┘"
    
    # Check if all tools are compatible
    
    local all_compatible=true
    local tools_to_check=("kubectl" "helm" "keda")
    local tools_to_check=("kubectl" "helm")
    local min_versions=("$MIN_KUBECTL_VERSION" "$MIN_HELM_VERSION")
    local i
    
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
      tools_to_check+=("aws-cli")
      min_versions+=("$MIN_AWS_CLI_VERSION")
    elif [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      tools_to_check+=("azure-cli")
      min_versions+=("$MIN_AZURE_CLI_VERSION")
    fi
    
    for i in "${!tools_to_check[@]}"; do
      local tool="${tools_to_check[$i]}"
      local min_ver="${min_versions[$i]}"
      
      # Special handling for helm - must match major.minor version
      if [[ "$tool" == "helm" ]]; then
        if command_exists helm; then
          local helm_ver
          helm_ver=$(get_tool_version helm)
          local helm_major_minor="${helm_ver%.*}"
          
          # Accept 3.18.x (>= 3.18.0) or 3.19.x
          if ([[ "$helm_major_minor" == "3.18" ]] && version_gte "$helm_ver" "$MIN_HELM_VERSION") || [[ "$helm_major_minor" == "3.19" ]]; then
            # Version is acceptable
            :
          else
            all_compatible=false
            break
          fi
        else
          all_compatible=false
          break
        fi
      elif [[ "$tool" == "keda" ]]; then
        if ! verify_keda &>/dev/null; then
          all_compatible=false
          break
        fi
      else
        # For other tools, check minimum version
        if ! check_version "$tool" "$min_ver"; then
          all_compatible=false
          break
        fi
      fi
    done
    
    echo ""
    if [[ "$all_compatible" == true ]]; then
      log_success "All tools meet minimum version requirements!"
    else
      log_warn "Some tools do not meet version requirements. Please review above."
    fi
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
}

#######################################
# Main Execution
#######################################
main() {
  # Parse command line arguments first
  parse_args "$@"
  
  # Detect environment
  PKG_MANAGER="$(detect_pkg_manager)"
  
  # Create install directory
  mkdir -p "${INSTALL_DIR}"
  export PATH="${INSTALL_DIR}:$PATH"
  
  # Capture versions before installation
  capture_pre_install_versions
  
  if [[ "$QUIET_MODE" != true ]]; then
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     CloudShell Environment Bootstrap Script               ║"
    echo "║     CI360 Marketing AI (MAI) - Local Agent Setup          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "Cloud provider: $CLOUD_PROVIDER"
    log_info "Detected package manager: $PKG_MANAGER"
    log_info "Pinned versions: kubectl=${KUBECTL_VERSION}, helm=v${MIN_HELM_VERSION}-v${MAX_HELM_VERSION} (verify only)"
    echo ""
  fi
  
  log_info "Starting environment validation and tool installation..."
  
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Running in DRY-RUN mode - no changes will be made"
  fi
  
  if [[ "$FORCE_REINSTALL" == true ]]; then
    log_info "Force reinstall enabled - all tools will be reinstalled"
  fi
  
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
  fi
  verify_tool kubectl "$MIN_KUBECTL_VERSION" || true

  # Helm — verify only, do NOT install
    log_info "Verifying helm version (required: v${MIN_HELM_VERSION} - v${MAX_HELM_VERSION}, no auto-install)..."
  if verify_helm_version; then
    track_install "helm" "skipped" "verified"
  else
    track_install "helm" "failed" "version mismatch or not installed"
  fi
  
  # KEDA — install if not present or version too old
  if should_install keda "$MIN_KEDA_VERSION"; then
    if install_keda; then
      track_install "keda" "installed" "new/upgraded"
    else
      track_install "keda" "failed" "installation error"
    fi
  else
    track_install "keda" "skipped" "meets minimum"
    log_info "KEDA already meets minimum version (use --force to reinstall)"
  fi
  verify_keda || true

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
          # Check if it failed due to Cloud Shell limitation
          local current_ver
          current_ver=$(get_tool_version azure-cli)
          
          if is_azure_cloudshell && [[ "$current_ver" != "0.0.0" ]]; then
            # Azure CLI exists in CloudShell but cannot be upgraded
            track_install "azure-cli" "skipped" "CloudShell managed (v${current_ver})"
            
            if ! version_gte "$current_ver" "$MIN_AZURE_CLI_VERSION"; then
              log_warn "Azure CLI v${current_ver} is below minimum v${MIN_AZURE_CLI_VERSION}"
              log_warn "In Azure Cloud Shell, Azure CLI is managed by Microsoft and will be updated in future releases."
              # Don't fail the entire bootstrap for Azure CLI version in CloudShell
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
  esac
  
  # Cloud-specific configuration
  configure_cloud_tools
  
  # Environment configuration
  configure_environment
  
  # Print summary
  print_summary
  
  # Final status message and exit code
  echo ""
  if [[ "$MANDATORY_FAILED" == true ]]; then
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  ✗ BOOTSTRAP FAILED                                       ║"
    echo "║    One or more mandatory tools failed to install.         ║"
    echo "║    Please review the errors above and retry.              ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    exit 4
  else
    # Check if we have warnings about cloud CLI versions
    local has_cli_warning=false
    
    if [[ "$CLOUD_PROVIDER" == "azure" ]]; then
      local azure_ver
      azure_ver=$(get_tool_version azure-cli)
      if [[ "$azure_ver" != "0.0.0" ]] && ! version_gte "$azure_ver" "$MIN_AZURE_CLI_VERSION"; then
        has_cli_warning=true
      fi
    fi
    
    if [[ "$has_cli_warning" == true ]] && is_any_cloudshell; then
      echo "╔═══════════════════════════════════════════════════════════╗"
      echo "║  ⚠ BOOTSTRAP COMPLETE WITH WARNINGS                       ║"
      echo "║    Mandatory tools (kubectl, helm) are installed.         ║"
      echo "║    Cloud CLI version is below minimum but managed by      ║"
      echo "║    the cloud provider and will be updated automatically.  ║"
      echo "╚═══════════════════════════════════════════════════════════╝"
      log_warn "Bootstrap complete with warnings. Review above for details."
      exit 0
    else
      echo "╔═══════════════════════════════════════════════════════════╗"
      echo "║  ✓ BOOTSTRAP COMPLETE                                     ║"
      echo "║    All tools installed and verified successfully.         ║"
      echo "╚═══════════════════════════════════════════════════════════╝"
      log_success "Bootstrap complete!"
      exit 0
    fi
  fi
}

# Execute main function
main "$@"
