# Novu docker run 启动说明

以下命令根据远程服务器 `/opt/novu/docker-compose.yml` 和 `/opt/novu/.env` 的真实配置拆解生成，不再依赖 `docker compose` 启动 Novu 服务。

已解析服务：

- `redis`: `redis:alpine`
- `mongodb`: `mongo:8.0.17`
- `api`: `ghcr.io/novuhq/novu/api:3.17.0`
- `worker`: `ghcr.io/novuhq/novu/worker:3.17.0`
- `ws`: `ghcr.io/novuhq/novu/ws:3.17.0`
- `dashboard`: `ghcr.io/novuhq/novu/dashboard:3.17.0`

Compose 中没有为这些服务配置 `env_file` 或 `command`。`depends_on` 在独立 `docker run` 中不能自动生效，因此需要按本文顺序启动，并等待依赖服务健康。

密钥值说明：`JWT_SECRET`、`STORE_ENCRYPTION_KEY`、`NOVU_SECRET_KEY` 等值均来自远程服务器 `/opt/novu/.env` 的真实配置，不是手工编造。`.env` 注释中说明这些值应在生产环境中使用随机值生成，例如 `JWT_SECRET` 和 `NOVU_SECRET_KEY` 可用 `openssl rand -hex 32` 生成，`STORE_ENCRYPTION_KEY` 必须是 32 个字符，可用 `openssl rand -hex 16` 生成。

当前服务器已有其他容器占用宿主机 `3000` 和 `3002`，因此 Novu 对外端口修正为：

- API: `13000:3000`
- WS: `13002:3002`
- Dashboard: `4000:4000`

内网访问地址：

- Dashboard: `http://192.168.124.2:4000`
- API: `http://192.168.124.2:13000`
- WS: `http://192.168.124.2:13002`

## 1. 停止并清理旧 Novu Compose 容器

以下命令会停止并删除旧 Compose 容器和 Compose 网络，但不会删除 MongoDB 数据卷 `novu_mongodb`。

```bash
cd /opt/novu

docker compose down --remove-orphans

docker rm -f api worker ws dashboard redis mongodb 2>/dev/null || true
docker network rm novu_default 2>/dev/null || true
```

## 2. 准备网络和 MongoDB 数据卷

```bash
docker network create novu_default 2>/dev/null || true
docker volume create novu_mongodb
```

## 3. Redis 独立启动命令

```bash
docker run -d \
  --name redis \
  --network novu_default \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  --health-cmd='redis-cli ping' \
  --health-interval=10s \
  --health-timeout=5s \
  --health-retries=5 \
  redis:alpine
```

## 4. MongoDB 独立启动命令

```bash
docker run -d \
  --name mongodb \
  --network novu_default \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=secret \
  -v novu_mongodb:/data/db \
  --health-cmd="mongosh --quiet --username root --password secret --eval \"db.adminCommand('ping').ok\"" \
  --health-interval=20s \
  --health-timeout=5s \
  --health-retries=5 \
  --health-start-period=20s \
  mongo:8.0.17
```

## 5. 等待 Redis 和 MongoDB 健康

```bash
until [ "$(docker inspect -f '{{.State.Health.Status}}' redis)" = "healthy" ]; do
  sleep 2
done

until [ "$(docker inspect -f '{{.State.Health.Status}}' mongodb)" = "healthy" ]; do
  sleep 2
done
```

## 6. Novu API 独立启动命令

```bash
docker run -d \
  --name api \
  --network novu_default \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -p 13000:3000 \
  -e NODE_ENV=local \
  -e API_ROOT_URL=http://192.168.124.2:13000 \
  -e PORT=3000 \
  -e 'FRONT_BASE_URL=http://192.168.124.2:(4000|4200)' \
  -e 'MONGO_URL=mongodb://root:secret@mongodb:27017/novu-db?authSource=admin' \
  -e MONGO_MIN_POOL_SIZE=5 \
  -e MONGO_MAX_POOL_SIZE=10 \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD= \
  -e REDIS_DB_INDEX=2 \
  -e REDIS_CACHE_SERVICE_HOST= \
  -e REDIS_CACHE_SERVICE_PORT=6379 \
  -e S3_LOCAL_STACK=http://192.168.124.2:4566 \
  -e S3_BUCKET_NAME=novu-local \
  -e S3_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  -e JWT_SECRET=3c03d6195380a3423722ecfe689f8a3f3b976c39006e10a7bee35e26428e3536 \
  -e STORE_ENCRYPTION_KEY=346e87a392b1bb45e7e6d7c115941001 \
  -e NOVU_SECRET_KEY=e60404750f910f2d0694980be3471e1aaf314d4d5cca098cd72f99b2870cc4da \
  -e SUBSCRIBER_WIDGET_JWT_EXPIRATION_TIME=15d \
  -e SENTRY_DSN= \
  -e NEW_RELIC_ENABLED=false \
  -e NEW_RELIC_APP_NAME=NEW_RELIC_APP_NAME \
  -e NEW_RELIC_LICENSE_KEY=NEW_RELIC_LICENSE_KEY \
  -e API_CONTEXT_PATH= \
  -e MONGO_AUTO_CREATE_INDEXES=true \
  -e IS_API_IDEMPOTENCY_ENABLED=false \
  -e IS_API_RATE_LIMITING_ENABLED=false \
  -e IS_NEW_MESSAGES_API_RESPONSE_ENABLED=true \
  -e IS_V2_ENABLED=true \
  -e IS_SELF_HOSTED=true \
  --health-cmd='wget --no-verbose --tries=1 --spider http://localhost:${PORT}/v1/health-check || exit 1' \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=40s \
  ghcr.io/novuhq/novu/api:3.17.0
```

