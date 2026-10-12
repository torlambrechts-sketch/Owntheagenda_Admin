#!/usr/bin/env bash
# Blocks edits to files only humans may change. Exit 2 = block with message.
path=$(jq -r '.tool_input.file_path // empty')
case "$path" in
  *.env*|supabase/migrations/*_applied*|.github/workflows/*|CLAUDE.md)
    echo "Protected file: $path — open a PR by hand instead." >&2; exit 2 ;;
esac
exit 0
