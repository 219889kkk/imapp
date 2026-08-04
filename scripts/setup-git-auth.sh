#!/usr/bin/env bash
# Configure git/gh auth for pushing to github.com/219889kkk/imapp
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${HOME}/.ssh/imapp_ed25519"
TOKEN_FILE="${HOME}/.config/gh/imapp_token"

mkdir -p "${HOME}/.config/gh" "${HOME}/.ssh"

if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -f "$KEY" -N '' -C "imapp-server@$(hostname)"
fi

if ! grep -q 'github.com-imapp' "${HOME}/.ssh/config" 2>/dev/null; then
  cat >> "${HOME}/.ssh/config" <<EOF
Host github.com-imapp
  HostName github.com
  User git
  IdentityFile ${KEY}
  IdentitiesOnly yes
EOF
  chmod 600 "${HOME}/.ssh/config"
fi

echo "=== Deploy key (add in GitHub → imapp → Settings → Deploy keys, allow write) ==="
cat "${KEY}.pub"
echo

if [[ -f "$TOKEN_FILE" ]]; then
  gh auth login --hostname github.com --with-token < "$TOKEN_FILE"
  echo "gh auth: OK (token file)"
elif [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
  printf '%s\n' "${GH_TOKEN:-$GITHUB_TOKEN}" | gh auth login --hostname github.com --with-token
  echo "gh auth: OK (env token)"
else
  echo "No token yet. Either:"
  echo "  1) Put a classic PAT (repo scope) into $TOKEN_FILE then re-run this script"
  echo "  2) export GH_TOKEN=ghp_xxx && $0"
  echo "  3) Add the deploy key above with write access, then:"
  echo "       git -C $ROOT remote set-url origin git@github.com-imapp:219889kkk/imapp.git"
fi
