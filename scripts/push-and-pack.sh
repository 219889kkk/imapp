#!/usr/bin/env bash
# After GitHub auth is ready: push master and trigger Android arm64 pack.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! gh auth status >/dev/null 2>&1; then
  if [[ -s "${HOME}/.config/gh/imapp_token" ]]; then
    gh auth login --hostname github.com --with-token < "${HOME}/.config/gh/imapp_token"
  else
    echo "Not logged in. Run: scripts/setup-git-auth.sh"
    echo "Or open https://github.com/login/device with the code from /root/app/GITHUB_DEVICE_LOGIN.txt"
    exit 1
  fi
fi

gh auth setup-git
git push -u origin master
gh workflow run android-release.yml -R 219889kkk/imapp --ref master
echo "Triggered Android Release. Watch: https://github.com/219889kkk/imapp/actions"
gh run list -R 219889kkk/imapp --workflow=android-release.yml -L 5
