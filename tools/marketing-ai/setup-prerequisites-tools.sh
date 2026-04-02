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
# | `--helm-version <v>` | Specific helm version to install (default: v3.18.1) |

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

# # Install specific versions
# ./setup-prerequisites-tools.sh --cloud aws --kubectl-version v1.33.0 --helm-version v3.18.1
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
if [[ "$(file "$0" 2>/dev/null)" == *"CRLF"* ]]; then
  echo "[WARN] Detected Windows line endings. Converting..."
  sed -i 's/\r$//' "$0"
  echo "[INFO] Line endings fixed. Re-executing script..."
  exec "$0" "$@"
fi

set -euo pipefail

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
MIN_HELM_VERSION="3.18.1"
MIN_AWS_CLI_VERSION="2.18.1"
MIN_AZURE_CLI_VERSION="2.83.0"

# Pinned versions for installation (>= minimum)
KUBECTL_VERSION="v1.33.0"
HELM_REQUIRED_VERSION="3.18.1"
HELM_VERSION="${HELM_REQUIRED_VERSION}"
AWS_CLI_VERSION="2.18.1"
AZURE_CLI_VERSION="2.83.0"

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

# Define mandatory tools
MANDATORY_TOOLS=("kubectl" "helm")

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
  --helm-version <version>    Specific helm version — NOTE: only v${HELM_REQUIRED_VERSION} is supported.
                              Auto-install is disabled; script will verify only.

Minimum Required Versions:
  kubectl:    >= v${MIN_KUBECTL_VERSION}
  helm:       == v${HELM_REQUIRED_VERSION}  (exact match required — no auto-install)
  aws-cli:    >= ${MIN_AWS_CLI_VERSION} (AWS only)
  azure-cli:  >= ${MIN_AZURE_CLI_VERSION} (Azure only)

Pinned Installation Versions:
  kubectl:    ${KUBECTL_VERSION}
  helm:       ${HELM_REQUIRED_VERSION}  (verify only — install manually if mismatched)
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

  # Install specific versions
  $(basename "$0") --cloud aws --kubectl-version v1.32.0 --helm-version v3.17.0

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
          echo "[ERROR] --helm-version requires a version argument (e.g., v3.18.1)"
          exit 2
        fi
        # Helm version cannot be changed — only HELM_REQUIRED_VERSION is supported
        if [[ "${2#v}" != "$HELM_REQUIRED_VERSION" ]]; then
          echo "[ERROR] helm auto-install is disabled. Only v${HELM_REQUIRED_VERSION} is supported."
          echo "        Please install helm v${HELM_REQUIRED_VERSION} manually before running this script."
          exit 2
        fi
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
# Returns 0 if $1 >= $2, 1 otherwise
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
      version=$(helm version --short 2>/dev/null | sed -n 's/.*v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
      version="${version:-0.0.0}"
      ;;
    aws|aws-cli)
      version=$(aws --version 2>/dev/null | sed -n 's/aws-cli\/\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
      version="${version:-0.0.0}"
      ;;
    az|azure-cli)
      version=$(az version 2>/dev/null | sed -n 's/.*"azure-cli": "\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' | head -1)
      version="${version:-0.0.0}"
      ;;
  esac
  
  echo "$version"
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
# Command Check
#######################################
command_exists() {
  command -v "$1" >/dev/null 2>&1
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
  
  # Check if not installed
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
# Tool Installers
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
  
  log_info "Downloading kubectl ${KUBECTL_VERSION}..."
  retry curl -fsSL \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o "${INSTALL_DIR}/kubectl"
  
  chmod +x "${INSTALL_DIR}/kubectl"
  
  # Verify the binary works
  if ! "${INSTALL_DIR}/kubectl" version --client &>/dev/null; then
    log_error "kubectl binary verification failed"
    return 1
  fi
  
  log_success "kubectl ${KUBECTL_VERSION} installed to ${INSTALL_DIR}/kubectl"
}

