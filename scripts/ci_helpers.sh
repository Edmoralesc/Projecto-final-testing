#!/usr/bin/env bash
set -euo pipefail

# Common helpers for CI/CD jobs

log() { echo "[ci-helpers] $*"; }

# docker_login_dockerhub USERNAME TOKEN
docker_login_dockerhub() {
  local user="$1" token="$2"
  echo "$token" | docker login -u "$user" --password-stdin
}

# compute image tags
# Usage: image_tags repo -> prints "repo:staging repo:${SHA}"
image_tags() {
  local repo="$1"
  local sha_short
  sha_short="${GITHUB_SHA:-unknown}"
  echo "${repo}:staging ${repo}:${sha_short}"
}

# wait_for_rollout <namespace> <kind/name> [timeout]
wait_for_rollout() {
  local ns="$1" target="$2" timeout="${3:-120s}"
  kubectl -n "$ns" rollout status "$target" --timeout="$timeout"
}

# set_images <namespace> <backend_image> <frontend_image>
set_images() {
  local ns="$1" backend_img="$2" frontend_img="$3"
  kubectl -n "$ns" set image deployment/backend backend="$backend_img"
  kubectl -n "$ns" set image deployment/frontend frontend="$frontend_img"
}

# backend_health_check <namespace>
backend_health_check() {
  local ns="$1"
  kubectl -n "$ns" port-forward deploy/backend 18080:8000 >/tmp/pf.log 2>&1 &
  local pf=$!
  sleep 3
  local code="000"
  for _ in $(seq 1 10); do
    code=$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:18080/health || true)
    if [ "$code" = "200" ]; then break; fi
    sleep 3
  done
  kill "$pf" || true
  echo "$code"
}
