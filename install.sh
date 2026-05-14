#!/usr/bin/env bash
set -euo pipefail

# Install the latest caw CLI and TSS node assets.
# Re-running is safe: existing binaries are skipped.
#
# Usage:
#   curl -fsSL <url>/install.sh | bash
#   CAW_VERSION=v0.2.80 bash install.sh
#   CAW_LINK_DIR=/usr/local/bin bash install.sh   # override symlink directory

CAW_BASE_URL="${CAW_BASE_URL:-https://download.agenticwallet.cobo.com/binary-release}"
CAW_VERSION="${CAW_VERSION:-v0.2.84}"
TSS_BASE_URL="${TSS_BASE_URL:-https://download.tss.cobo.com/binary-release/latest}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.cobo-agentic-wallet}"
BIN_DIR="${BIN_DIR:-$INSTALL_ROOT/bin}"
CACHE_TSS_DIR="${CACHE_TSS_DIR:-$INSTALL_ROOT/cache/tss-node}"
LOG_DIR="${LOG_DIR:-$INSTALL_ROOT/logs}"

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

  local caw_url="${CAW_BASE_URL}/${CAW_VERSION}/caw-${os}-${arch}-${CAW_VERSION}.tar.gz"
  local tss_url="${TSS_BASE_URL}/cobo-tss-node-${os}-${arch}.tar.gz"
  local caw_log="$LOG_DIR/caw-download.log"
  local tss_log="$LOG_DIR/tss-prewarm.log"

  echo "[1/4] Start downloads..."

  local caw_pid="" tss_pid=""

  (
    set -euo pipefail
    caw_tmp_tar="$(mktemp)"
    caw_tmp_sum="$(mktemp)"
    trap 'rm -f "$caw_tmp_tar" "$caw_tmp_sum"' EXIT
    download_with_resume "$caw_url" "$caw_tmp_tar"
    echo "Verifying checksum..."
    download_with_resume "${caw_url}.sha256" "$caw_tmp_sum"
    expected_sum="$(awk '{print $1}' "$caw_tmp_sum")"
    actual_sum="$(sha256_file "$caw_tmp_tar")"
    if [[ "$actual_sum" != "$expected_sum" ]]; then
      echo "Checksum mismatch: expected $expected_sum, got $actual_sum" >&2
      exit 1
    fi
    echo "Checksum OK (${actual_sum:0:12}...)"
    extract_caw_assets "$caw_tmp_tar" "$BIN_DIR"
  ) >"$caw_log" 2>&1 &
  caw_pid=$!

  (
    set -euo pipefail
    tss_tmp_tar="$(mktemp)"
    trap 'rm -f "$tss_tmp_tar"' EXIT
    download_with_resume "$tss_url" "$tss_tmp_tar"
    extract_tss_assets "$tss_tmp_tar"
  ) >"$tss_log" 2>&1 &
  tss_pid=$!

  echo "[2/4] Waiting for downloads to complete..."
  [[ -n "$caw_pid" ]] && wait_job_or_fail "$caw_pid" "$caw_log" "caw download" && cat "$caw_log"
  [[ -n "$tss_pid" ]] && wait_job_or_fail "$tss_pid" "$tss_log" "tss download" && cat "$tss_log"

  echo "[3/4] Setting up caw in PATH..."
  setup_path

  local link_dir
  link_dir="$(get_link_dir)"
  echo ""
  echo "[4/4] Done."
  echo "  caw $("$link_dir/caw" --version)  →  $link_dir/caw"
  echo "  TSS node                      →  $CACHE_TSS_DIR"
  echo ""

  if [[ "$_PATH_SHELL_UPDATED" == "true" ]]; then
    local login_shell
    login_shell="$(basename "${SHELL:-bash}")"
    echo "Run the following to use 'caw' in this terminal:"
    case "$login_shell" in
      zsh)  echo "  source ~/.zshrc" ;;
      fish) echo "  source ~/.config/fish/config.fish" ;;
      *)    echo "  source ~/.bashrc" ;;
    esac
    echo ""
    echo "New terminals will have 'caw' on PATH automatically."
  else
    echo "caw is ready. Run: caw"
  fi
}

main
