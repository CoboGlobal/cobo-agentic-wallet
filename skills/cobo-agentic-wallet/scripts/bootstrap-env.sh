#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for local onboarding:
# - Download caw and TSS assets in parallel (only; onboard is run via caw in the skill)

# caw: Cobo Agentic Wallet binary release (tar.gz). Package: caw-{version}-{os}-{arch}.tar.gz
# Bucket: cobo-agenticwallet, path: /binary-release/0.1.0/ (linux-amd64, linux-arm64; darwin when published)
CAW_BASE_URL="${CAW_BASE_URL:-https://download.agenticwallet.cobo.com/binary-release}"
CAW_VERSION="${CAW_VERSION:-v0.2.5}"
# TSS Node: Cobo download (tar.gz)
TSS_BASE_URL="${TSS_BASE_URL:-https://download.tss.cobo.com/binary-release/latest}"
ENV_NAME="${ENV_NAME:-prod}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.cobo-agentic-wallet}"
BIN_DIR="${BIN_DIR:-$INSTALL_ROOT/bin}"
CACHE_TSS_DIR="${CACHE_TSS_DIR:-$INSTALL_ROOT/cache/tss-node}"
LOG_DIR="${LOG_DIR:-$INSTALL_ROOT/logs}"
FORCE_DOWNLOAD=false
PRINT_WAITLIST_CURL=false
# Replaced per-environment by sync_env_skills.py; default to sandbox for direct use
WAITLIST_URL="${WAITLIST_API_URL:-https://api-assistant.agenticwallet.cobo.com/api/v1/waitlist/apply}"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-env.sh [--env prod] [--base-url URL] [--caw-version VER] [--force-download] [--print-waitlist-curl]

Options:
  --env               Cobo environment (sandbox/dev/prod), default: prod
  --base-url          TSS Node base URL (default: https://download.tss.cobo.com/binary-release/latest)
  --caw-version       caw package version (default: 0.1.0). Path: {base}/{ver}/caw-{ver}-{os}-{arch}.tar.gz
  --force-download    Always download (ignore existing caw and tss-node)
  --print-waitlist-curl  Print curl command for waitlist apply and exit

Download sources:
  caw:  https://cobo-agenticwallet.s3.us-west-2.amazonaws.com/binary-release/{ver}/caw-{ver}-{os}-{arch}.tar.gz
  TSS:  https://download.tss.cobo.com/binary-release/latest/cobo-tss-node-{os}-{arch}.tar.gz

Examples:
  bootstrap-env.sh --env prod
  bootstrap-env.sh --env prod --caw-version 0.1.0
  bootstrap-env.sh --env prod --print-waitlist-curl
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_NAME="$2"
      shift 2
      ;;
    --base-url)
      TSS_BASE_URL="$2"
      shift 2
      ;;
    --caw-version)
      CAW_VERSION="$2"
      shift 2
      ;;
    --force-download)
      FORCE_DOWNLOAD=true
      shift 1
      ;;
    --print-waitlist-curl)
      PRINT_WAITLIST_CURL=true
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$PRINT_WAITLIST_CURL" == "true" ]]; then
  echo "curl -X POST \"$WAITLIST_URL\" \\"
  echo "  -H \"Content-Type: application/json\" \\"
  echo "  -d '{\"agent_name\":\"YOUR_AGENT_NAME\",\"agent_description\":\"Brief description\",\"email\":\"user@example.com\",\"telegram\":\"@handle\"}'"
  exit 0
fi

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux|darwin) ;;
    *)
      echo "Unsupported OS: $os" >&2
      exit 1
      ;;
  esac
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "Unsupported architecture: $arch" >&2
      exit 1
      ;;
  esac
  printf "%s %s\n" "$os" "$arch"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

download_with_resume() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  curl --fail --location --silent --show-error --continue-at - --output "$dest" "$url"
}