# Helm is NOT installed by this script.
# Only verifies the installed version matches exactly v3.18.1
verify_helm_version() {
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would verify helm == v${HELM_REQUIRED_VERSION}"
    return 0
  fi

  if ! command_exists helm; then
    log_error "helm is NOT installed."
    log_error "Please install helm v${HELM_REQUIRED_VERSION} manually:"
    log_error ""
    log_error "  Linux/macOS:"
    log_error "    curl -fsSL https://get.helm.sh/helm-v${HELM_REQUIRED_VERSION}-linux-amd64.tar.gz | tar -xz"
    log_error "    mv linux-amd64/helm /usr/local/bin/helm"
    log_error ""
    log_error "  macOS (Homebrew):"
    log_error "    brew install helm@${HELM_REQUIRED_VERSION}"
    log_error ""
    log_error "  Windows (Chocolatey):"
    log_error "    choco install kubernetes-helm --version ${HELM_REQUIRED_VERSION}"
    log_error ""
    log_error "  Official docs: https://helm.sh/docs/intro/install/"
    return 1
  fi

  local installed_ver
  installed_ver=$(get_tool_version helm)

  if [[ "$installed_ver" == "$HELM_REQUIRED_VERSION" ]]; then
    log_success "helm version verified: v${installed_ver} (required: v${HELM_REQUIRED_VERSION} ✓)"
    return 0
  else
    log_error "helm version mismatch!"
    log_error "  Installed : v${installed_ver}"
    log_error "  Required  : v${HELM_REQUIRED_VERSION}"
    log_error ""
    log_error "Please install the exact required version manually:"
    log_error ""
    log_error "  Linux/macOS:"
    log_error "    curl -fsSL https://get.helm.sh/helm-v${HELM_REQUIRED_VERSION}-linux-amd64.tar.gz | tar -xz"
    log_error "    sudo mv linux-amd64/helm /usr/local/bin/helm"
    log_error ""
    log_error "  macOS (Homebrew):"
    log_error "    brew unlink helm && brew install helm@${HELM_REQUIRED_VERSION}"
    log_error ""
    log_error "  Windows (Chocolatey):"
    log_error "    choco install kubernetes-helm --version ${HELM_REQUIRED_VERSION}"
    log_error ""
    log_error "  Official docs: https://helm.sh/docs/intro/install/"
    return 1
  fi
}

install_aws_cli() {
  log_info "Installing AWS CLI ${AWS_CLI_VERSION} (minimum: ${MIN_AWS_CLI_VERSION})..."
  
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install AWS CLI ${AWS_CLI_VERSION}"
    return 0
  fi
  
  log_info "Downloading AWS CLI v2..."
  
  cd /tmp
  retry curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  
  # Install unzip if needed
  if ! command_exists unzip; then
    install_pkg unzip
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
  
  # Cleanup
  rm -rf aws awscliv2.zip
  
  # Verify installation
  if ! aws --version &>/dev/null; then
    log_error "AWS CLI installation verification failed"
    return 1
  fi
  
  log_success "AWS CLI installed: $(aws --version)"
}

