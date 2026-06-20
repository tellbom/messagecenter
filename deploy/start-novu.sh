#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/novu-lib.sh"

load_novu_env
validate_required_env
ensure_docker

info "preparing MongoDB data directory: ${NOVU_MONGO_DATA_DIR}"
mkdir -p "${NOVU_MONGO_DATA_DIR}"
[[ -d "${NOVU_MONGO_DATA_DIR}" && -w "${NOVU_MONGO_DATA_DIR}" ]] || fail "MongoDB data directory is not writable: ${NOVU_MONGO_DATA_DIR}"

info "removing old Novu containers"
docker rm -f \
  "${NOVU_DASHBOARD_CONTAINER_NAME}" \
  "${NOVU_WS_CONTAINER_NAME}" \
  "${NOVU_API_CONTAINER_NAME}" \
  "${NOVU_WORKER_CONTAINER_NAME}" \
  "${NOVU_REDIS_CONTAINER_NAME}" \
  "${NOVU_MONGODB_CONTAINER_NAME}" \
  2>/dev/null || true

info "checking published host ports"
ensure_port_available "${NOVU_API_HOST_PORT}"
ensure_port_available "${NOVU_WS_HOST_PORT}"
ensure_port_available "${NOVU_DASHBOARD_HOST_PORT}"

if ! docker network inspect "${NOVU_NETWORK}" >/dev/null 2>&1; then
  info "creating Docker network: ${NOVU_NETWORK}"
  docker network create "${NOVU_NETWORK}" >/dev/null
fi

MONGO_URL_VALUE="$(mongo_url)"
API_PUBLIC_URL_VALUE="$(api_public_url)"
WS_PUBLIC_URL_VALUE="$(ws_public_url)"
S3_LOCAL_STACK_URL_VALUE="$(s3_local_stack_url)"
API_INTERNAL_URL_VALUE="$(api_internal_url)"
FRONT_BASE_URL_REGEX_VALUE="$(front_base_url_regex)"
MONGO_HEALTH_CMD='mongosh --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --eval "db.adminCommand('\''ping'\'').ok"'

info "starting Redis"
docker run -d \
  --name "${NOVU_REDIS_CONTAINER_NAME}" \
  --network "${NOVU_NETWORK}" \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  --health-cmd='redis-cli ping' \
  --health-interval=10s \
  --health-timeout=5s \
  --health-retries=5 \
  "${NOVU_REDIS_IMAGE}" >/dev/null

info "starting MongoDB"
docker run -d \
  --name "${NOVU_MONGODB_CONTAINER_NAME}" \
  --network "${NOVU_NETWORK}" \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -e MONGO_INITDB_ROOT_USERNAME="${NOVU_MONGO_ROOT_USERNAME}" \
  -e MONGO_INITDB_ROOT_PASSWORD="${NOVU_MONGO_ROOT_PASSWORD}" \
  -v "${NOVU_MONGO_DATA_DIR}:/data/db" \
  --health-cmd="${MONGO_HEALTH_CMD}" \
  --health-interval=20s \
  --health-timeout=5s \
  --health-retries=5 \
  --health-start-period=20s \
  "${NOVU_MONGODB_IMAGE}" >/dev/null

wait_healthy "${NOVU_REDIS_CONTAINER_NAME}"
wait_healthy "${NOVU_MONGODB_CONTAINER_NAME}"