fetch_remote_meta() {
  local url="$1"
  local headers
  headers="$(curl --fail --silent --show-error --location --head "$url" 2>/dev/null | tr -d '\r')" || return 1

  local etag last_modified content_length
  etag="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^etag:/ {sub(/^[^:]*:[[:space:]]*/, "", $0); v=$0} END{print v}')"
  last_modified="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^last-modified:/ {sub(/^[^:]*:[[:space:]]*/, "", $0); v=$0} END{print v}')"
  content_length="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^content-length:/ {sub(/^[^:]*:[[:space:]]*/, "", $0); v=$0} END{print v}')"
  printf '%s\t%s\t%s\n' "$etag" "$last_modified" "$content_length"
}

write_meta_file() {
  local meta_file="$1"
  local source_url="$2"
  local etag="$3"
  local last_modified="$4"
  local content_length="$5"
  mkdir -p "$(dirname "$meta_file")"
  cat >"$meta_file" <<EOF
SOURCE_URL=$source_url
ETAG=$etag
LAST_MODIFIED=$last_modified
CONTENT_LENGTH=$content_length
EOF
}

should_download_artifact() {
  local target_path="$1"
  local label="$2"

  if [[ "$FORCE_DOWNLOAD" == "true" ]]; then
    return 0
  fi
  if [[ -f "$target_path" ]]; then
    return 1
  fi
  return 0
}

extract_caw_assets() {
  local tarball="$1"
  local dest_dir="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  tar -xzf "$tarball" -C "$tmp_dir"

  local caw_bin
  caw_bin="$(find "$tmp_dir" -type f \( -name "caw" -o -name "caw.exe" \) | head -n 1)"
  if [[ -z "$caw_bin" ]]; then
    # fallback: caw-darwin-arm64 style
    caw_bin="$(find "$tmp_dir" -type f -name "caw-*" ! -name "*.sha256" | head -n 1)"
  fi
  if [[ -z "$caw_bin" ]]; then
    echo "caw binary not found in tarball" >&2
    exit 1
  fi

  mkdir -p "$dest_dir"
  cp "$caw_bin" "$dest_dir/caw"
  chmod 755 "$dest_dir/caw"
}

extract_tss_assets() {
  local tarball="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  tar -xzf "$tarball" -C "$tmp_dir"

  local tss_bin
  tss_bin="$(find "$tmp_dir" -type f -name "cobo-tss-node" | head -n 1)"
  if [[ -z "$tss_bin" ]]; then
    echo "cobo-tss-node binary not found in tarball" >&2
    exit 1
  fi

  mkdir -p "$CACHE_TSS_DIR"
  cp "$tss_bin" "$CACHE_TSS_DIR/cobo-tss-node"
  chmod 755 "$CACHE_TSS_DIR/cobo-tss-node"
  sha256_file "$CACHE_TSS_DIR/cobo-tss-node" > "$CACHE_TSS_DIR/cobo-tss-node.sha256"
  chmod 600 "$CACHE_TSS_DIR/cobo-tss-node.sha256"

  local tpl
  tpl="$(find "$tmp_dir" -type f -name "*.yaml.template" ! -name "._*" | head -n 1 || true)"
  if [[ -n "$tpl" ]]; then
    mkdir -p "$CACHE_TSS_DIR/configs"
    cp "$tpl" "$CACHE_TSS_DIR/configs/cobo-tss-node-config.yaml.template"
    cp "$tpl" "$CACHE_TSS_DIR/configs/cobo-tss-node-config.yaml"
    sha256_file "$CACHE_TSS_DIR/configs/cobo-tss-node-config.yaml.template" > "$CACHE_TSS_DIR/configs/cobo-tss-node-config.yaml.template.sha256"
    sha256_file "$CACHE_TSS_DIR/configs/cobo-tss-node-config.yaml" > "$CACHE_TSS_DIR/configs/cobo-tss-node-config.yaml.sha256"
    chmod 600 "$CACHE_TSS_DIR/configs/"*.sha256
  fi
}

wait_job_or_fail() {
  local pid="$1"
  local log_path="$2"
  local label="$3"
  if ! wait "$pid"; then
    echo "[ERROR] ${label} failed. See log: ${log_path}" >&2
    exit 1
  fi
}

