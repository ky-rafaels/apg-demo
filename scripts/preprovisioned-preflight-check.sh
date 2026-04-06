#!/usr/bin/env bash
# prereq-check.sh — Ensure NKP/Konvoy node prerequisites on Ubuntu 22.04
# Run as root or with sudo

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
KONVOY_USER="${KONVOY_USER:-konvoy}"
KONVOY_PUBKEY="${KONVOY_PUBKEY:-}"          # Set via env or prompted at runtime
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

# ── 2. Create konvoy user with passwordless sudo ──────────────────────────────
ensure_konvoy_user() {
  info "Checking user '${KONVOY_USER}'..."

  if ! id "${KONVOY_USER}" &>/dev/null; then
    info "User '${KONVOY_USER}' not found — creating."
    useradd \
      --create-home \
      --shell /bin/bash \
      --comment "NKP Konvoy service account" \
      "${KONVOY_USER}"
  else
    success "User '${KONVOY_USER}' already exists."
  fi

  # Write a dedicated sudoers drop-in (safer than editing /etc/sudoers directly)
  local sudoers_file="/etc/sudoers.d/99-${KONVOY_USER}"
  local sudoers_line="${KONVOY_USER} ALL=(ALL) NOPASSWD:ALL"

  if [[ ! -f "${sudoers_file}" ]] || ! grep -qF "${sudoers_line}" "${sudoers_file}"; then
    info "Configuring passwordless sudo for '${KONVOY_USER}'."
    echo "${sudoers_line}" > "${sudoers_file}"
    chmod 0440 "${sudoers_file}"
    # Validate the file before committing
    visudo -cf "${sudoers_file}" || die "sudoers syntax check failed — aborting."
  fi

  success "User '${KONVOY_USER}' has passwordless sudo."
}

# ── 3. Configure SSH public key authentication ────────────────────────────────
ensure_ssh_pubkey() {
  info "Checking SSH public key authentication..."

  # Prompt for key path if not provided via environment
  if [[ -z "${KONVOY_PUBKEY_FILE}" ]]; then
    read -r -p "Path to SSH public key file for '${KONVOY_USER}': " KONVOY_PUBKEY_FILE
  fi

  [[ -n "${KONVOY_PUBKEY_FILE}" ]]  || die "No public key file path provided."
  [[ -f "${KONVOY_PUBKEY_FILE}" ]]  || die "Public key file not found: ${KONVOY_PUBKEY_FILE}"
  [[ -r "${KONVOY_PUBKEY_FILE}" ]]  || die "Public key file is not readable: ${KONVOY_PUBKEY_FILE}"

  local pubkey
  pubkey="$(cat "${KONVOY_PUBKEY_FILE}")"
  [[ -n "${pubkey}" ]] || die "Public key file is empty: ${KONVOY_PUBKEY_FILE}"

  local ssh_dir="/home/${KONVOY_USER}/.ssh"
  local auth_keys="${ssh_dir}/authorized_keys"

  if [[ ! -d "${ssh_dir}" ]]; then
    install -d -m 700 -o "${KONVOY_USER}" -g "${KONVOY_USER}" "${ssh_dir}"
  fi

  if ! grep -qF "${pubkey}" "${auth_keys}" 2>/dev/null; then
    info "Adding public key to ${auth_keys}."
    echo "${pubkey}" >> "${auth_keys}"
  fi

  chmod 600 "${auth_keys}"
  chown "${KONVOY_USER}:${KONVOY_USER}" "${auth_keys}"

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

# ── 4. Enable iSCSI daemon ────────────────────────────────────────────────────
ensure_iscsi() {
  info "Checking iSCSI daemon (iscsid)..."

  # Install open-iscsi if missing
  if ! dpkg -l open-iscsi 2>/dev/null | grep -q '^ii'; then
    info "open-iscsi not installed — installing."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y open-iscsi
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

  success "iSCSI daemon is enabled and running."
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
  ensure_konvoy_user
  echo ""
  ensure_ssh_pubkey
  echo ""
  ensure_iscsi
  echo ""

  echo "════════════════════════════════════════════"
  echo "  All prerequisites satisfied."
  echo "════════════════════════════════════════════"
}

main "$@"