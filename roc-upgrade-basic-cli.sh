#!/bin/bash
# Point every Roc app and package in this repo at another basic-cli release,
# then check and test every app so breaking changes show up right away.
# Usage: ./roc-upgrade-basic-cli.sh <version>   (e.g. 0.27.0)
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

version="$1"
repo_root=$(dirname "$(realpath "$0")")

# The URL contains a content hash, so it has to come from the release itself.
release=$(curl -fsSL "https://api.github.com/repos/roc-lang/basic-cli/releases/tags/$version") || {
  echo "basic-cli release '$version' not found."
  exit 1
}
url=$(echo "$release" | jq -r '.assets[] | select(.name | endswith(".tar.zst")) | .browser_download_url')
if [ -z "$url" ]; then
  echo "basic-cli release '$version' has no .tar.zst asset."
  exit 1
fi

mapfile -t files < <(grep -rlE --include='*.roc' 'https://github.com/roc-lang/basic-cli/releases/download/[^"]+\.tar\.zst' "$repo_root")
if [ "${#files[@]}" -eq 0 ]; then
  echo "No .roc file references basic-cli."
  exit 1
fi
sed -i -E "s#https://github.com/roc-lang/basic-cli/releases/download/[^\"]+\.tar\.zst#$url#" "${files[@]}"
printf 'Updated %s\n' "${files[@]#"$repo_root"/}"

# Recent releases state the oldest compiler nightly they work with.
echo "Required: $(echo "$release" | jq -r '.body' | grep -m1 -iE 'requires .*nightly' || echo 'not stated in the release notes')"
echo "Installed: $(roc version)"

mapfile -t apps < <(grep -rlE --include='main.roc' '^app \[' "$repo_root")
failed=0
for app in "${apps[@]}"; do
  echo "== ${app#"$repo_root"/}"
  roc check "$app" && roc test "$app" || failed=1
done
exit "$failed"
