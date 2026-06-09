# MessageCenter API

ASP.NET Core 6 Web API. It wraps Novu as the source of truth for in-app messages and exposes a small business-facing message center API.

## Current Environment

| Item | Value |
|---|---|
| .NET SDK | 6.x |
| Novu Dashboard | `http://192.168.124.2:4000` |
| Novu API | `http://192.168.124.2:13000` |
| Novu WS | `http://192.168.124.2:13002` |
| Novu workflow trigger | `system-notification` |
| Novu channel | `in_app` |
| Keycloak authority | `http://192.168.124.2:18085/realms/master` |
| Test client | `cooper` |
| Test user | `196045` |

The `system-notification` in-app template must use:

```text
{{payload.title}}
{{payload.content}}
{{payload.url}}
```

## Configuration

The current intranet config is committed in [appsettings.json](MessageCenter.Api/appsettings.json):

```json
{
  "Novu": {
    "BaseUrl": "http://192.168.124.2:13000",
    "ApiKey": "13452c72c03e51f5da2433a989008e67",
    "DefaultWorkflowId": "system-notification",
    "InAppChannel": "in_app",
    "TimeoutSeconds": 10
  },
  "Jwt": {
    "Authority": "http://192.168.124.2:18085/realms/master",
    "RequireHttpsMetadata": false
  }
}
```

Environment variables can still override config:

```powershell
$env:Novu__ApiKey="13452c72c03e51f5da2433a989008e67"
$env:Jwt__Authority="http://192.168.124.2:18085/realms/master"
$env:Jwt__RequireHttpsMetadata="false"
```

## Run

```powershell
dotnet build .\MessageCenter.Api\MessageCenter.Api.csproj
dotnet run --project .\MessageCenter.Api\MessageCenter.Api.csproj --urls http://localhost:5000
```

Health check:

```bash
curl http://localhost:5000/health
# {"status":"ok"}
```

## Authentication

All `/api/message-center/*` endpoints require `Authorization: Bearer <token>`.

The API reads `preferred_username` from the Keycloak token:

- Send path: `preferred_username` becomes `sourceSystem`.
- Read path: `preferred_username` becomes Novu `subscriberId`.
- The request body `sourceSystem` is optional and ignored if supplied.

Get a test user token:

```bash
TOKEN=$(curl -s -X POST \
  http://192.168.124.2:18085/realms/master/protocol/openid-connect/token \
  -d "grant_type=password" \
  -d "client_id=cooper" \
  -d "client_secret=oEllGz2IOsrMY07YnY1hZo6RzrFBZnjD" \
  -d "username=196045" \
  -d "password=cacjszx.132" \
  | jq -r .access_token)
```

## Endpoints

### Send Message

`POST /api/message-center/send`

```bash
curl -X POST http://localhost:5000/api/message-center/send \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "businessType": "process_task",
    "businessId": "TASK_001",
    "title": "You have a new workflow task",
    "content": "Please process the inspection approval workflow",
    "url": "/process/tasks/TASK_001",
    "receivers": [{ "type": "user", "id": "196045" }]
  }'
```

Response `201`:

```json
{
  "transactionId": "txn_xxx",
  "status": "processed",
  "acknowledged": true,
  "accepted": ["196045"],
  "skipped": []
}
```

Only `receivers[].type == "user"` is actionable in MVP. Other receiver types are skipped. If all receivers are skipped, the API returns `400`.

### My Messages

`GET /api/message-center/my?page=0&limit=100`

```bash
curl "http://localhost:5000/api/message-center/my?page=0&limit=10" \
  -H "Authorization: Bearer $TOKEN"
```

Response `200`:

```json
[
  {
    "messageId": "6a27771843f156a3e5a9891f",
    "title": "You have a new workflow task",
    "content": "Please process the inspection approval workflow",
    "url": "/process/tasks/TASK_001",
    "read": false,
    "seen": false,
    "createdAt": "2026-06-09T01:45:42.993Z"
  }
]
```

### Unread Count

`GET /api/message-center/unread-count`

