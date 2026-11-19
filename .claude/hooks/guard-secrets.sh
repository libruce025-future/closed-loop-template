#!/usr/bin/env bash
# PreToolUse(Write|Edit) guard: blocks edits to env files and key material.
set -euo pipefail

input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[[ -n "$path" ]] || exit 0

base="$(basename "$path")"
shopt -s nocasematch

reason=""
if [[ "$base" != *.example ]]; then
  case "$base" in
    .env | app.env | deploy.env | *.pem | *.key | *.p12 | *.pfx | id_rsa* | id_ed25519* | *.kdbx)
      reason="禁止写入环境变量/密钥文件：$base"
      ;;
  esac
fi

case "$path" in
  */.ssh/* | */secrets/* | */credentials/*)
    reason="禁止写入敏感目录：$path"
    ;;
esac

if [[ -n "$reason" ]]; then
  jq -nc --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
fi

exit 0
