#!/usr/bin/env bash
set -euo pipefail
TMPDIR=$(mktemp -d)
INCLUDE_FILE=release-include-list.txt
if [ -f "$INCLUDE_FILE" ]; then
  echo "Using include list at repository root: $INCLUDE_FILE"
  > /tmp/include.tmp
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ -d "$path" ]; then
      # include the directory itself (so empty dirs are preserved)
      printf "%s/\n" "$path" >> /tmp/include.tmp
      # include all files under the directory
      find "$path" -type f -print >> /tmp/include.tmp
    else
      printf "%s\n" "$path" >> /tmp/include.tmp
    fi
  done < <(awk '!/^\s*#/ && NF {print}' "$INCLUDE_FILE")
  rsync -a --delete --files-from=/tmp/include.tmp ./ "$TMPDIR/"
  COUNT=$(wc -l < /tmp/include.tmp || true)
  rm -f /tmp/include.tmp
  echo "Included $COUNT paths."
else
  echo "No include list found; snapshotting working tree with default excludes"
  rsync -a --delete --exclude='.git' --exclude='.github' --exclude='node_modules' --exclude='build' ./ "$TMPDIR/"
fi
tar -C "$TMPDIR" -czf release.tar.gz .
rm -rf "$TMPDIR"