```bash
curl http://localhost:5000/api/message-center/unread-count \
  -H "Authorization: Bearer $TOKEN"
```

Response `200`:

```json
{
  "unreadCount": 4
}
```

The count is derived from `GET /v1/messages?page=0&limit=100&pageSize=100` by counting items where `read == false`.

### Mark Read

`POST /api/message-center/messages/{messageId}/read`

```bash
curl -X POST http://localhost:5000/api/message-center/messages/6a27771843f156a3e5a9891f/read \
  -H "Authorization: Bearer $TOKEN"
```

Response `200`:

```json
{
  "messageId": "6a27771843f156a3e5a9891f",
  "read": true,
  "unreadCount": 3
}
```

### Mark Unread

`POST /api/message-center/messages/{messageId}/unread`

```bash
curl -X POST http://localhost:5000/api/message-center/messages/6a27771843f156a3e5a9891f/unread \
  -H "Authorization: Bearer $TOKEN"
```

Response `200`:

```json
{
  "messageId": "6a27771843f156a3e5a9891f",
  "read": false,
  "unreadCount": 4
}
```

## Errors

| Status | Meaning |
|---|---|
| `400` | Validation failed, or no actionable user receivers |
| `401` | Missing/invalid JWT, or token lacks `preferred_username` |
| `502` | Novu request failed; response contains `novuStatus` |
| `504` | Novu request timed out |

Example:

```json
{
  "error": "Novu request failed.",
  "novuStatus": 0
}
```

## Audit

Each successful receiver trigger writes one structured audit log entry:

```text
AUDIT send. TransactionId=txn_xxx SourceSystem=196045 BusinessType=process_task BusinessId=TASK_001 SubscriberId=196045 NovuHttpStatus=200 Status=processed Acknowledged=True Timestamp=...
```

`IAuditSink` is the extension point. To persist audit records in a database, add `DbAuditSink : IAuditSink` and replace the DI registration in `Program.cs`.

## Used Novu Endpoints

Only these Novu endpoints are used:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/events/trigger` | Send notification |
| `GET` | `/v1/messages?page=&limit=&pageSize=` | Query messages and derive unread count |
| `POST` | `/v1/subscribers/{subscriberId}/messages/mark-as` | Mark read/unread |

Important notes:

- `GET /v1/messages` returns real Novu fields as `subject`, `content`, and `cta.data.url`.
- Mark read/unread uses body `{ "messageId": "...", "markAs": "read" }` or `{ "messageId": "...", "markAs": "unread" }`.
- The subscriber-scoped notification feed/unseen endpoints were not validated and are not used.

## Project Structure

```text
MessageCenter.Api/
  Audit/
    IAuditSink.cs
    LoggerAuditSink.cs
  Controllers/
    MessageCenterController.cs
  HttpClients/
    NovuClient.cs
    Dtos/
      NovuDtos.cs
  Middleware/
    NovuExceptionMiddleware.cs
  Models/
    SendMessageRequest.cs
    SendMessageResponse.cs
  Options/
    NovuOptions.cs
  Services/
    MessageMapper.cs
    NovuTriggerPayload.cs
  appsettings.json
  Program.cs
```

## MVP Smoke Test

```bash
BASE=http://localhost:5000

TOKEN=$(curl -s -X POST \
  http://192.168.124.2:18085/realms/master/protocol/openid-connect/token \
  -d "grant_type=password" \
  -d "client_id=cooper" \
  -d "client_secret=oEllGz2IOsrMY07YnY1hZo6RzrFBZnjD" \
  -d "username=196045" \
  -d "password=cacjszx.132" \
  | jq -r .access_token)

curl -s -X POST "$BASE/api/message-center/send" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"businessType":"process_task","businessId":"TASK_SMOKE_001","title":"Smoke test","content":"Hello","url":"/tasks/TASK_SMOKE_001","receivers":[{"type":"user","id":"196045"}]}'

curl -s "$BASE/api/message-center/my?page=0&limit=10" \
  -H "Authorization: Bearer $TOKEN"

curl -s "$BASE/api/message-center/unread-count" \
  -H "Authorization: Bearer $TOKEN"
```