install_azure_cli() {
  log_info "Installing Azure CLI ${AZURE_CLI_VERSION} (minimum: ${MIN_AZURE_CLI_VERSION})..."
  
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would install Azure CLI ${AZURE_CLI_VERSION}"
    return 0
  fi
  
  case "$PKG_MANAGER" in
    apt)
      log_info "Installing Azure CLI via Microsoft repository..."
      
      # Install prerequisites
      retry sudo apt-get update -qq
      retry sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl apt-transport-https lsb-release gnupg
      
      # Add Microsoft signing key
      sudo mkdir -p /etc/apt/keyrings
      curl -sLS https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
      sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
      
      # Add Azure CLI repository
      AZ_DIST=$(lsb_release -cs)
      echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" | \
        sudo tee /etc/apt/sources.list.d/azure-cli.list
      
      # Install Azure CLI
      retry sudo apt-get update -qq
      retry sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq azure-cli
      ;;
    yum)
      log_info "Installing Azure CLI via Microsoft repository..."
      
      # Import Microsoft repository key
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      
      # Add Azure CLI repository
      sudo tee /etc/yum.repos.d/azure-cli.repo << 'EOF'
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
      
      # Install Azure CLI
      retry sudo yum install -y -q azure-cli
      ;;
    *)
      log_info "Installing Azure CLI via pip..."
      pip3 install azure-cli
      ;;
  esac
  
  # Verify installation
  if ! az version &>/dev/null; then
    log_error "Azure CLI installation verification failed"
    return 1
  fi
  
  log_success "Azure CLI installed: $(az version -o tsv 2>/dev/null | head -1)"
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
  
  # Add to PATH in shell profile
  local shell_rc=""
  
  if [[ -f "$HOME/.bashrc" ]]; then
    shell_rc="$HOME/.bashrc"
  elif [[ -f "$HOME/.bash_profile" ]]; then
    shell_rc="$HOME/.bash_profile"
  elif [[ -f "$HOME/.profile" ]]; then
    shell_rc="$HOME/.profile"
  fi
  
  if [[ -n "$shell_rc" ]]; then
    if ! grep -q "${INSTALL_DIR}" "$shell_rc"; then
      echo "" >> "$shell_rc"
      echo "# Added by setup-prerequisites-tools.sh" >> "$shell_rc"
      echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$shell_rc"
      log_success "Added ${INSTALL_DIR} to PATH in $shell_rc"
    else
      log_info "${INSTALL_DIR} already in PATH"
    fi
  fi
  
  # Configure kubectl autocomplete
  if command_exists kubectl; then
    if [[ -n "$shell_rc" ]]; then
      if ! grep -q "kubectl completion" "$shell_rc"; then
        echo "" >> "$shell_rc"
        echo "# kubectl autocomplete" >> "$shell_rc"
        echo "source <(kubectl completion bash)" >> "$shell_rc"
        log_success "Enabled kubectl autocomplete"
      fi
    fi
  fi
  
  # Configure helm autocomplete
  if command_exists helm; then
    if [[ -n "$shell_rc" ]]; then
      if ! grep -q "helm completion" "$shell_rc"; then
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
    printf "│  %-12s = v%-41s │\n" "helm:" "${MIN_HELM_VERSION}"
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
          printf "│   ✓ %-10s %-10s (new install)                     │\n" "$tool:" "$new_ver"
        else
          printf "│   ✓ %-10s %-6s → %-6s (upgraded)                  │\n" "$tool:" "$old_ver" "$new_ver"
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
        printf "│   ○ %-10s %-10s (%s)                       │\n" "$tool:" "$cur_ver" "$reason"
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
    local helm_ver
    helm_ver=$(get_tool_version helm)
    if command_exists helm && [[ "$helm_ver" == "$HELM_REQUIRED_VERSION" ]]; then
      printf "│  ✓ %-11s %-12s %-28s │\n" "helm:" "$helm_ver" "(exact match required)"
    elif command_exists helm; then
      printf "│  ✗ %-11s %-12s %-28s │\n" "helm:" "$helm_ver" "(REQUIRED: v${HELM_REQUIRED_VERSION})"
    else
      printf "│  ✗ %-11s %-12s %-28s │\n" "helm:" "---" "(NOT INSTALLED)"
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
      tool="${tools_to_check[$i]}"
      local min_ver="${min_versions[$i]}"
      if ! check_version "$tool" "$min_ver"; then
        all_compatible=false
        break
      fi
    done
    
    echo ""
    if [[ "$all_compatible" == true ]]; then
      log_success "All tools meet minimum version requirements!"
    else
      log_warn "Some tools do not meet minimum version requirements. Please review above."
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
    log_info "Pinned versions: kubectl=${KUBECTL_VERSION}, helm=${HELM_REQUIRED_VERSION} (verify only)"
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
  log_info "Verifying helm version (required: v${HELM_REQUIRED_VERSION}, no auto-install)..."
  if verify_helm_version; then
    track_install "helm" "skipped" "verified"
  else
    track_install "helm" "failed" "version mismatch or not installed"
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
          track_install "azure-cli" "failed" "installation error"
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
    echo "║    One or more tools failed to install.                   ║"
    echo "║    Please review the errors above and retry.              ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    exit 4
  else
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  ✓ BOOTSTRAP COMPLETE                                     ║"
    echo "║    All tools installed and verified successfully.         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    log_success "Bootstrap complete!"
    exit 0
  fi
}

# Execute main function
main "$@"
