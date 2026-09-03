#!/usr/bin/env bash
# Installs k9s (https://github.com/derailed/k9s) from GitHub Releases.
# No devcontainer feature exists for k9s, so fetch the binary directly.
# Run once at container creation (postCreateCommand); re-running is a no-op update.
set -euo pipefail

if command -v k9s >/dev/null 2>&1; then
  echo "[install-k9s] k9s already installed: $(k9s version --short 2>/dev/null || true)"
  exit 0
fi

arch="$(uname -m)"
case "${arch}" in
  x86_64) k9s_arch="amd64" ;;
  aarch64) k9s_arch="arm64" ;;
  armv7l) k9s_arch="armv7" ;;
  *) echo "[install-k9s] Unsupported architecture: ${arch}" >&2; exit 1 ;;
esac

latest_release_json="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest)"
version="$(printf '%s' "${latest_release_json}" | grep -m1 '"tag_name"' | cut -d '"' -f4)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "[install-k9s] Installing k9s ${version} (${k9s_arch})"
curl -fsSL "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_${k9s_arch}.tar.gz" \
  -o "${tmp_dir}/k9s.tar.gz"
tar -xzf "${tmp_dir}/k9s.tar.gz" -C "${tmp_dir}" k9s
sudo install -m 0755 "${tmp_dir}/k9s" /usr/local/bin/k9s

echo "[install-k9s] Installed: $(k9s version --short 2>/dev/null || true)"