## 7. Novu Worker 独立启动命令

```bash
docker run -d \
  --name worker \
  --network novu_default \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -e NODE_ENV=local \
  -e PORT=3004 \
  -e 'MONGO_URL=mongodb://root:secret@mongodb:27017/novu-db?authSource=admin' \
  -e MONGO_MIN_POOL_SIZE=5 \
  -e MONGO_MAX_POOL_SIZE=10 \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD= \
  -e REDIS_DB_INDEX=2 \
  -e REDIS_CACHE_SERVICE_HOST= \
  -e REDIS_CACHE_SERVICE_PORT=6379 \
  -e S3_LOCAL_STACK=http://192.168.124.2:4566 \
  -e S3_BUCKET_NAME=novu-local \
  -e S3_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  -e STORE_ENCRYPTION_KEY=346e87a392b1bb45e7e6d7c115941001 \
  -e SUBSCRIBER_WIDGET_JWT_EXPIRATION_TIME=15d \
  -e SENTRY_DSN= \
  -e NEW_RELIC_ENABLED=false \
  -e NEW_RELIC_APP_NAME=NEW_RELIC_APP_NAME \
  -e NEW_RELIC_LICENSE_KEY=NEW_RELIC_LICENSE_KEY \
  -e BROADCAST_QUEUE_CHUNK_SIZE=100 \
  -e MULTICAST_QUEUE_CHUNK_SIZE=100 \
  -e API_ROOT_URL=http://api:3000 \
  -e IS_EMAIL_INLINE_CSS_DISABLED=false \
  -e IS_USE_MERGED_DIGEST_ID_ENABLED=false \
  --health-cmd='wget --no-verbose --tries=1 --spider http://localhost:${PORT:-3004}/v1/health-check || exit 1' \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=20s \
  ghcr.io/novuhq/novu/worker:3.17.0
```

## 8. Novu WS 独立启动命令

```bash
docker run -d \
  --name ws \
  --network novu_default \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -p 13002:3002 \
  -e PORT=3002 \
  -e NODE_ENV=local \
  -e 'MONGO_URL=mongodb://root:secret@mongodb:27017/novu-db?authSource=admin' \
  -e MONGO_MIN_POOL_SIZE=5 \
  -e MONGO_MAX_POOL_SIZE=10 \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD= \
  -e JWT_SECRET=3c03d6195380a3423722ecfe689f8a3f3b976c39006e10a7bee35e26428e3536 \
  -e WS_CONTEXT_PATH= \
  -e NEW_RELIC_ENABLED=false \
  -e NEW_RELIC_APP_NAME=NEW_RELIC_APP_NAME \
  -e NEW_RELIC_LICENSE_KEY=NEW_RELIC_LICENSE_KEY \
  --health-cmd='wget --no-verbose --tries=1 --spider http://localhost:${PORT}/v1/health-check || exit 1' \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=40s \
  ghcr.io/novuhq/novu/ws:3.17.0
```

## 9. 等待 API、Worker、WS 健康

```bash
until [ "$(docker inspect -f '{{.State.Health.Status}}' api)" = "healthy" ]; do
  sleep 2
done

until [ "$(docker inspect -f '{{.State.Health.Status}}' worker)" = "healthy" ]; do
  sleep 2
done

until [ "$(docker inspect -f '{{.State.Health.Status}}' ws)" = "healthy" ]; do
  sleep 2
done
```

## 10. Novu Dashboard 独立启动命令

```bash
docker run -d \
  --name dashboard \
  --network novu_default \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -p 4000:4000 \
  -e VITE_API_HOSTNAME=http://192.168.124.2:13000 \
  -e VITE_WEBSOCKET_HOSTNAME=http://192.168.124.2:13002 \
  --health-cmd='node -e "const http = require('\''http'\''); const req = http.get({hostname: '\''localhost'\'', port: 4000, path: '\''/'\'', timeout: 5000}, (res) => { process.exit(res.statusCode === 200 ? 0 : 1); }); req.on('\''error'\'', () => process.exit(1)); req.on('\''timeout'\'', () => { req.destroy(); process.exit(1); });"' \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=20s \
  ghcr.io/novuhq/novu/dashboard:3.17.0
```

## 11. 查看日志命令

```bash
docker logs -f redis
docker logs -f mongodb
docker logs -f api
docker logs -f worker
docker logs -f ws
docker logs -f dashboard
```

查看全部 Novu 容器最近日志：

