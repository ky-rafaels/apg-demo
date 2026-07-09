#!/usr/bin/env bash
# nvidia-gpu-preflight.sh — Check prerequisites for NVIDIA GPU driver installation on Ubuntu
# Run as root or with sudo

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
LOG_PREFIX="[nvidia-preflight]"
ERRORS=0

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo "${LOG_PREFIX} INFO:  $*"; }
success() { echo "${LOG_PREFIX} OK:    $*"; }
warn()    { echo "${LOG_PREFIX} WARN:  $*"; }
fail()    { echo "${LOG_PREFIX} FAIL:  $*" >&2; (( ERRORS++ )) || true; }
die()     { echo "${LOG_PREFIX} ERROR: $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root (or via sudo)."
}

# ── 1. Confirm NVIDIA GPU is present ─────────────────────────────────────────
check_gpu_present() {
  info "Checking for NVIDIA GPU..."

  if ! lspci | grep -qi nvidia; then
    fail "No NVIDIA GPU detected via lspci. Ensure the GPU is seated and recognized by the system."
    return
  fi

  local gpu_info
  gpu_info="$(lspci | grep -i nvidia | head -1)"
  success "NVIDIA GPU detected: ${gpu_info}"
}

# ── 2. Check Ubuntu version ───────────────────────────────────────────────────
check_ubuntu_version() {
  info "Checking OS..."

  if [[ ! -f /etc/os-release ]]; then
    fail "/etc/os-release not found — cannot determine OS."
    return
  fi

  # shellcheck source=/dev/null
  source /etc/os-release

  if [[ "${ID}" != "ubuntu" ]]; then
    fail "OS is '${ID}', expected Ubuntu. This script targets Ubuntu only."
    return
  fi

  local major
  major="$(echo "${VERSION_ID}" | cut -d. -f1)"

  if (( major < 20 )); then
    fail "Ubuntu ${VERSION_ID} is not supported. Minimum supported version is 20.04."
    return
  fi

  success "Ubuntu ${VERSION_ID} detected."
}

# ── 3. Check kernel headers are installed ────────────────────────────────────
check_kernel_headers() {
  info "Checking kernel headers..."

  local running_kernel
  running_kernel="$(uname -r)"

  if ! dpkg -l "linux-headers-${running_kernel}" 2>/dev/null | grep -q '^ii'; then
    fail "Kernel headers for ${running_kernel} are not installed. Run: apt-get install linux-headers-${running_kernel}"
    return
  fi

  success "Kernel headers present for ${running_kernel}."
}

