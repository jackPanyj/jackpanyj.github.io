#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

git add -A
git commit -m "sync: update content $(date '+%Y-%m-%d')" || { echo "No changes to commit"; exit 0; }
git push origin main

echo "Deployed!"
