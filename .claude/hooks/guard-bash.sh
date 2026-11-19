#!/usr/bin/env bash
# PreToolUse(Bash) guard: blocks force-push, direct pushes to main, destructive resets.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[[ -n "$cmd" ]] || exit 0

deny() {
  jq -nc --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

raw="$(printf '%s' "$cmd" | tr '\n' ' ' | tr -s ' ')"

# Match `git ... push` even with options such as `-c key=value` in between.
if [[ "$raw" =~ (^|[[:space:];\&|])git([[:space:]][^;\&\|]*)?[[:space:]]push([[:space:]]|$) ]]; then
  if [[ "$raw" =~ --force|[[:space:]]-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|[[:space:]]\+[^[:space:]] ]]; then
    deny "禁止强推（--force / -f / +refspec）。请改用新的提交。"
  fi
  if [[ "$raw" =~ [[:space:]](origin[[:space:]]+)?(main|master)([[:space:]]|$) ]]; then
    deny "禁止直接推送 main/master。请开分支并走 PR。"
  fi
  if [[ -n "$cwd" ]]; then
    branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ "$branch" == "main" || "$branch" == "master" ]]; then
      deny "当前分支是 ${branch}，禁止直接推送。请先创建 feat/* 分支。"
    fi
  fi
fi

if [[ "$raw" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
  deny "禁止 git reset --hard：会丢失未提交的工作。"
fi

if [[ "$raw" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f ]]; then
  deny "禁止 git clean -f：会删除未跟踪文件。"
fi

if [[ "$raw" =~ (^|[[:space:]])rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r) ]]; then
  deny "禁止 rm -rf。请指定具体文件，或先与用户确认。"
fi

exit 0