# ── 4. Check build tools (gcc, make, dkms) ───────────────────────────────────
check_build_tools() {
  info "Checking build tools..."

  local missing=()
  for pkg in gcc make dkms; do
    if ! dpkg -l "${pkg}" 2>/dev/null | grep -q '^ii'; then
      missing+=("${pkg}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    fail "Missing build packages: ${missing[*]}. Run: apt-get install ${missing[*]}"
    return
  fi

  success "Build tools present (gcc, make, dkms)."
}

# ── 5. Check secure boot status ──────────────────────────────────────────────
check_secure_boot() {
  info "Checking Secure Boot status..."

  if ! command -v mokutil &>/dev/null; then
    warn "mokutil not found — cannot determine Secure Boot state. Install mokutil to check."
    return
  fi

  local sb_state
  sb_state="$(mokutil --sb-state 2>/dev/null || true)"

  if echo "${sb_state}" | grep -qi "SecureBoot enabled"; then
    warn "Secure Boot is ENABLED. NVIDIA drivers require a signed MOK or Secure Boot must be disabled."
  else
    success "Secure Boot is not enabled."
  fi
}

# ── 6. Check for conflicting nouveau driver ───────────────────────────────────
check_nouveau() {
  info "Checking for nouveau driver..."

  if lsmod | grep -q "^nouveau"; then
    fail "The nouveau driver is currently loaded. It must be blacklisted before installing NVIDIA drivers."
    info "  To blacklist: echo 'blacklist nouveau' >> /etc/modprobe.d/blacklist-nouveau.conf && update-initramfs -u && reboot"
    return
  fi

  if grep -rq "^blacklist nouveau" /etc/modprobe.d/ 2>/dev/null; then
    success "nouveau is blacklisted and not loaded."
  else
    warn "nouveau is not currently loaded but is not explicitly blacklisted. Consider adding a blacklist entry before installing drivers."
  fi
}

# ── 7. Check existing NVIDIA driver installation ─────────────────────────────
check_existing_driver() {
  info "Checking for existing NVIDIA driver installation..."

  if command -v nvidia-smi &>/dev/null; then
    local driver_ver
    driver_ver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
    warn "NVIDIA driver already installed (version: ${driver_ver:-unknown}). Reinstalling may require a reboot."
    return
  fi

  if dpkg -l 'nvidia-driver-*' 2>/dev/null | grep -q '^ii'; then
    local installed_pkg
    installed_pkg="$(dpkg -l 'nvidia-driver-*' 2>/dev/null | grep '^ii' | awk '{print $2}' | head -1)"
    warn "NVIDIA driver package already installed: ${installed_pkg}."
    return
  fi

  success "No existing NVIDIA driver installation detected."
}

# ── 8. Install NFS and block storage packages ────────────────────────────────
install_storage_packages() {
  info "Installing NFS and block storage packages..."

  # NFS client — required for mounting NFS persistent volumes
  # open-iscsi — required for iSCSI block storage (Longhorn, Portworx, etc.)
  # multipath-tools — required for multipath I/O on SAN/block devices
  # lsscsi — lists SCSI/NVMe devices; useful for storage debugging
  # sg3-utils — low-level SCSI utilities needed by some CSI drivers
  local packages=(nfs-common open-iscsi multipath-tools lsscsi sg3-utils)
  local to_install=()

  for pkg in "${packages[@]}"; do
    if ! dpkg -l "${pkg}" 2>/dev/null | grep -q '^ii'; then
      to_install+=("${pkg}")
    else
      success "Package already installed: ${pkg}"
    fi
  done

  if (( ${#to_install[@]} > 0 )); then
    info "Installing missing packages: ${to_install[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${to_install[@]}" \
      || { fail "Failed to install one or more storage packages: ${to_install[*]}"; return; }
  fi

  # Enable and start iscsid
  if ! systemctl is-enabled iscsid &>/dev/null; then
    info "Enabling iscsid service."
    systemctl enable iscsid
  fi
  if ! systemctl is-active --quiet iscsid; then
    info "Starting iscsid service."
    systemctl start iscsid
  fi

  # Enable and start multipathd
  if ! systemctl is-enabled multipathd &>/dev/null; then
    info "Enabling multipathd service."
    systemctl enable multipathd
  fi
  if ! systemctl is-active --quiet multipathd; then
    info "Starting multipathd service."
    systemctl start multipathd
  fi

  success "NFS and block storage packages installed and services running."
}

# ── 9. Kubernetes node prerequisites ─────────────────────────────────────────
configure_k8s_prereqs() {
  info "Configuring Kubernetes node prerequisites..."

  # Disable swap (required by kubelet)
  swapoff -a
  sed -i "/ swap / s/^/#/" /etc/fstab
  success "Swap disabled."

  # Load required kernel modules
  modprobe overlay
  modprobe br_netfilter
  echo "overlay"      | tee /etc/modules-load.d/k8s.conf  >/dev/null
  echo "br_netfilter" | tee -a /etc/modules-load.d/k8s.conf >/dev/null
  success "Kernel modules overlay and br_netfilter loaded."

  # Apply required sysctl settings
  {
    echo "net.bridge.bridge-nf-call-iptables = 1"
    echo "net.bridge.bridge-nf-call-ip6tables = 1"
    echo "net.ipv4.ip_forward = 1"
  } | tee /etc/sysctl.d/k8s.conf >/dev/null
  sysctl --system &>/dev/null
  success "sysctl settings applied."

  # Disable firewall
  ufw disable
  success "ufw disabled."

  # Remove any pre-existing Kubernetes packages and repo list
  apt-get remove -y kubelet kubeadm kubectl kubernetes-cni >/dev/null 2>&1 || true
  rm -f /etc/apt/sources.list.d/kubernetes*.list
  success "Existing Kubernetes packages and repo list removed."

  apt-get update >/dev/null
  success "apt package lists refreshed."
}

# ── 10. Check internet/apt repo access ───────────────────────────────────────
check_apt_connectivity() {
  info "Checking apt repository connectivity..."

  if ! apt-get update -qq &>/dev/null; then
    fail "apt-get update failed. Check network connectivity and apt sources."
    return
  fi

  # Confirm nvidia-driver packages are available
  if ! apt-cache show nvidia-driver-535 &>/dev/null && \
     ! apt-cache search 'nvidia-driver-[0-9]' 2>/dev/null | grep -q .; then
    warn "No nvidia-driver packages found in apt sources. You may need to add the graphics-drivers PPA:"
    warn "  add-apt-repository ppa:graphics-drivers/ppa && apt-get update"
    return
  fi

  success "apt repositories are reachable and NVIDIA driver packages are available."
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  require_root

  echo ""
  echo "════════════════════════════════════════════════════"
  echo "  NVIDIA GPU Driver Preflight Check — Ubuntu"
  echo "════════════════════════════════════════════════════"
  echo ""

  check_ubuntu_version
  echo ""
  check_gpu_present
  echo ""
  check_kernel_headers
  echo ""
  check_build_tools
  echo ""
  check_secure_boot
  echo ""
  check_nouveau
  echo ""
  check_existing_driver
  echo ""
  configure_k8s_prereqs
  echo ""
  check_apt_connectivity
  echo ""
  install_storage_packages
  echo ""

  echo "════════════════════════════════════════════════════"
  if (( ERRORS > 0 )); then
    echo "  Preflight complete — ${ERRORS} issue(s) must be resolved before proceeding."
    echo "════════════════════════════════════════════════════"
    exit 1
  else
    echo "  Preflight complete — all checks passed."
    echo "════════════════════════════════════════════════════"
  fi
}

main "$@"
