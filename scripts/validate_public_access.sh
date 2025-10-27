#!/usr/bin/env bash
set -euo pipefail

NS="staging"

get_host(){
  local name="$1"
  local host ip
  host=$(kubectl -n "$NS" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  ip=$(kubectl -n "$NS" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$host" ]]; then echo "$host"; return; fi
  if [[ -n "$ip" ]]; then echo "$ip"; return; fi
}

BACKEND_HOST=$(get_host backend-public || true)
FRONTEND_HOST=$(get_host frontend-public || true)

[[ -z "$BACKEND_HOST" ]] && { echo "[FAIL] backend-public has no external endpoint"; exit 3; }
[[ -z "$FRONTEND_HOST" ]] && { echo "[FAIL] frontend-public has no external endpoint"; exit 3; }

wait_dns(){
  local h="$1"
  for i in {1..30}; do
    if python3 -c 'import socket,sys; socket.gethostbyname(sys.argv[1])' "$h" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

resolve_ip(){
  local h="$1"
  if command -v dig >/dev/null 2>&1; then
    dig +short "$h" | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -n1
  else
    python3 -c 'import socket,sys; print(socket.gethostbyname(sys.argv[1]))' "$h" 2>/dev/null || true
  fi
}

echo "Waiting for DNS to resolve..."
wait_dns "$BACKEND_HOST" || { echo "[WARN] Backend hostname not resolving yet"; }
wait_dns "$FRONTEND_HOST" || { echo "[WARN] Frontend hostname not resolving yet"; }

BACKEND_IP=$(resolve_ip "$BACKEND_HOST" || true)
FRONTEND_IP=$(resolve_ip "$FRONTEND_HOST" || true)

TARGET_BACKEND=${BACKEND_IP:-$BACKEND_HOST}
TARGET_FRONTEND=${FRONTEND_IP:-$FRONTEND_HOST}

echo "Testing Backend: http://$TARGET_BACKEND/health"
CODE_B=$(curl -sS --connect-timeout 5 --retry 6 --retry-delay 3 -o /dev/null -w "%{http_code}" "http://$TARGET_BACKEND/health" || true)
echo "Backend HTTP: $CODE_B"

echo "Testing Frontend: http://$TARGET_FRONTEND/"
CODE_F=$(curl -sS --connect-timeout 5 --retry 6 --retry-delay 3 -o /dev/null -w "%{http_code}" "http://$TARGET_FRONTEND/" || true)
echo "Frontend HTTP: $CODE_F"

if [[ "$CODE_B" == "200" && "$CODE_F" == "200" ]]; then
  echo "[OK] Public access validated."
  exit 0
else
  echo "[FAIL] One or more checks failed (backend=$CODE_B, frontend=$CODE_F)"
  exit 4
fi
