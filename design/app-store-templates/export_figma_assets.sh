#!/usr/bin/env bash
set -euo pipefail

# Export raster assets from a Figma file via REST API.
# This bypasses MCP tool-call quotas and gives deterministic files for automation.
#
# Required:
#   FIGMA_ACCESS_TOKEN=... (Personal Access Token)
#
# Usage:
#   FIGMA_ACCESS_TOKEN=... ./export_figma_assets.sh \
#     --file JlmgstLYrGngH4JDybrP6Z \
#     --out /Volumes/SSD/tmuxonwatch/figma-assets \
#     --node watch-bezel=5:153 \
#     --node iphone-bezel=5:187

FILE_KEY="JlmgstLYrGngH4JDybrP6Z"
OUT_DIR="./exported-assets"
FORMAT="png"
SCALE="2"
USE_ABSOLUTE_BOUNDS="true"
declare -a NODES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      FILE_KEY="$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    --node)
      NODES+=("$2")
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --scale)
      SCALE="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '1,40p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${FIGMA_ACCESS_TOKEN:-}" ]]; then
  echo "Missing FIGMA_ACCESS_TOKEN env var." >&2
  exit 1
fi

if [[ ${#NODES[@]} -eq 0 ]]; then
  NODES=(
    "watch-bezel=5:153"
    "iphone-bezel=5:187"
  )
fi

mkdir -p "$OUT_DIR"

declare -a NODE_IDS=()
declare -A NODE_NAME_BY_ID=()
for pair in "${NODES[@]}"; do
  name="${pair%%=*}"
  id="${pair#*=}"
  NODE_IDS+=("$id")
  NODE_NAME_BY_ID["$id"]="$name"
done

ids_csv="$(IFS=,; echo "${NODE_IDS[*]}")"
json_path="$OUT_DIR/figma-images-response.json"

curl -sS \
  -H "X-Figma-Token: $FIGMA_ACCESS_TOKEN" \
  "https://api.figma.com/v1/images/$FILE_KEY?ids=$ids_csv&format=$FORMAT&scale=$SCALE&use_absolute_bounds=$USE_ABSOLUTE_BOUNDS" \
  -o "$json_path"

if ! jq -e '.images' "$json_path" >/dev/null 2>&1; then
  echo "Unexpected response. See: $json_path" >&2
  cat "$json_path" >&2
  exit 1
fi

for id in "${NODE_IDS[@]}"; do
  url="$(jq -r --arg id "$id" '.images[$id] // empty' "$json_path")"
  if [[ -z "$url" ]]; then
    echo "No image URL returned for node $id" >&2
    continue
  fi

  safe_id="${id//:/-}"
  base="${NODE_NAME_BY_ID[$id]}-${safe_id}"
  out="$OUT_DIR/${base}.${FORMAT}"

  curl -sSL "$url" -o "$out"
  echo "Exported $id -> $out"
done

echo "Done. Metadata JSON: $json_path"
