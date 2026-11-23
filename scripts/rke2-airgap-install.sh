#!/usr/bin/env bash
# Install RKE2 from a pre-staged directory with no network access.
#
# The directory must hold the files published on an RKE2 GitHub release:
#   rke2.linux-<arch>.tar.gz
#   rke2-images.linux-<arch>.tar.zst   (or .tar.gz)
#   sha256sum-<arch>.txt
#   install.sh                          (from https://get.rke2.io)
#
# Every file is checked against sha256sum-<arch>.txt before anything is
# installed. Use --dry-run to verify and print the plan without changing the host.
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") --dir DIR [options]

  --dir DIR              staged artifact directory (required)
  --type server|agent    node role (default: server)
  --arch ARCH            amd64 or arm64 (default: amd64)
  --config FILE          RKE2 config.yaml to place in /etc/rancher/rke2
  --registries FILE      registries.yaml pointing mirrors at the private registry
  --no-start             install and enable the service but do not start it
  --dry-run              verify checksums and print actions only
  -h, --help             show this help
USAGE
}

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

STAGE_DIR=""
NODE_TYPE="server"
ARCH="amd64"
CONFIG_FILE=""
REGISTRIES_FILE=""
START=1
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) STAGE_DIR="${2:-}"; shift 2 ;;
    --type) NODE_TYPE="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --registries) REGISTRIES_FILE="${2:-}"; shift 2 ;;
    --no-start) START=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[ -n "$STAGE_DIR" ] || { usage >&2; die "--dir is required"; }
[ -d "$STAGE_DIR" ] || die "not a directory: $STAGE_DIR"
case "$NODE_TYPE" in server|agent) ;; *) die "--type must be server or agent" ;; esac
case "$ARCH" in amd64|arm64) ;; *) die "--arch must be amd64 or arm64" ;; esac
[ -z "$CONFIG_FILE" ] || [ -f "$CONFIG_FILE" ] || die "config not found: $CONFIG_FILE"
[ -z "$REGISTRIES_FILE" ] || [ -f "$REGISTRIES_FILE" ] || die "registries file not found: $REGISTRIES_FILE"

if command -v sha256sum >/dev/null 2>&1; then
  hash_of() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  hash_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  die "need sha256sum or shasum"
fi

SUMS="$STAGE_DIR/sha256sum-$ARCH.txt"
[ -f "$SUMS" ] || die "missing checksum file: $SUMS"
[ -f "$STAGE_DIR/install.sh" ] || die "missing install.sh in $STAGE_DIR"

TARBALL="$STAGE_DIR/rke2.linux-$ARCH.tar.gz"
[ -f "$TARBALL" ] || die "missing $TARBALL"

IMAGES=""
for candidate in "rke2-images.linux-$ARCH.tar.zst" "rke2-images.linux-$ARCH.tar.gz"; do
  if [ -f "$STAGE_DIR/$candidate" ]; then
    IMAGES="$STAGE_DIR/$candidate"
    break
  fi
done
[ -n "$IMAGES" ] || die "missing rke2-images.linux-$ARCH.tar.zst or .tar.gz in $STAGE_DIR"

verify_one() {
  local file="$1" name expected actual
  name="$(basename "$file")"
  expected="$(awk -v n="$name" '$2 == n || $2 == "*" n { print $1 }' "$SUMS" | head -n1)"
  [ -n "$expected" ] || die "$name is not listed in $(basename "$SUMS")"
  actual="$(hash_of "$file")"
  if [ "$expected" != "$actual" ]; then
    die "checksum mismatch for $name: expected $expected, got $actual"
  fi
  log "checksum ok: $name"
}

verify_one "$TARBALL"
verify_one "$IMAGES"

run() {
  log "+ $*"
  if [ "$DRY_RUN" -eq 0 ]; then
    "$@"
  fi
}

if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  die "run as root, or use --dry-run"
fi

IMAGES_DIR="/var/lib/rancher/rke2/agent/images"
CONF_DIR="/etc/rancher/rke2"
SERVICE="rke2-$NODE_TYPE.service"

run mkdir -p "$IMAGES_DIR" "$CONF_DIR"
run cp "$IMAGES" "$IMAGES_DIR/"
if [ -n "$CONFIG_FILE" ]; then
  run install -m 0600 "$CONFIG_FILE" "$CONF_DIR/config.yaml"
fi
if [ -n "$REGISTRIES_FILE" ]; then
  run install -m 0600 "$REGISTRIES_FILE" "$CONF_DIR/registries.yaml"
fi

log "+ INSTALL_RKE2_ARTIFACT_PATH=$STAGE_DIR INSTALL_RKE2_TYPE=$NODE_TYPE sh $STAGE_DIR/install.sh"
if [ "$DRY_RUN" -eq 0 ]; then
  INSTALL_RKE2_ARTIFACT_PATH="$STAGE_DIR" INSTALL_RKE2_TYPE="$NODE_TYPE" sh "$STAGE_DIR/install.sh"
fi

run systemctl enable "$SERVICE"
if [ "$START" -eq 1 ]; then
  run systemctl start "$SERVICE"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry run complete, nothing was changed"
else
  log "rke2 $NODE_TYPE installed"
fi
