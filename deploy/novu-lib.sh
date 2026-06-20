#!/usr/bin/env bash

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

load_novu_env() {
  local script_dir env_file
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  env_file="${NOVU_ENV_FILE:-"${script_dir}/novu.env"}"

  [[ -f "${env_file}" ]] || fail "env file not found: ${env_file}"
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}

require_var() {
  local name="$1"
  if [[ -z "${!name+x}" ]]; then
    fail "required env var is missing: ${name}"
  fi
}

require_non_empty_var() {
  local name="$1"
  require_var "${name}"
  [[ -n "${!name}" ]] || fail "required env var is empty: ${name}"
}

validate_port() {
  local name="$1" value="${!1}"
  [[ "${value}" =~ ^[0-9]+$ ]] || fail "${name} must be a numeric TCP port: ${value}"
  (( value >= 1 && value <= 65535 )) || fail "${name} is outside TCP port range: ${value}"
}

validate_ipv4() {
  local name="$1" value="${!1}" part
  [[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "${name} must be an IPv4 address: ${value}"
  IFS='.' read -r -a parts <<< "${value}"
  for part in "${parts[@]}"; do
    (( part >= 0 && part <= 255 )) || fail "${name} has an invalid IPv4 octet: ${value}"
  done
}

validate_docker_name() {
  local name="$1" value="${!1}"
  [[ "${value}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail "${name} is not a safe Docker name: ${value}"
}

validate_image_ref() {
  local name="$1" value="${!1}"
  [[ "${value}" =~ ^[a-zA-Z0-9./:_-]+$ ]] || fail "${name} is not a safe image reference: ${value}"
}

validate_bool() {
  local name="$1" value="${!1}"
  [[ "${value}" == "true" || "${value}" == "false" ]] || fail "${name} must be true or false: ${value}"
}

validate_abs_dir_var() {
  local name="$1" value="${!1}"
  [[ "${value}" == /* ]] || fail "${name} must be an absolute directory path: ${value}"
  [[ "${value}" != "/" ]] || fail "${name} must not be /"
}

validate_unique_host_ports() {
  local ports=("$NOVU_API_HOST_PORT" "$NOVU_WS_HOST_PORT" "$NOVU_DASHBOARD_HOST_PORT")
  local sorted unique_count
  sorted="$(printf '%s\n' "${ports[@]}" | sort -n)"
  unique_count="$(printf '%s\n' "${ports[@]}" | sort -n | uniq | wc -l | tr -d ' ')"
  [[ "${unique_count}" == "${#ports[@]}" ]] || fail "host ports must be unique: ${sorted}"
}

validate_store_encryption_key() {
  [[ "${#NOVU_STORE_ENCRYPTION_KEY}" -eq 32 ]] || fail "NOVU_STORE_ENCRYPTION_KEY must be exactly 32 characters"
}

validate_required_env() {
  local required_non_empty=(
    NOVU_PUBLIC_IP
    NOVU_BIND_IP
    NOVU_NETWORK
    NOVU_MONGO_DATA_DIR
    NOVU_REDIS_CONTAINER_NAME
    NOVU_MONGODB_CONTAINER_NAME
    NOVU_API_CONTAINER_NAME
    NOVU_WORKER_CONTAINER_NAME
    NOVU_WS_CONTAINER_NAME
    NOVU_DASHBOARD_CONTAINER_NAME
    NOVU_REDIS_IMAGE
    NOVU_MONGODB_IMAGE
    NOVU_API_IMAGE
    NOVU_WORKER_IMAGE
    NOVU_WS_IMAGE
    NOVU_DASHBOARD_IMAGE
    NOVU_NODE_ENV
    NOVU_MONGO_ROOT_USERNAME
    NOVU_MONGO_ROOT_PASSWORD
    NOVU_MONGO_DATABASE
    NOVU_MONGO_AUTH_SOURCE
    NOVU_MONGO_MIN_POOL_SIZE
    NOVU_MONGO_MAX_POOL_SIZE
    NOVU_REDIS_DB_INDEX
    NOVU_S3_BUCKET_NAME
    NOVU_S3_REGION
    NOVU_AWS_ACCESS_KEY_ID
    NOVU_AWS_SECRET_ACCESS_KEY
    NOVU_JWT_SECRET
    NOVU_STORE_ENCRYPTION_KEY
    NOVU_SECRET_KEY
    NOVU_SUBSCRIBER_WIDGET_JWT_EXPIRATION_TIME
    NOVU_NEW_RELIC_ENABLED
    NOVU_NEW_RELIC_APP_NAME
    NOVU_NEW_RELIC_LICENSE_KEY
    NOVU_MONGO_AUTO_CREATE_INDEXES
    NOVU_IS_API_IDEMPOTENCY_ENABLED
    NOVU_IS_API_RATE_LIMITING_ENABLED
    NOVU_IS_NEW_MESSAGES_API_RESPONSE_ENABLED
    NOVU_IS_V2_ENABLED
    NOVU_IS_SELF_HOSTED
    NOVU_BROADCAST_QUEUE_CHUNK_SIZE
    NOVU_MULTICAST_QUEUE_CHUNK_SIZE
    NOVU_IS_EMAIL_INLINE_CSS_DISABLED
    NOVU_IS_USE_MERGED_DIGEST_ID_ENABLED
    NOVU_HEALTH_TIMEOUT_SECONDS
  )

  local required_present=(
    NOVU_REDIS_PASSWORD
    NOVU_REDIS_CACHE_SERVICE_HOST
    NOVU_SENTRY_DSN
    NOVU_API_CONTEXT_PATH
    NOVU_WS_CONTEXT_PATH
  )

  local port_vars=(
    NOVU_API_HOST_PORT
    NOVU_API_CONTAINER_PORT
    NOVU_WORKER_CONTAINER_PORT
    NOVU_WS_HOST_PORT
    NOVU_WS_CONTAINER_PORT
    NOVU_DASHBOARD_HOST_PORT
    NOVU_DASHBOARD_CONTAINER_PORT
    NOVU_DASHBOARD_ALT_HOST_PORT
    NOVU_REDIS_CONTAINER_PORT
    NOVU_REDIS_CACHE_SERVICE_PORT
    NOVU_MONGODB_CONTAINER_PORT
    NOVU_S3_LOCAL_STACK_PORT
  )

  local docker_name_vars=(
    NOVU_NETWORK
    NOVU_REDIS_CONTAINER_NAME
    NOVU_MONGODB_CONTAINER_NAME
    NOVU_API_CONTAINER_NAME
    NOVU_WORKER_CONTAINER_NAME
    NOVU_WS_CONTAINER_NAME
    NOVU_DASHBOARD_CONTAINER_NAME
  )

  local image_vars=(
    NOVU_REDIS_IMAGE
    NOVU_MONGODB_IMAGE
    NOVU_API_IMAGE
    NOVU_WORKER_IMAGE
    NOVU_WS_IMAGE
    NOVU_DASHBOARD_IMAGE
  )

  local bool_vars=(
    NOVU_NEW_RELIC_ENABLED
    NOVU_MONGO_AUTO_CREATE_INDEXES
    NOVU_IS_API_IDEMPOTENCY_ENABLED
    NOVU_IS_API_RATE_LIMITING_ENABLED
    NOVU_IS_NEW_MESSAGES_API_RESPONSE_ENABLED
    NOVU_IS_V2_ENABLED
    NOVU_IS_SELF_HOSTED
    NOVU_IS_EMAIL_INLINE_CSS_DISABLED
    NOVU_IS_USE_MERGED_DIGEST_ID_ENABLED
  )

  local var
  for var in "${required_non_empty[@]}"; do require_non_empty_var "${var}"; done
  for var in "${required_present[@]}"; do require_var "${var}"; done
  for var in "${port_vars[@]}"; do require_non_empty_var "${var}"; validate_port "${var}"; done
  for var in "${docker_name_vars[@]}"; do validate_docker_name "${var}"; done
  for var in "${image_vars[@]}"; do validate_image_ref "${var}"; done
  for var in "${bool_vars[@]}"; do validate_bool "${var}"; done

  validate_ipv4 NOVU_PUBLIC_IP
  validate_ipv4 NOVU_BIND_IP
  validate_abs_dir_var NOVU_MONGO_DATA_DIR
  validate_unique_host_ports
  validate_store_encryption_key
  validate_port NOVU_HEALTH_TIMEOUT_SECONDS
}

mongo_url() {
  printf 'mongodb://%s:%s@%s:%s/%s?authSource=%s' \
    "${NOVU_MONGO_ROOT_USERNAME}" \
    "${NOVU_MONGO_ROOT_PASSWORD}" \
    "${NOVU_MONGODB_CONTAINER_NAME}" \
    "${NOVU_MONGODB_CONTAINER_PORT}" \
    "${NOVU_MONGO_DATABASE}" \
    "${NOVU_MONGO_AUTH_SOURCE}"
}

api_public_url() {
  printf 'http://%s:%s' "${NOVU_PUBLIC_IP}" "${NOVU_API_HOST_PORT}"
}

ws_public_url() {
  printf 'http://%s:%s' "${NOVU_PUBLIC_IP}" "${NOVU_WS_HOST_PORT}"
}

dashboard_public_url() {
  printf 'http://%s:%s' "${NOVU_PUBLIC_IP}" "${NOVU_DASHBOARD_HOST_PORT}"
}

s3_local_stack_url() {
  printf 'http://%s:%s' "${NOVU_PUBLIC_IP}" "${NOVU_S3_LOCAL_STACK_PORT}"
}

api_internal_url() {
  printf 'http://%s:%s' "${NOVU_API_CONTAINER_NAME}" "${NOVU_API_CONTAINER_PORT}"
}

front_base_url_regex() {
  printf 'http://%s:(%s|%s)' "${NOVU_PUBLIC_IP}" "${NOVU_DASHBOARD_HOST_PORT}" "${NOVU_DASHBOARD_ALT_HOST_PORT}"
}

ensure_port_available() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    if ss -lnt | awk -v port=":${port}" 'NR > 1 && index($4, port) == length($4) - length(port) + 1 { found=1 } END { exit found ? 0 : 1 }'; then
      fail "host port is already listening: ${port}"
    fi
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    ! lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 \
      || fail "host port is already listening: ${port}"
    return
  fi

  fail "cannot check host port ${port}: neither ss nor lsof is installed"
}

wait_healthy() {
  local name="$1"
  local timeout="${NOVU_HEALTH_TIMEOUT_SECONDS}"
  local start now status
  start="$(date +%s)"

  info "waiting for ${name} health"
  while true; do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "${name}" 2>/dev/null || true)"
    [[ "${status}" == "healthy" ]] && return 0
    [[ "${status}" == "unhealthy" ]] && fail "${name} became unhealthy"
    [[ "${status}" != "no-healthcheck" ]] || fail "${name} does not define a healthcheck"

    now="$(date +%s)"
    (( now - start < timeout )) || fail "timed out waiting for ${name} to become healthy"
    sleep 2
  done
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 || fail "docker command not found"
  docker info >/dev/null 2>&1 || fail "docker daemon is not reachable"
}
