#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for local onboarding:
# - Download caw and TSS assets in parallel (only; onboard is run via caw in the skill)

# caw: Cobo Agentic Wallet binary release (tar.gz). Package: caw-{version}-{os}-{arch}.tar.gz
# Bucket: cobo-agenticwallet, path: /binary-release/0.1.0/ (linux-amd64, linux-arm64; darwin when published)
CAW_BASE_URL="${CAW_BASE_URL:-https://download.agenticwallet.cobo.com/binary-release}"
CAW_VERSION="${CAW_VERSION:-v0.2.84}"
# TSS Node: Cobo download (tar.gz)
TSS_BASE_URL="${TSS_BASE_URL:-https://download.tss.cobo.com/binary-release/latest}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.cobo-agentic-wallet}"
BIN_DIR="${BIN_DIR:-$INSTALL_ROOT/bin}"
CACHE_TSS_DIR="${CACHE_TSS_DIR:-$INSTALL_ROOT/cache/tss-node}"
LOG_DIR="${LOG_DIR:-$INSTALL_ROOT/logs}"
FORCE_DOWNLOAD=false
DOWNLOAD_ONLY="all"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-env.sh [--base-url URL] [--caw-version VER] [--only all|caw|tss] [--force-download]

Options:
  --base-url          TSS Node base URL (default: https://download.tss.cobo.com/binary-release/latest)
  --caw-version       caw version to install (default: latest). Use 'latest' for the latest release or a specific version like v0.2.30.
  --only              Download scope: all (default), caw, tss
  --force-download    Always download (ignore existing caw and tss-node)

Download sources:
  caw:  https://download.agenticwallet.cobo.com/binary-release/latest/caw-{os}-{arch}.tar.gz  (latest)
        https://download.agenticwallet.cobo.com/binary-release/{ver}/caw-{os}-{arch}-{ver}.tar.gz  (specific version)
  TSS:  https://download.tss.cobo.com/binary-release/latest/cobo-tss-node-{os}-{arch}.tar.gz

Examples:
  bootstrap-env.sh
  bootstrap-env.sh --caw-version v0.2.14
  bootstrap-env.sh --only caw
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      TSS_BASE_URL="$2"
      shift 2
      ;;
    --caw-version)
      CAW_VERSION="$2"
      shift 2
      ;;
    --only)
      DOWNLOAD_ONLY="$2"
      shift 2
      ;;
    --force-download)
      FORCE_DOWNLOAD=true
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

case "$DOWNLOAD_ONLY" in
  all|caw|tss) ;;
  *)
    echo "Invalid --only value: $DOWNLOAD_ONLY (expected: all, caw, tss)" >&2
    exit 1
    ;;
esac

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

local_caw_version_matches() {
  local caw_bin="$1"
  local want="$2"
  [[ -x "$caw_bin" ]] || return 1
  local got
  got="$("$caw_bin" version 2>&1)" || return 1
  got="$(echo "$got" | awk '{print $NF}')"
  [[ "$got" == "$want" ]]
}

