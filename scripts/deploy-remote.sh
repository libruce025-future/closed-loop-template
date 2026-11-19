#!/usr/bin/env bash
# Runs on the ECS host as root (via deploy-ctl). The only input is a validated SHA.
set -Eeuo pipefail

BASE="${APP_BASE:-/opt/closed-loop}"
RELEASES="$BASE/releases"
CURRENT="$BASE/current"
LOCK="$BASE/deploy.lock"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/version.json}"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-1}"

usage() {
  echo "usage: deploy-remote.sh <40-hex-sha> | deploy-remote.sh --rollback" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
MODE="$1"

mkdir -p "$RELEASES"
exec 9>"$LOCK"
flock -n 9 || { echo "another deploy is running" >&2; exit 75; }

sha_of() {
  sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/version.json" 2>/dev/null
}

verify_release() {
  local rel="$1" expected="$2" got
  [[ -f "$rel/index.html" ]] || { echo "missing $rel/index.html" >&2; return 1; }
  got="$(sha_of "$rel")"
  [[ "$got" == "$expected" ]] || { echo "version.json sha=$got expected=$expected" >&2; return 1; }
}

switch_to() {
  ln -sfn "$1" "$CURRENT.tmp"
  mv -Tf "$CURRENT.tmp" "$CURRENT"
}

reload_nginx() {
  if ! nginx -t; then
    echo "nginx config test failed" >&2
    return 1
  fi
  systemctl reload nginx
}

wait_for_sha() {
  local expected="$1" i got
  for ((i = 1; i <= HEALTH_RETRIES; i++)); do
    got="$(curl -fsS "$HEALTH_URL" 2>/dev/null | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)"
    if [[ "$got" == "$expected" ]]; then
      echo "health ok: sha=$expected"
      return 0
    fi
    sleep "$HEALTH_INTERVAL"
  done
  echo "health check failed: expected=$expected got=${got:-<none>}" >&2
  return 1
}

deploy() {
  local sha="$1" rel prev="" first=0
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid sha: $sha" >&2; exit 64; }

  rel="$RELEASES/$sha"
  verify_release "$rel" "$sha" || exit 1

  if [[ -L "$CURRENT" ]]; then
    prev="$(readlink -f "$CURRENT")"
  else
    first=1
  fi

  switch_to "$rel"
  if ! reload_nginx || ! wait_for_sha "$sha"; then
    if (( first == 0 )) && [[ -n "$prev" ]]; then
      echo "rolling back to $prev" >&2
      switch_to "$prev"
      reload_nginx || true
      wait_for_sha "$(sha_of "$prev")" || true
    else
      echo "FIRST_DEPLOY failed; release kept at $rel for inspection" >&2
    fi
    exit 1
  fi

  echo "deployed sha=$sha"
}

rollback() {
  [[ -L "$CURRENT" ]] || { echo "no current release to roll back from" >&2; exit 1; }
  local cur prev expected
  cur="$(readlink -f "$CURRENT")"
  prev="$(find "$RELEASES" -mindepth 1 -maxdepth 1 -type d ! -path "$cur" \
    -printf '%T@ %p\n' | sort -rn | head -n1 | cut -d' ' -f2-)"
  [[ -n "$prev" ]] || { echo "no previous release available" >&2; exit 1; }

  expected="$(sha_of "$prev")"
  [[ -n "$expected" ]] || { echo "no sha in $prev/version.json" >&2; exit 1; }

  echo "rolling back to $prev (sha=$expected)"
  switch_to "$prev"
  reload_nginx
  wait_for_sha "$expected"
  echo "rolled back"
}

case "$MODE" in
  --rollback) rollback ;;
  *) deploy "$MODE" ;;
esac
