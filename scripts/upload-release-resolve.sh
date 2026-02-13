#!/usr/bin/env bash
# Simple chunked uploader using curl. Usage:
# ./upload-release.sh <file> <url> <user:pass>

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <file> <url> <user:pass>"
  exit 2
fi

FILE="$1"
URL="$2"
AUTH="$3"
CHUNK_SIZE=${CHUNK_SIZE:-52428800} # 50MB per chunk by default; override with env CHUNK_SIZE
DEBUG=${DEBUG:-0}

if [ "$DEBUG" != "0" ]; then
  set -x
fi

if [ ! -f "$FILE" ]; then
  echo "File not found: $FILE" >&2
  exit 1
fi

FNAME=$(basename "$FILE")
UPLOAD_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$RANDOM$RANDOM")
TOTAL_SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE")
TOTAL_CHUNKS=$(( (TOTAL_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))

echo "Uploading $FILE -> $URL as $FNAME in $TOTAL_CHUNKS chunks (id=$UPLOAD_ID)"
echo "Total size: $TOTAL_SIZE bytes; chunk size: $CHUNK_SIZE"

index=0
while [ $index -lt $TOTAL_CHUNKS ]; do
  offset=$(( index * CHUNK_SIZE ))
  echo "Uploading chunk $index (offset $offset)"

  # dd with bs=CHUNK_SIZE and skip=index extracts the exact chunk directly
  if [ "$DEBUG" != "0" ]; then
    CURL_OPTS=( -v )
  else
    CURL_OPTS=( -sS )
  fi

  # Capture response and exit code
  tmp=$(mktemp)
  # Use dd to extract the chunk — avoids SIGPIPE that tail|head causes under pipefail
  dd if="$FILE" bs="$CHUNK_SIZE" skip="$index" count=1 2>/dev/null | \
    curl "${CURL_OPTS[@]}" -u "$AUTH" -X POST "$URL" --resolve pitealabb.pitea.se:443:195.196.144.113 \
      -F "upload_id=$UPLOAD_ID" \
      -F "chunk_index=$index" \
      -F "total_chunks=$TOTAL_CHUNKS" \
      -F "filename=$FNAME" \
      -F "file=@-;filename=${FNAME}.part.$index" -o "$tmp"
  rc=$?
  resp=$(cat "$tmp" 2>/dev/null || true)
  rm -f "$tmp"

  echo "Server response for chunk $index: $resp"
  if [ $rc -ne 0 ]; then
    echo "curl exited with code $rc" >&2
  fi
  echo "Uploaded chunk $index"
  index=$((index + 1))
done

echo "Done. Server will assemble when all chunks are received."
