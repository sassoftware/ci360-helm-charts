#!/usr/bin/env bash
# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

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
###############################################################################

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
# Detect Package Manager
#######################################
detect_pkg_manager() {
  if command_exists apt-get; then
    echo "apt"
  elif command_exists yum; then
    echo "yum"
  else
    echo "none"
  fi
}

PKG_MANAGER="$(detect_pkg_manager)"

#######################################
# Install via Package Manager
#######################################
install_pkg() {
  local pkg="$1"

  case "$PKG_MANAGER" in
    apt)
      retry sudo apt-get update -y
      retry sudo apt-get install -y "$pkg"
      ;;
    yum)
      retry sudo yum install -y "$pkg"
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
  install_pkg python3
}

install_kubectl() {
  log_info "Installing kubectl..."
  local url
  url="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  retry curl -fsSL \
    "https://dl.k8s.io/release/${url}/bin/linux/amd64/kubectl" \
    -o "${INSTALL_DIR}/kubectl"
  chmod +x "${INSTALL_DIR}/kubectl"
}

install_helm() {
  log_info "Installing helm..."
  retry curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

#######################################
# Verify Installation
#######################################
verify_tool() {
  local tool="$1"
  if ! command_exists "$tool"; then
    log_error "$tool installation failed"
    exit 1
  fi
  log_info "$tool is available: $($tool --version 2>/dev/null | head -n1)"
}

#######################################
# Main Execution
#######################################
main() {
  log_info "Starting CloudShell environment validation..."

  if ! command_exists git; then
    install_git
  fi
  verify_tool git

  if ! command_exists python3; then
    install_python
  fi
  verify_tool python3

  if ! command_exists kubectl; then
    install_kubectl
  fi
  verify_tool kubectl

  if ! command_exists helm; then
    install_helm
  fi
  verify_tool helm

  log_info "All required tools are installed and ready."
}

main "$@"