main() {
  read -r os arch < <(detect_platform)
  mkdir -p "$BIN_DIR" "$LOG_DIR" "$CACHE_TSS_DIR"

  # Early exit: if both caw and tss-node exist and no force-download, skip download
  if [[ "$FORCE_DOWNLOAD" != "true" ]]; then
    if [[ -x "$BIN_DIR/caw" ]] && [[ -x "$CACHE_TSS_DIR/cobo-tss-node" ]]; then
      echo "ready"
      exit 0
    fi
  fi

  local caw_url="${CAW_BASE_URL}/${CAW_VERSION}/caw-${os}-${arch}-${CAW_VERSION}.tar.gz"
  echo "caw url: ${caw_url}"
  local tss_url="${TSS_BASE_URL}/cobo-tss-node-${os}-${arch}.tar.gz"

  local caw_log="$LOG_DIR/caw-download.log"
  local tss_log="$LOG_DIR/tss-prewarm.log"
  local caw_meta="$BIN_DIR/caw.meta"
  local tss_meta="$CACHE_TSS_DIR/tss.meta"

  echo "      force=${FORCE_DOWNLOAD}"

  echo "[1/3] Start parallel download (caw + TSS)..."
  (
    set -euo pipefail
    if should_download_artifact "$BIN_DIR/caw" "caw"; then
      local caw_tmp_tar caw_remote_meta caw_etag caw_last_modified caw_content_length
      caw_remote_meta="$(fetch_remote_meta "$caw_url" || true)"
      IFS=$'\t' read -r caw_etag caw_last_modified caw_content_length <<<"${caw_remote_meta:-}"
      caw_tmp_tar="$(mktemp)"
      trap 'rm -f "$caw_tmp_tar"' EXIT
      download_with_resume "$caw_url" "$caw_tmp_tar"
      extract_caw_assets "$caw_tmp_tar" "$BIN_DIR"
      write_meta_file "$caw_meta" "$caw_url" "${caw_etag:-}" "${caw_last_modified:-}" "${caw_content_length:-}"
      echo "[DONE] caw downloaded to $BIN_DIR/caw"
    else
      echo "[DONE] caw reuse local binary at $BIN_DIR/caw"
    fi
  ) >"$caw_log" 2>&1 &
  local caw_pid=$!

  (
    set -euo pipefail
    if should_download_artifact "$CACHE_TSS_DIR/cobo-tss-node" "tss"; then
      local tss_tmp_tar
      local tss_remote_meta tss_etag tss_last_modified tss_content_length
      tss_remote_meta="$(fetch_remote_meta "$tss_url" || true)"
      IFS=$'\t' read -r tss_etag tss_last_modified tss_content_length <<<"${tss_remote_meta:-}"
      tss_tmp_tar="$(mktemp)"
      trap 'rm -f "$tss_tmp_tar"' EXIT
      download_with_resume "$tss_url" "$tss_tmp_tar"
      extract_tss_assets "$tss_tmp_tar"
      write_meta_file "$tss_meta" "$tss_url" "${tss_etag:-}" "${tss_last_modified:-}" "${tss_content_length:-}"
      echo "[DONE] Shared TSS cache downloaded at $CACHE_TSS_DIR"
    else
      echo "[DONE] Shared TSS cache reuse local assets at $CACHE_TSS_DIR"
    fi
  ) >"$tss_log" 2>&1 &
  local tss_pid=$!

  echo "      caw pid=${caw_pid}, log=${caw_log}"
  echo "      tss pid=${tss_pid}, log=${tss_log}"

  echo "[2/3] Waiting for prework to complete..."
  wait_job_or_fail "$caw_pid" "$caw_log" "caw download"
  wait_job_or_fail "$tss_pid" "$tss_log" "tss prewarm"

  echo "[3/3] Done. caw at $BIN_DIR/caw, TSS at $CACHE_TSS_DIR"
}

main "$@"
