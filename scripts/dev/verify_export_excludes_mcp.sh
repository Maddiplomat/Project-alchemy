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
	if find "$target" \( -path '*addons/godot_mcp*' -o -path '*scripts/MCPRuntime.gd*' \) | grep -q .; then
	  echo "MCP development files found in export directory: $target" >&2
      return 1
    fi
    return 0
  fi

  case "$target" in
    *.log)
	  if grep -E -q 'Storing File: res://(addons/godot_mcp|scripts/MCPRuntime\.gd)' "$target"; then
		echo "MCP development files were exported according to build log: $target" >&2
        return 1
      fi
      ;;
    *.zip)
	  if unzip -Z -1 "$target" | grep -E -q '^(addons/godot_mcp/|scripts/MCPRuntime\.gd)'; then
		echo "MCP development files found in export archive: $target" >&2
        return 1
      fi
      ;;
    *)
	  if find "$target" \( -path '*addons/godot_mcp*' -o -path '*scripts/MCPRuntime.gd*' \) 2>/dev/null | grep -q .; then
		echo "MCP development files found in export artifact: $target" >&2
        return 1
      fi
      ;;
  esac
}

for target in "$@"; do
  check_path "$target"
done

echo "verified: exported artifacts do not contain MCP development tooling"
