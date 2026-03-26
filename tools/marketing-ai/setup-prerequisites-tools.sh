#!/usr/bin/env bash
# filepath: c:\NexusProject\ci360-mkt-ai-helm\maila-bootstrap-tools.sh
###############################################################################
# CloudShell Tool Bootstrap Script
#
# Compatible with:
#   - AWS CloudShell (Amazon Linux)
#   - Azure Cloud Shell (Ubuntu)
#   - GCP Cloud Shell (Debian)
#
# Tools:
#   - git
#   - python3
#   - kubectl
#   - helm
#
# Features:
#   - Idempotent checks
#   - Retries with backoff
#   - Descriptive error handling
#   - Non-interactive installs
#   - Self-healing line endings
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

mkdir -p "${INSTALL_DIR}"
export PATH="${INSTALL_DIR}:$PATH"

#######################################
# Logging Helpers
#######################################
log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

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
# Detect Cloud Provider
#######################################
detect_cloud() {
  if [[ -n "${AWS_EXECUTION_ENV:-}" ]] || [[ -f /etc/cloudshell-version ]]; then
    echo "aws"
  elif [[ -n "${AZURE_HTTP_USER_AGENT:-}" ]] || [[ -d /usr/lib/azure-cli ]]; then
    echo "azure"
  elif [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]] || [[ -f /google/devshell/bashrc.google ]]; then
    echo "gcp"
  else
    echo "unknown"
  fi
}

CLOUD_PROVIDER="$(detect_cloud)"
log_info "Detected cloud provider: $CLOUD_PROVIDER"

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

PKG_MANAGER="$(detect_pkg_manager)"
log_info "Detected package manager: $PKG_MANAGER"

#######################################
# Install via Package Manager
#######################################
install_pkg() {
  local pkg="$1"

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
install_git() {
  log_info "Installing git..."
  install_pkg git
}

install_python() {
  log_info "Installing python3..."
  
  case "$PKG_MANAGER" in
    apt)
      install_pkg python3
      install_pkg python3-pip
      ;;
    yum)
      install_pkg python3
      install_pkg python3-pip
      ;;
    *)
      install_pkg python3
      ;;
  esac
}

install_kubectl() {
  log_info "Installing kubectl..."
  
  # Get latest stable version
  local version
  version="$(retry curl -fsSL https://dl.k8s.io/release/stable.txt)"
  
  log_info "Downloading kubectl ${version}..."
  retry curl -fsSL \
    "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl" \
    -o "${INSTALL_DIR}/kubectl"
  
  chmod +x "${INSTALL_DIR}/kubectl"
  
  # Verify the binary works
  if ! "${INSTALL_DIR}/kubectl" version --client &>/dev/null; then
    log_error "kubectl binary verification failed"
    return 1
  fi
}

install_helm() {
  log_info "Installing helm..."
  
  # Download and run the official Helm installer
  retry curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  
  # Verify installation
  if ! command_exists helm; then
    log_error "Helm installation failed"
    return 1
  fi
}

install_yq() {
  log_info "Installing yq (YAML processor)..."
  
  local version="v4.40.5"
  local binary="yq_linux_amd64"
  
  retry curl -fsSL \
    "https://github.com/mikefarah/yq/releases/download/${version}/${binary}" \
    -o "${INSTALL_DIR}/yq"
  
  chmod +x "${INSTALL_DIR}/yq"
  
  # Verify the binary works
  if ! "${INSTALL_DIR}/yq" --version &>/dev/null; then
    log_error "yq binary verification failed"
    return 1
  fi
}

install_jq() {
  log_info "Installing jq (JSON processor)..."
  
  case "$PKG_MANAGER" in
    apt|yum)
      install_pkg jq
      ;;
    *)
      # Manual installation
      retry curl -fsSL \
        "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" \
        -o "${INSTALL_DIR}/jq"
      chmod +x "${INSTALL_DIR}/jq"
      ;;
  esac
}

#######################################
# Verify Installation
#######################################
verify_tool() {
  local tool="$1"
  
  if ! command_exists "$tool"; then
    log_error "$tool is not available after installation"
    return 1
  fi
  
  local version_output
  version_output="$($tool --version 2>&1 | head -n1)"
  
  log_success "$tool is available: $version_output"
  return 0
}

#######################################
# Cloud-Specific Configuration
#######################################
configure_cloud_tools() {
  case "$CLOUD_PROVIDER" in
    aws)
      log_info "Configuring AWS CloudShell..."
      # AWS CLI is pre-installed in CloudShell
      if command_exists aws; then
        log_success "AWS CLI is available: $(aws --version)"
      fi
      ;;
    azure)
      log_info "Configuring Azure Cloud Shell..."
      # Azure CLI is pre-installed in Cloud Shell
      if command_exists az; then
        log_success "Azure CLI is available: $(az version -o tsv | head -n1)"
      fi
      ;;
    gcp)
      log_info "Configuring GCP Cloud Shell..."
      # gcloud is pre-installed in Cloud Shell
      if command_exists gcloud; then
        log_success "gcloud CLI is available: $(gcloud --version | head -n1)"
      fi
      ;;
    *)
      log_warn "Unknown cloud provider. Skipping cloud-specific configuration."
      ;;
  esac
}

#######################################
# Post-Installation Configuration
#######################################
configure_environment() {
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
      echo "# Added by maila-bootstrap-tools.sh" >> "$shell_rc"
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
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "                    Installation Summary"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Cloud Provider: $CLOUD_PROVIDER"
  echo "Install Directory: $INSTALL_DIR"
  echo ""
  echo "Installed Tools:"
  echo "  ✓ git:     $(git --version 2>&1 | head -n1)"
  echo "  ✓ python3: $(python3 --version 2>&1)"
  echo "  ✓ kubectl: $(kubectl version --client --short 2>&1 | head -n1)"
  echo "  ✓ helm:    $(helm version --short 2>&1)"
  
  if command_exists yq; then
    echo "  ✓ yq:      $(yq --version 2>&1)"
  fi
  
  if command_exists jq; then
    echo "  ✓ jq:      $(jq --version 2>&1)"
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  log_success "All tools are ready! You may need to restart your shell or run:"
  echo ""
  echo "    source ~/.bashrc"
  echo ""
}

#######################################
# Main Execution
#######################################
main() {
  echo ""
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║     CloudShell Environment Bootstrap Script               ║"
  echo "║     CI360 Marketing AI (MAI) - Local Agent Setup          ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo ""
  
  log_info "Starting environment validation and tool installation..."
  echo ""
  
  # Install core tools
  if ! command_exists git; then
    install_git
  else
    log_info "git is already installed"
  fi
  verify_tool git
  
  if ! command_exists python3; then
    install_python
  else
    log_info "python3 is already installed"
  fi
  verify_tool python3
  
  if ! command_exists kubectl; then
    install_kubectl
  else
    log_info "kubectl is already installed"
  fi
  verify_tool kubectl
  
  if ! command_exists helm; then
    install_helm
  else
    log_info "helm is already installed"
  fi
  verify_tool helm
  
  # Install optional but recommended tools
  if ! command_exists yq; then
    install_yq
  else
    log_info "yq is already installed"
  fi
  verify_tool yq || log_warn "yq installation failed (optional tool)"
  
  if ! command_exists jq; then
    install_jq
  else
    log_info "jq is already installed"
  fi
  verify_tool jq || log_warn "jq installation failed (optional tool)"
  
  # Cloud-specific configuration
  configure_cloud_tools
  
  # Environment configuration
  configure_environment
  
  # Print summary
  print_summary
  
  log_success "Bootstrap complete!"
}

# Execute main function
main "$@"