should_download_artifact() {
  local target_path="$1"
  local label="$2"

  if [[ "$FORCE_DOWNLOAD" == "true" ]]; then
    return 0
  fi
  if [[ "$label" == "caw" ]]; then
    if [[ "$CAW_VERSION" == "latest" ]]; then
      # For latest, just check the binary exists (version is unknown before download)
      [[ -x "$target_path" ]] && return 1 || return 0
    else
      local_caw_version_matches "$target_path" "$CAW_VERSION" && return 1 || return 0
    fi
  fi
  [[ -f "$target_path" ]] && return 1 || return 0
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

# get_link_dir — returns the directory where the `caw` symlink will be placed.
#
# Priority:
#   $CAW_LINK_DIR (env override) → use as-is
#   Linux root                   → /usr/local/bin  (FHS, already on PATH)
#   Everyone else                → $HOME/.local/bin
get_link_dir() {
  if [[ -n "${CAW_LINK_DIR:-}" ]]; then
    echo "$CAW_LINK_DIR"
    return
  fi
  if [[ "$(uname -s)" == "Linux" ]] && [[ "$(id -u)" -eq 0 ]]; then
    echo "/usr/local/bin"
  else
    echo "$HOME/.local/bin"
  fi
}

# _PATH_SHELL_UPDATED is set to true by setup_path() when it writes a new
# PATH entry into a shell config file (i.e. link_dir was not already on PATH).
_PATH_SHELL_UPDATED=false

# setup_path — symlinks $BIN_DIR/caw into a PATH-accessible directory and,
# if that directory is not already on PATH, appends an export line to the
# user's shell config file(s).
setup_path() {
  local link_dir
  link_dir="$(get_link_dir)"

  mkdir -p "$link_dir"
  ln -sf "$BIN_DIR/caw" "$link_dir/caw"
  echo "Linked: $link_dir/caw → $BIN_DIR/caw"

  # /usr/local/bin is always on PATH on Linux root — nothing more to do.
  if [[ "$link_dir" == "/usr/local/bin" ]]; then
    export PATH="$link_dir:$PATH"
    return 0
  fi

  # Check if link_dir is already on PATH *before* we modify $PATH.
  if echo ":${PATH}:" | grep -q ":${link_dir}:"; then
    echo "$link_dir is already on PATH"
    export PATH="$link_dir:$PATH"
    return 0
  fi

  # link_dir is not on PATH — update shell config files.
  local login_shell
  login_shell="$(basename "${SHELL:-bash}")"
  local path_line="export PATH=\"$link_dir:\$PATH\""
  local path_comment="# caw CLI"

  case "$login_shell" in
    zsh)
      local configs=()
      [[ -f "$HOME/.zshrc" ]]    && configs+=("$HOME/.zshrc")
      [[ -f "$HOME/.zprofile" ]] && configs+=("$HOME/.zprofile")
      [[ ${#configs[@]} -eq 0 ]] && { touch "$HOME/.zshrc"; configs+=("$HOME/.zshrc"); }
      for cfg in "${configs[@]}"; do
        _append_path_to_config "$cfg" "$link_dir" "$path_line" "$path_comment"
      done
      ;;
    fish)
      local fish_config="$HOME/.config/fish/config.fish"
      mkdir -p "$(dirname "$fish_config")"
      touch "$fish_config"
      if ! grep -q "fish_add_path.*$link_dir" "$fish_config" 2>/dev/null; then
        printf '\n%s\nfish_add_path "%s"\n' "$path_comment" "$link_dir" >> "$fish_config"
        echo "Added $link_dir to PATH in $fish_config"
      fi
      ;;
    bash|*)
      local configs=()
      [[ -f "$HOME/.bashrc" ]]       && configs+=("$HOME/.bashrc")
      [[ -f "$HOME/.bash_profile" ]] && configs+=("$HOME/.bash_profile")
      for cfg in "${configs[@]}"; do
        _append_path_to_config "$cfg" "$link_dir" "$path_line" "$path_comment"
      done
      ;;
  esac

  # Also update ~/.profile, which is sourced by login shells on most distros.
  [[ -f "$HOME/.profile" ]] && _append_path_to_config "$HOME/.profile" "$link_dir" "$path_line" "$path_comment"

  _PATH_SHELL_UPDATED=true
  export PATH="$link_dir:$PATH"
}

# _append_path_to_config FILE LINK_DIR PATH_LINE COMMENT
# Appends PATH_LINE to FILE if LINK_DIR is not already mentioned there.
_append_path_to_config() {
  local cfg="$1" link_dir="$2" path_line="$3" comment="$4"
  if ! grep -v '^[[:space:]]*#' "$cfg" 2>/dev/null | grep -q "$link_dir"; then
    printf '\n%s\n%s\n' "$comment" "$path_line" >> "$cfg"
    echo "Added $link_dir to PATH in $cfg"
  fi
}

main() {
  read -r os arch < <(detect_platform)
  mkdir -p "$BIN_DIR" "$LOG_DIR" "$CACHE_TSS_DIR"

  # Build caw download URL: latest uses bare filename, specific version includes version suffix
  local caw_url
  if [[ "$CAW_VERSION" == "latest" ]]; then
    caw_url="${CAW_BASE_URL}/latest/caw-${os}-${arch}.tar.gz"
  else
    caw_url="${CAW_BASE_URL}/${CAW_VERSION}/caw-${os}-${arch}-${CAW_VERSION}.tar.gz"
  fi
  echo "caw url: ${caw_url}"

  # caw_ready: true when existing binary satisfies the version requirement
  local caw_ready=false
  if [[ "$CAW_VERSION" == "latest" ]]; then
    [[ -x "$BIN_DIR/caw" ]] && caw_ready=true
  else
    local_caw_version_matches "$BIN_DIR/caw" "$CAW_VERSION" && caw_ready=true || true
  fi

  # Early exit: required assets already present, no force-download.
  if [[ "$FORCE_DOWNLOAD" != "true" ]]; then
    case "$DOWNLOAD_ONLY" in
      all)
        if [[ "$caw_ready" == "true" ]] && [[ -x "$CACHE_TSS_DIR/cobo-tss-node" ]]; then
          echo "ready"
          exit 0
        fi
        ;;
      caw)
        if [[ "$caw_ready" == "true" ]]; then
          echo "ready"
          exit 0
        fi
        ;;
      tss)
        if [[ -x "$CACHE_TSS_DIR/cobo-tss-node" ]]; then
          echo "ready"
          exit 0
        fi
        ;;
    esac
  fi
  local tss_url="${TSS_BASE_URL}/cobo-tss-node-${os}-${arch}.tar.gz"

  local caw_log="$LOG_DIR/caw-download.log"
  local tss_log="$LOG_DIR/tss-prewarm.log"

  echo "      force=${FORCE_DOWNLOAD}, only=${DOWNLOAD_ONLY}"

  echo "[1/3] Start downloads..."
  local caw_pid=""
  local tss_pid=""

  if [[ "$DOWNLOAD_ONLY" == "all" || "$DOWNLOAD_ONLY" == "caw" ]]; then
    (
      set -euo pipefail
      if should_download_artifact "$BIN_DIR/caw" "caw"; then
        local caw_tmp_tar caw_tmp_sum
        caw_tmp_tar="$(mktemp)"
        caw_tmp_sum="$(mktemp)"
        trap 'rm -f "$caw_tmp_tar" "$caw_tmp_sum"' EXIT
        download_with_resume "$caw_url" "$caw_tmp_tar"
        echo "Verifying checksum..."
        download_with_resume "${caw_url}.sha256" "$caw_tmp_sum"
        local expected_sum actual_sum
        expected_sum="$(awk '{print $1}' "$caw_tmp_sum")"
        actual_sum="$(sha256_file "$caw_tmp_tar")"
        if [[ "$actual_sum" != "$expected_sum" ]]; then
          echo "Checksum mismatch: expected $expected_sum, got $actual_sum" >&2
          exit 1
        fi
        echo "Checksum OK (${actual_sum:0:12}...)"
        extract_caw_assets "$caw_tmp_tar" "$BIN_DIR"
        echo "[DONE] caw downloaded to $BIN_DIR/caw"
      else
        echo "[DONE] caw reuse local binary at $BIN_DIR/caw"
      fi
    ) >"$caw_log" 2>&1 &
    caw_pid=$!
    echo "      caw pid=${caw_pid}, log=${caw_log}"
  else
    echo "      caw skipped (--only=${DOWNLOAD_ONLY})"
  fi

  if [[ "$DOWNLOAD_ONLY" == "all" || "$DOWNLOAD_ONLY" == "tss" ]]; then
    (
      set -euo pipefail
      if should_download_artifact "$CACHE_TSS_DIR/cobo-tss-node" "tss"; then
        local tss_tmp_tar
        tss_tmp_tar="$(mktemp)"
        trap 'rm -f "$tss_tmp_tar"' EXIT
        download_with_resume "$tss_url" "$tss_tmp_tar"
        extract_tss_assets "$tss_tmp_tar"
        echo "[DONE] Shared TSS cache downloaded at $CACHE_TSS_DIR"
      else
        echo "[DONE] Shared TSS cache reuse local assets at $CACHE_TSS_DIR"
      fi
    ) >"$tss_log" 2>&1 &
    tss_pid=$!
    echo "      tss pid=${tss_pid}, log=${tss_log}"
  else
    echo "      tss skipped (--only=${DOWNLOAD_ONLY})"
  fi

  echo "[2/3] Waiting for prework to complete..."
  if [[ -n "$caw_pid" ]]; then
    wait_job_or_fail "$caw_pid" "$caw_log" "caw download"
  fi
  if [[ -n "$tss_pid" ]]; then
    wait_job_or_fail "$tss_pid" "$tss_log" "tss prewarm"
  fi

  if [[ "$DOWNLOAD_ONLY" == "all" || "$DOWNLOAD_ONLY" == "caw" ]]; then
    echo "[3/3] Setting up caw in PATH..."
    setup_path
    local link_dir
    link_dir="$(get_link_dir)"
    echo "Done. caw at $link_dir/caw, TSS at $CACHE_TSS_DIR (mode=${DOWNLOAD_ONLY})"
  else
    echo "[3/3] Done. TSS at $CACHE_TSS_DIR (mode=${DOWNLOAD_ONLY})"
  fi
}

main "$@"