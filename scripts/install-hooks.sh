#!/usr/bin/env bash
set -euo pipefail
git_dir="$(git rev-parse --git-dir)"
mkdir -p "$git_dir/hooks"
cp "$(git rev-parse --show-toplevel)/scripts/pre-commit" "$git_dir/hooks/pre-commit"
chmod +x "$git_dir/hooks/pre-commit"
echo "Installed pre-commit hook."