```bash
for c in redis mongodb api worker ws dashboard; do
  echo "===== $c ====="
  docker logs --tail 80 "$c"
done
```

## 12. 查看容器状态命令

```bash
docker ps -a --filter name='^(redis|mongodb|api|worker|ws|dashboard)$'

docker inspect -f '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' \
  redis mongodb api worker ws dashboard
```

## 13. 端口占用排查命令

检查 Novu 对外端口：

```bash
ss -lntp | grep -E ':(13000|13002|4000)\b' || true
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -E '13000|13002|4000' || true
```

当前默认使用 `13000:3000` 和 `13002:3002`，即宿主机外部端口为 `13000`、`13002`，容器内部 Novu API 和 WS 端口仍分别为 `3000`、`3002`。

如果要改回 `3000:3000` 且发现宿主机 `3000` 被占用，方案一：查找并释放占用端口的进程或容器。

```bash
ss -lntp | grep ':3000\b' || true
docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Ports}}' | grep '3000' || true

# 如果是容器占用，按实际容器名或 ID 停止
docker stop <container_name_or_id>

# 如果是宿主机进程占用，按实际 PID 结束
kill <pid>
```

如果要改回 `3002:3002` 且发现宿主机 `3002` 被占用，方案一：查找并释放占用端口的进程或容器。

```bash
ss -lntp | grep ':3002\b' || true
docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Ports}}' | grep '3002' || true

# 如果是容器占用，按实际容器名或 ID 停止
docker stop <container_name_or_id>

# 如果是宿主机进程占用，按实际 PID 结束
kill <pid>
```

如果宿主机 `3002` 被占用，方案二：保留容器内部端口 `3002`，只修改 WS 外部端口，例如本文默认使用的 `13002:3002`。

```bash
docker rm -f ws 2>/dev/null || true

docker run -d \
  --name ws \
  --network novu_default \
  --restart unless-stopped \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -p 13002:3002 \
  -e PORT=3002 \
  -e NODE_ENV=local \
  -e 'MONGO_URL=mongodb://root:secret@mongodb:27017/novu-db?authSource=admin' \
  -e MONGO_MIN_POOL_SIZE=5 \
  -e MONGO_MAX_POOL_SIZE=10 \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD= \
  -e JWT_SECRET=3c03d6195380a3423722ecfe689f8a3f3b976c39006e10a7bee35e26428e3536 \
  -e WS_CONTEXT_PATH= \
  -e NEW_RELIC_ENABLED=false \
  -e NEW_RELIC_APP_NAME=NEW_RELIC_APP_NAME \
  -e NEW_RELIC_LICENSE_KEY=NEW_RELIC_LICENSE_KEY \
  --health-cmd='wget --no-verbose --tries=1 --spider http://localhost:${PORT}/v1/health-check || exit 1' \
  --health-interval=20s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=40s \
  ghcr.io/novuhq/novu/ws:3.17.0
```

同时需要让前端访问新的 WebSocket 外部端口，重建 Dashboard 时把 `VITE_WEBSOCKET_HOSTNAME` 改为 `http://192.168.124.2:13002`。

## 14. 重启命令

```bash
docker restart redis
docker restart mongodb
docker restart api
docker restart worker
docker restart ws
docker restart dashboard
```

## 15. API 发送测试消息

`system_notification` 是 Dashboard 中看到的 workflow 名称，实际触发标识是 `system-notification`。调用 `/v1/events/trigger` 时需要使用触发标识，否则会返回 `workflow_not_found`。

```bash
curl -sS -i \
  -X POST 'http://192.168.124.2:13000/v1/events/trigger' \
  -H 'Authorization: ApiKey 13452c72c03e51f5da2433a989008e67' \
  -H 'Content-Type: application/json' \
  --data-binary '{
    "name": "system-notification",
    "to": {
      "subscriberId": "EMP001"
    },
    "payload": {
      "title": "流程审批通知",
      "content": "您有新的待办任务",
      "url": "/tasks/123"
    }
  }'
```

成功响应示例：

```json
{
  "data": {
    "acknowledged": true,
    "status": "processed"
  }
}
```

## 16. 按依赖顺序重启全部服务

```bash
docker restart redis mongodb

until [ "$(docker inspect -f '{{.State.Health.Status}}' redis)" = "healthy" ] && \
      [ "$(docker inspect -f '{{.State.Health.Status}}' mongodb)" = "healthy" ]; do
  sleep 2
done

docker restart api worker ws
docker restart dashboard
```

## 17. 清理命令

普通清理：删除 Novu 容器和网络，但保留 MongoDB 数据卷。

```bash
docker rm -f dashboard ws api worker redis mongodb 2>/dev/null || true
docker network rm novu_default 2>/dev/null || true
```

## 18. 危险清理命令

以下命令会删除 MongoDB 数据卷 `novu_mongodb`，会导致 Novu MongoDB 数据丢失。仅在确认不需要保留数据时执行。

```bash
docker rm -f dashboard ws api worker redis mongodb 2>/dev/null || true
docker network rm novu_default 2>/dev/null || true
docker volume rm novu_mongodb
```