info "starting Novu API"
docker run -d \
  --name "${NOVU_API_CONTAINER_NAME}" \
  --network "${NOVU_NETWORK}" \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -p "${NOVU_BIND_IP}:${NOVU_API_HOST_PORT}:${NOVU_API_CONTAINER_PORT}" \
  -e NODE_ENV="${NOVU_NODE_ENV}" \
  -e API_ROOT_URL="${API_PUBLIC_URL_VALUE}" \
  -e PORT="${NOVU_API_CONTAINER_PORT}" \
  -e FRONT_BASE_URL="${FRONT_BASE_URL_REGEX_VALUE}" \
  -e MONGO_URL="${MONGO_URL_VALUE}" \
  -e MONGO_MIN_POOL_SIZE="${NOVU_MONGO_MIN_POOL_SIZE}" \
  -e MONGO_MAX_POOL_SIZE="${NOVU_MONGO_MAX_POOL_SIZE}" \
  -e REDIS_HOST="${NOVU_REDIS_CONTAINER_NAME}" \
  -e REDIS_PORT="${NOVU_REDIS_CONTAINER_PORT}" \
  -e REDIS_PASSWORD="${NOVU_REDIS_PASSWORD}" \
  -e REDIS_DB_INDEX="${NOVU_REDIS_DB_INDEX}" \
  -e REDIS_CACHE_SERVICE_HOST="${NOVU_REDIS_CACHE_SERVICE_HOST}" \
  -e REDIS_CACHE_SERVICE_PORT="${NOVU_REDIS_CACHE_SERVICE_PORT}" \
  -e S3_LOCAL_STACK="${S3_LOCAL_STACK_URL_VALUE}" \
  -e S3_BUCKET_NAME="${NOVU_S3_BUCKET_NAME}" \
  -e S3_REGION="${NOVU_S3_REGION}" \
  -e AWS_ACCESS_KEY_ID="${NOVU_AWS_ACCESS_KEY_ID}" \
  -e AWS_SECRET_ACCESS_KEY="${NOVU_AWS_SECRET_ACCESS_KEY}" \
  -e JWT_SECRET="${NOVU_JWT_SECRET}" \
  -e STORE_ENCRYPTION_KEY="${NOVU_STORE_ENCRYPTION_KEY}" \
  -e NOVU_SECRET_KEY="${NOVU_SECRET_KEY}" \
  -e SUBSCRIBER_WIDGET_JWT_EXPIRATION_TIME="${NOVU_SUBSCRIBER_WIDGET_JWT_EXPIRATION_TIME}" \
  -e SENTRY_DSN="${NOVU_SENTRY_DSN}" \
  -e NEW_RELIC_ENABLED="${NOVU_NEW_RELIC_ENABLED}" \
  -e NEW_RELIC_APP_NAME="${NOVU_NEW_RELIC_APP_NAME}" \
  -e NEW_RELIC_LICENSE_KEY="${NOVU_NEW_RELIC_LICENSE_KEY}" \
  -e API_CONTEXT_PATH="${NOVU_API_CONTEXT_PATH}" \
  -e MONGO_AUTO_CREATE_INDEXES="${NOVU_MONGO_AUTO_CREATE_INDEXES}" \
  -e IS_API_IDEMPOTENCY_ENABLED="${NOVU_IS_API_IDEMPOTENCY_ENABLED}" \
  -e IS_API_RATE_LIMITING_ENABLED="${NOVU_IS_API_RATE_LIMITING_ENABLED}" \
  -e IS_NEW_MESSAGES_API_RESPONSE_ENABLED="${NOVU_IS_NEW_MESSAGES_API_RESPONSE_ENABLED}" \
  -e IS_V2_ENABLED="${NOVU_IS_V2_ENABLED}" \
  -e IS_SELF_HOSTED="${NOVU_IS_SELF_HOSTED}" \
  --health-cmd="wget --no-verbose --tries=1 --spider http://localhost:${NOVU_API_CONTAINER_PORT}/v1/health-check || exit 1" \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=40s \
  "${NOVU_API_IMAGE}" >/dev/null

info "starting Novu Worker"
docker run -d \
  --name "${NOVU_WORKER_CONTAINER_NAME}" \
  --network "${NOVU_NETWORK}" \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -e NODE_ENV="${NOVU_NODE_ENV}" \
  -e PORT="${NOVU_WORKER_CONTAINER_PORT}" \
  -e MONGO_URL="${MONGO_URL_VALUE}" \
  -e MONGO_MIN_POOL_SIZE="${NOVU_MONGO_MIN_POOL_SIZE}" \
  -e MONGO_MAX_POOL_SIZE="${NOVU_MONGO_MAX_POOL_SIZE}" \
  -e REDIS_HOST="${NOVU_REDIS_CONTAINER_NAME}" \
  -e REDIS_PORT="${NOVU_REDIS_CONTAINER_PORT}" \
  -e REDIS_PASSWORD="${NOVU_REDIS_PASSWORD}" \
  -e REDIS_DB_INDEX="${NOVU_REDIS_DB_INDEX}" \
  -e REDIS_CACHE_SERVICE_HOST="${NOVU_REDIS_CACHE_SERVICE_HOST}" \
  -e REDIS_CACHE_SERVICE_PORT="${NOVU_REDIS_CACHE_SERVICE_PORT}" \
  -e S3_LOCAL_STACK="${S3_LOCAL_STACK_URL_VALUE}" \
  -e S3_BUCKET_NAME="${NOVU_S3_BUCKET_NAME}" \
  -e S3_REGION="${NOVU_S3_REGION}" \
  -e AWS_ACCESS_KEY_ID="${NOVU_AWS_ACCESS_KEY_ID}" \
  -e AWS_SECRET_ACCESS_KEY="${NOVU_AWS_SECRET_ACCESS_KEY}" \
  -e STORE_ENCRYPTION_KEY="${NOVU_STORE_ENCRYPTION_KEY}" \
  -e SUBSCRIBER_WIDGET_JWT_EXPIRATION_TIME="${NOVU_SUBSCRIBER_WIDGET_JWT_EXPIRATION_TIME}" \
  -e SENTRY_DSN="${NOVU_SENTRY_DSN}" \
  -e NEW_RELIC_ENABLED="${NOVU_NEW_RELIC_ENABLED}" \
  -e NEW_RELIC_APP_NAME="${NOVU_NEW_RELIC_APP_NAME}" \
  -e NEW_RELIC_LICENSE_KEY="${NOVU_NEW_RELIC_LICENSE_KEY}" \
  -e BROADCAST_QUEUE_CHUNK_SIZE="${NOVU_BROADCAST_QUEUE_CHUNK_SIZE}" \
  -e MULTICAST_QUEUE_CHUNK_SIZE="${NOVU_MULTICAST_QUEUE_CHUNK_SIZE}" \
  -e API_ROOT_URL="${API_INTERNAL_URL_VALUE}" \
  -e IS_EMAIL_INLINE_CSS_DISABLED="${NOVU_IS_EMAIL_INLINE_CSS_DISABLED}" \
  -e IS_USE_MERGED_DIGEST_ID_ENABLED="${NOVU_IS_USE_MERGED_DIGEST_ID_ENABLED}" \
  --health-cmd="wget --no-verbose --tries=1 --spider http://localhost:${NOVU_WORKER_CONTAINER_PORT}/v1/health-check || exit 1" \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=20s \
  "${NOVU_WORKER_IMAGE}" >/dev/null

