#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <export-artifact-or-directory> [more paths...]" >&2
  exit 2
fi

check_path() {
  local target="$1"

  if [ ! -e "$target" ]; then
    echo "missing export artifact: $target" >&2
    return 1
  fi

  if [ -d "$target" ]; then
    if find "$target" -path '*addons/godot_mcp*' | grep -q .; then
      echo "MCP addon files found in export directory: $target" >&2
      return 1
    fi
    return 0
  fi

  case "$target" in
    *.log)
      if grep -E -q 'Storing File: res://addons/godot_mcp/|Storing File: res://addons/godot_mcp\.|Storing File: res://addons/godot_mcp' "$target"; then
        echo "MCP addon files were exported according to build log: $target" >&2
        return 1
      fi
      ;;
    *.zip)
      if unzip -Z -1 "$target" | grep -q '^addons/godot_mcp/'; then
        echo "MCP addon files found in export archive: $target" >&2
        return 1
      fi
      ;;
    *)
      if find "$target" -path '*addons/godot_mcp*' 2>/dev/null | grep -q .; then
        echo "MCP addon files found in export artifact: $target" >&2
        return 1
      fi
      ;;
  esac
}

for target in "$@"; do
  check_path "$target"
done

echo "verified: exported artifacts do not contain addons/godot_mcp"
