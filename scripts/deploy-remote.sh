#!/usr/bin/env bash
# Runs on the ECS host as root (via deploy-ctl). Never interpolate caller input
# into a shell string: the only input is a validated 40-hex commit SHA.
set -Eeuo pipefail

BASE="${APP_BASE:-/opt/closed-loop}"
RELEASES="$BASE/releases"
CURRENT="$BASE/current"
LOCK="$BASE/deploy.lock"
HEALTH_RETRIES="${HEALTH_RETRIES:-30}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-2}"

usage() {
  echo "usage: deploy-remote.sh <40-hex-sha> | deploy-remote.sh --rollback" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
MODE="$1"

mkdir -p "$RELEASES"
exec 9>"$LOCK"
flock -n 9 || { echo "another deploy is running" >&2; exit 75; }

compose() {
  local dir="$1"
  shift
  docker compose \
    --project-directory "$dir" \
    --env-file "$BASE/deploy.env" \
    -f "$dir/compose.yml" \
    "$@"
}

wait_for_sha() {
  local dir="$1" sha="$2" i got
  for ((i = 1; i <= HEALTH_RETRIES; i++)); do
    got="$(compose "$dir" exec -T app wget -qO- http://127.0.0.1:3000/version 2>/dev/null \
      | sed -n 's/.*"sha":"\([^"]*\)".*/\1/p' || true)"
    if [[ "$got" == "$sha" ]]; then
      echo "health ok: sha=$sha"
      return 0
    fi
    sleep "$HEALTH_INTERVAL"
  done
  echo "health check failed: expected sha=$sha" >&2
  return 1
}

switch_to() {
  ln -sfn "$1" "$CURRENT.tmp"
  mv -Tf "$CURRENT.tmp" "$CURRENT"
}

previous_release() {
  local exclude="$1"
  find "$RELEASES" -mindepth 1 -maxdepth 1 -type d ! -path "$exclude" \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-
}

rollback_to() {
  local prev="$1" tag
  tag="$(sed -n 's/^SHA=//p' "$prev/meta")"
  [[ "$tag" =~ ^[0-9a-f]{40}$ ]] || { echo "bad meta in $prev" >&2; exit 1; }
  echo "rolling back to $prev (sha=$tag)" >&2
  switch_to "$prev"
  export IMAGE_TAG="$tag"
  compose "$prev" pull app
  compose "$prev" up -d --remove-orphans
  wait_for_sha "$prev" "$tag"
}

fail() {
  local prev="$1" first="$2"
  if (( first == 0 )) && [[ -n "$prev" ]]; then
    rollback_to "$prev"
    exit 1
  fi
  echo "FIRST_DEPLOY failed; container kept for inspection" >&2
  exit 1
}

deploy() {
  local sha="$1" rel prev="" first=0
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid sha: $sha" >&2; exit 64; }

  rel="$RELEASES/$sha"
  if [[ -L "$CURRENT" ]]; then
    prev="$(readlink -f "$CURRENT")"
  else
    first=1
  fi

  mkdir -p "$rel"
  cp "$BASE/compose.yml" "$rel/compose.yml"
  cp "$BASE/Caddyfile" "$rel/Caddyfile"
  install -m 600 "$BASE/app.env" "$rel/app.env"
  cat > "$rel/meta" <<META
SHA=$sha
DEPLOYED_AT=$(date -Is)
META

  echo "deploying sha=$sha first_deploy=$first"
  export IMAGE_TAG="$sha"
  compose "$rel" pull app
  if ! compose "$rel" up -d --remove-orphans; then
    compose "$rel" logs --tail=100 app >&2 || true
    fail "$prev" "$first"
  fi

  if wait_for_sha "$rel" "$sha"; then
    switch_to "$rel"
    echo "deployed sha=$sha"
    return 0
  fi

  compose "$rel" logs --tail=100 app >&2 || true
  fail "$prev" "$first"
}

rollback() {
  [[ -L "$CURRENT" ]] || { echo "no current release to roll back from" >&2; exit 1; }
  local cur prev
  cur="$(readlink -f "$CURRENT")"
  prev="$(previous_release "$cur")"
  [[ -n "$prev" ]] || { echo "no previous release available" >&2; exit 1; }
  rollback_to "$prev"
  echo "rolled back"
}

case "$MODE" in
  --rollback) rollback ;;
  *) deploy "$MODE" ;;
esac