info "starting Novu WS"
docker run -d \
  --name "${NOVU_WS_CONTAINER_NAME}" \
  --network "${NOVU_NETWORK}" \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -p "${NOVU_BIND_IP}:${NOVU_WS_HOST_PORT}:${NOVU_WS_CONTAINER_PORT}" \
  -e PORT="${NOVU_WS_CONTAINER_PORT}" \
  -e NODE_ENV="${NOVU_NODE_ENV}" \
  -e MONGO_URL="${MONGO_URL_VALUE}" \
  -e MONGO_MIN_POOL_SIZE="${NOVU_MONGO_MIN_POOL_SIZE}" \
  -e MONGO_MAX_POOL_SIZE="${NOVU_MONGO_MAX_POOL_SIZE}" \
  -e REDIS_HOST="${NOVU_REDIS_CONTAINER_NAME}" \
  -e REDIS_PORT="${NOVU_REDIS_CONTAINER_PORT}" \
  -e REDIS_PASSWORD="${NOVU_REDIS_PASSWORD}" \
  -e JWT_SECRET="${NOVU_JWT_SECRET}" \
  -e WS_CONTEXT_PATH="${NOVU_WS_CONTEXT_PATH}" \
  -e NEW_RELIC_ENABLED="${NOVU_NEW_RELIC_ENABLED}" \
  -e NEW_RELIC_APP_NAME="${NOVU_NEW_RELIC_APP_NAME}" \
  -e NEW_RELIC_LICENSE_KEY="${NOVU_NEW_RELIC_LICENSE_KEY}" \
  --health-cmd="wget --no-verbose --tries=1 --spider http://localhost:${NOVU_WS_CONTAINER_PORT}/v1/health-check || exit 1" \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=40s \
  "${NOVU_WS_IMAGE}" >/dev/null

wait_healthy "${NOVU_API_CONTAINER_NAME}"
wait_healthy "${NOVU_WORKER_CONTAINER_NAME}"
wait_healthy "${NOVU_WS_CONTAINER_NAME}"

info "starting Novu Dashboard"
docker run -d \
  --name "${NOVU_DASHBOARD_CONTAINER_NAME}" \
  --network "${NOVU_NETWORK}" \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -p "${NOVU_BIND_IP}:${NOVU_DASHBOARD_HOST_PORT}:${NOVU_DASHBOARD_CONTAINER_PORT}" \
  -e VITE_API_HOSTNAME="${API_PUBLIC_URL_VALUE}" \
  -e VITE_WEBSOCKET_HOSTNAME="${WS_PUBLIC_URL_VALUE}" \
  --health-cmd="node -e \"const http = require('http'); const req = http.get({hostname: 'localhost', port: ${NOVU_DASHBOARD_CONTAINER_PORT}, path: '/', timeout: 5000}, (res) => { process.exit(res.statusCode === 200 ? 0 : 1); }); req.on('error', () => process.exit(1)); req.on('timeout', () => { req.destroy(); process.exit(1); });\"" \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=20s \
  "${NOVU_DASHBOARD_IMAGE}" >/dev/null

wait_healthy "${NOVU_DASHBOARD_CONTAINER_NAME}"

info "Novu is ready"
echo "Dashboard: $(dashboard_public_url)"
echo "API:       $(api_public_url)"
echo "WS:        $(ws_public_url)"
