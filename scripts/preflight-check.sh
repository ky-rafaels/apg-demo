#!/usr/bin/env bash
# prereq-check.sh — Ensure NKP node prerequisites on Ubuntu 22.04
# Run as root or with sudo

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
NUTANIX_USER="${NUTANIX_USER:-nutanix}"
NUTANIX_PUBKEY_FILE="${NUTANIX_PUBKEY_FILE:-}"   # Set via env or prompted at runtime
LOG_PREFIX="[prereq]"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo "${LOG_PREFIX} INFO:  $*"; }
success() { echo "${LOG_PREFIX} OK:    $*"; }
warn()    { echo "${LOG_PREFIX} WARN:  $*"; }
die()     { echo "${LOG_PREFIX} ERROR: $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root (or via sudo)."
}

# ── 1. Disable swap permanently ───────────────────────────────────────────────
ensure_swap_disabled() {
  info "Checking swap..."

  # Turn off any active swap immediately
  if swapon --show | grep -q .; then
    warn "Swap is currently active — disabling now."
    swapoff -a
  fi

  # Remove or comment out all swap entries in /etc/fstab
  if grep -qE '^\s*[^#].*\bswap\b' /etc/fstab; then
    warn "Found active swap entries in /etc/fstab — commenting out."
    sed -i.bak -E 's|^(\s*[^#].*\bswap\b.*)|# \1  # disabled by prereq-check|' /etc/fstab
  fi

  # Disable and mask the systemd swap target so it can't come back on reboot
  if systemctl is-enabled swap.target &>/dev/null; then
    systemctl disable --now swap.target 2>/dev/null || true
  fi
  systemctl mask swap.target 2>/dev/null || true

  success "Swap is disabled and masked."
}

# ── 2. Create nutanix user with passwordless sudo ─────────────────────────────
ensure_nutanix_user() {
  info "Checking user '${NUTANIX_USER}'..."

  if ! id "${NUTANIX_USER}" &>/dev/null; then
    info "User '${NUTANIX_USER}' not found — creating."
    useradd \
      --create-home \
      --shell /bin/bash \
      --comment "NKP service account" \
      "${NUTANIX_USER}"
  else
    success "User '${NUTANIX_USER}' already exists."
  fi

  # Write a dedicated sudoers drop-in (safer than editing /etc/sudoers directly)
  local sudoers_file="/etc/sudoers.d/99-${NUTANIX_USER}"
  local sudoers_line="${NUTANIX_USER} ALL=(ALL) NOPASSWD:ALL"

  if [[ ! -f "${sudoers_file}" ]] || ! grep -qF "${sudoers_line}" "${sudoers_file}"; then
    info "Configuring passwordless sudo for '${NUTANIX_USER}'."
    echo "${sudoers_line}" > "${sudoers_file}"
    chmod 0440 "${sudoers_file}"
    # Validate the file before committing
    visudo -cf "${sudoers_file}" || die "sudoers syntax check failed — aborting."
  fi

  success "User '${NUTANIX_USER}' has passwordless sudo."
}

# ── 3. Configure SSH public key authentication ────────────────────────────────
ensure_ssh_pubkey() {
  info "Checking SSH public key authentication..."

  # Prompt for key path if not provided via environment
  if [[ -z "${NUTANIX_PUBKEY_FILE}" ]]; then
    read -r -p "Path to SSH public key file for '${NUTANIX_USER}': " NUTANIX_PUBKEY_FILE
  fi

  [[ -n "${NUTANIX_PUBKEY_FILE}" ]]  || die "No public key file path provided."
  [[ -f "${NUTANIX_PUBKEY_FILE}" ]]  || die "Public key file not found: ${NUTANIX_PUBKEY_FILE}"
  [[ -r "${NUTANIX_PUBKEY_FILE}" ]]  || die "Public key file is not readable: ${NUTANIX_PUBKEY_FILE}"

  local pubkey
  pubkey="$(cat "${NUTANIX_PUBKEY_FILE}")"
  [[ -n "${pubkey}" ]] || die "Public key file is empty: ${NUTANIX_PUBKEY_FILE}"

  local ssh_dir="/home/${NUTANIX_USER}/.ssh"
  local auth_keys="${ssh_dir}/authorized_keys"

  if [[ ! -d "${ssh_dir}" ]]; then
    install -d -m 700 -o "${NUTANIX_USER}" -g "${NUTANIX_USER}" "${ssh_dir}"
  fi

  if ! grep -qF "${pubkey}" "${auth_keys}" 2>/dev/null; then
    info "Adding public key to ${auth_keys}."
    echo "${pubkey}" >> "${auth_keys}"
  fi

  chmod 600 "${auth_keys}"
  chown "${NUTANIX_USER}:${NUTANIX_USER}" "${auth_keys}"

  local sshd_cfg="/etc/ssh/sshd_config"
  if grep -qE '^\s*#?\s*PubkeyAuthentication\s+no' "${sshd_cfg}"; then
    warn "PubkeyAuthentication is disabled in sshd_config — enabling."
    sed -i -E 's|^\s*#?\s*(PubkeyAuthentication)\s+no|\1 yes|' "${sshd_cfg}"
    systemctl reload ssh
  elif ! grep -qE '^\s*PubkeyAuthentication\s+yes' "${sshd_cfg}"; then
    info "PubkeyAuthentication not explicitly set — appending to sshd_config."
    echo "PubkeyAuthentication yes" >> "${sshd_cfg}"
    systemctl reload ssh
  fi

  success "SSH public key authentication is configured."
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  require_root

  echo ""
  echo "════════════════════════════════════════════"
  echo "  NKP Node Prerequisites — Ubuntu 22.04"
  echo "════════════════════════════════════════════"
  echo ""

  ensure_swap_disabled
  echo ""
  ensure_nutanix_user
  echo ""
  ensure_ssh_pubkey
  echo ""

  echo "════════════════════════════════════════════"
  echo "  All prerequisites satisfied."
  echo "════════════════════════════════════════════"
}

main "$@"
