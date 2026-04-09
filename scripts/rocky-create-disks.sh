#!/usr/bin/env bash
# lvm-setup.sh — Create a VG and 10 LVs from a single disk/partition
# Target: Rocky Linux 9.6
# Run as root or with sudo

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
DEVICE="${DEVICE:-/dev/nvme0n1p4}"   # Partition to use
VG_NAME="${VG_NAME:-vg_nkp}"         # Volume group name
LV_COUNT="${LV_COUNT:-10}"           # Number of logical volumes
LV_PREFIX="${LV_PREFIX:-lv_data}"    # LV name prefix (lv_data_01..10)
LV_SIZE="${LV_SIZE:-}"               # Leave empty to auto-divide equally
FS_TYPE="${FS_TYPE:-ext4}"           # Filesystem type (ext4 or xfs)
MOUNT_BASE="${MOUNT_BASE:-/mnt/nkp}" # Mount point base path
LOG_PREFIX="[lvm-setup]"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo "${LOG_PREFIX} INFO:  $*"; }
success() { echo "${LOG_PREFIX} OK:    $*"; }
warn()    { echo "${LOG_PREFIX} WARN:  $*"; }
die()     { echo "${LOG_PREFIX} ERROR: $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root (or via sudo)."
}

# ── Preflight checks ──────────────────────────────────────────────────────────
preflight() {
  info "Running preflight checks..."

  [[ -b "${DEVICE}" ]] || die "Device not found or not a block device: ${DEVICE}"

  # Warn if device is already in use
  if pvs "${DEVICE}" &>/dev/null; then
    die "${DEVICE} is already a PV. Refusing to proceed — set DEVICE to a different partition."
  fi

  if mount | grep -q "${DEVICE}"; then
    die "${DEVICE} is currently mounted. Unmount it before running this script."
  fi

  # Install lvm2 if missing
  if ! rpm -q lvm2 &>/dev/null; then
    info "lvm2 not installed — installing."
    dnf install -y lvm2
  fi

  success "Preflight passed."
}

# ── Create PV and VG ──────────────────────────────────────────────────────────
create_vg() {
  info "Creating physical volume on ${DEVICE}..."
  pvcreate -ff -y "${DEVICE}"
  success "PV created: ${DEVICE}"

  info "Creating volume group '${VG_NAME}'..."
  vgcreate "${VG_NAME}" "${DEVICE}"
  success "VG created: ${VG_NAME}"
}

# ── Calculate LV size ─────────────────────────────────────────────────────────
calc_lv_size() {
  if [[ -n "${LV_SIZE}" ]]; then
    info "Using specified LV size: ${LV_SIZE}"
    return
  fi

  # Get free PE count and PE size, divide equally across LV_COUNT
  local free_pe pe_size_kb total_kb lv_kb
  free_pe=$(vgs --noheadings --units k -o vg_free_count "${VG_NAME}" | tr -d ' ')
  pe_size_kb=$(vgs --noheadings --units k -o vg_extent_size "${VG_NAME}" | tr -d ' k')

  # Reserve 1% of PEs for metadata headroom
  local usable_pe=$(( free_pe * 99 / 100 ))
  local lv_pe=$(( usable_pe / LV_COUNT ))

  total_kb=$(( lv_pe * ${pe_size_kb%.*} ))
  LV_SIZE="${total_kb}K"

  info "Auto-calculated LV size: ${LV_SIZE} (${lv_pe} PEs each, ${LV_COUNT} LVs)"
}

# ── Create LVs, format, and mount ─────────────────────────────────────────────
create_lvs() {
  for i in $(seq -f "%02g" 1 "${LV_COUNT}"); do
    local lv_name="${LV_PREFIX}_${i}"
    local mount_point="${MOUNT_BASE}/${lv_name}"
    local lv_path="/dev/${VG_NAME}/${lv_name}"

    info "Creating LV: ${lv_name} (${LV_SIZE})"
    lvcreate -L "${LV_SIZE}" -n "${lv_name}" "${VG_NAME}"

    info "Formatting ${lv_path} as ${FS_TYPE}..."
    case "${FS_TYPE}" in
      ext4) mkfs.ext4 -q "${lv_path}" ;;
      xfs)  mkfs.xfs  -q "${lv_path}" ;;
      *)    die "Unsupported filesystem type: ${FS_TYPE}" ;;
    esac

    info "Mounting at ${mount_point}..."
    mkdir -p "${mount_point}"
    mount "${lv_path}" "${mount_point}"

    # Add to /etc/fstab for persistence across reboots
    local uuid
    uuid=$(blkid -s UUID -o value "${lv_path}")
    local fstab_entry="UUID=${uuid}  ${mount_point}  ${FS_TYPE}  defaults  0 0"

    if ! grep -qF "${uuid}" /etc/fstab; then
      echo "${fstab_entry}" >> /etc/fstab
      info "Added to /etc/fstab: ${fstab_entry}"
    fi

    success "LV ready: ${lv_path} → ${mount_point}"
    echo ""
  done
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  echo "════════════════════════════════════════════"
  echo "  LVM Setup Complete"
  echo "════════════════════════════════════════════"
  echo ""
  vgs "${VG_NAME}"
  echo ""
  lvs "${VG_NAME}"
  echo ""
  df -h "${MOUNT_BASE}"/*/
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  require_root
  preflight

  echo ""
  echo "════════════════════════════════════════════"
  echo "  LVM Setup — Rocky Linux 9.6"
  echo "  Device : ${DEVICE}"
  echo "  VG     : ${VG_NAME}"
  echo "  LVs    : ${LV_COUNT}x ${LV_PREFIX}_NN"
  echo "  FS     : ${FS_TYPE}"
  echo "  Mount  : ${MOUNT_BASE}/<lv_name>"
  echo "════════════════════════════════════════════"
  echo ""

  create_vg
  echo ""
  calc_lv_size
  echo ""
  create_lvs
  print_summary
}

main "$@"