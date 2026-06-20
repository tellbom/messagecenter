#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/novu-lib.sh"

load_novu_env
validate_required_env
ensure_docker

required_containers=(
  "${NOVU_REDIS_CONTAINER_NAME}"
  "${NOVU_MONGODB_CONTAINER_NAME}"
  "${NOVU_API_CONTAINER_NAME}"
  "${NOVU_WORKER_CONTAINER_NAME}"
  "${NOVU_WS_CONTAINER_NAME}"
  "${NOVU_DASHBOARD_CONTAINER_NAME}"
)

for container in "${required_containers[@]}"; do
  docker inspect "${container}" >/dev/null 2>&1 || fail "container does not exist: ${container}. Run ./start-novu.sh first."
done

info "restarting Redis and MongoDB"
docker restart "${NOVU_REDIS_CONTAINER_NAME}" "${NOVU_MONGODB_CONTAINER_NAME}" >/dev/null
wait_healthy "${NOVU_REDIS_CONTAINER_NAME}"
wait_healthy "${NOVU_MONGODB_CONTAINER_NAME}"

info "restarting API, Worker, and WS"
docker restart \
  "${NOVU_API_CONTAINER_NAME}" \
  "${NOVU_WORKER_CONTAINER_NAME}" \
  "${NOVU_WS_CONTAINER_NAME}" >/dev/null
wait_healthy "${NOVU_API_CONTAINER_NAME}"
wait_healthy "${NOVU_WORKER_CONTAINER_NAME}"
wait_healthy "${NOVU_WS_CONTAINER_NAME}"

info "restarting Dashboard"
docker restart "${NOVU_DASHBOARD_CONTAINER_NAME}" >/dev/null
wait_healthy "${NOVU_DASHBOARD_CONTAINER_NAME}"

info "Novu restart completed"
echo "Dashboard: $(dashboard_public_url)"
echo "API:       $(api_public_url)"
echo "WS:        $(ws_public_url)"
