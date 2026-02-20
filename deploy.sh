#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBSIDIAN_VAULT="$HOME/personal/obsidian"
CONTENT_DIR="$SCRIPT_DIR/content"

# Remove symlink, copy fresh content
rm -f "$CONTENT_DIR"
mkdir -p "$CONTENT_DIR"
rsync -av --delete \
  --exclude='.obsidian' \
  --exclude='.git' \
  --exclude='.DS_Store' \
  --exclude='.gitignore' \
  "$OBSIDIAN_VAULT/" "$CONTENT_DIR/"

# Commit and push
cd "$SCRIPT_DIR"
git add content/
git add -A
git commit -m "sync: update content from obsidian vault" || echo "No changes to commit"
git push origin v4

# Restore symlink for local dev
rm -rf "$CONTENT_DIR"
ln -s "$OBSIDIAN_VAULT" "$CONTENT_DIR"

echo "Deployed! Symlink restored for local dev."
