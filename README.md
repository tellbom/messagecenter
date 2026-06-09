# MessageCenter API

A lightweight ASP.NET Core 6 wrapper around [Novu](https://novu.co) that provides a business-facing contract for sending and reading in-app notifications.

---

## Prerequisites

| Requirement | Value |
|---|---|
| .NET SDK | 6.0 |
| Novu instance | `http://192.168.124.2:13000` |
| Novu workflow | `system-notification` (active, in-app step configured) |
| Novu API key | obtain from Novu dashboard → API Keys |

### Novu workflow template prerequisite

The `system-notification` workflow's in-app step **must** reference these payload variables:

```
{{payload.title}}    — message title
{{payload.content}}  — message body
{{payload.url}}      — redirect URL (CTA)
```

This was configured during the POC and is a hard precondition. The API will not error if these are missing from the template, but notifications will render without content.

---

## Configuration

### `appsettings.json`

```json
{
  "Novu": {
    "BaseUrl": "http://192.168.124.2:13000",
    "ApiKey": "",
    "DefaultWorkflowId": "system-notification",
    "InAppChannel": "in_app",
    "TimeoutSeconds": 10
  }
}
```

`ApiKey` must **not** be committed to source control. Supply it via environment variable:

```bash
# Linux / macOS
export Novu__ApiKey=your_api_key_here

# Windows (PowerShell)
$env:Novu__ApiKey = "your_api_key_here"
```

The application will throw `InvalidOperationException` on startup if `ApiKey` or `BaseUrl` is missing or empty.

---

## Running the API

```bash
cd MessageCenter.Api
Novu__ApiKey=your_api_key_here dotnet run
```

Verify the service is up:

```bash
curl http://localhost:5000/health
# 200 {"status":"ok"}
```

---

## Endpoints

All read-path endpoints require the `X-User-Id` header carrying the Novu `subscriberId` of the authenticated user. This header is expected to be injected by the API gateway.

> **TODO:** Replace `X-User-Id` header resolution with JWT claim extraction once auth middleware is added.

---

### 1. Send a message

`POST /api/message-center/send`

Triggers a Novu `system-notification` for each user receiver. Intended for backend services only.

**Request**

```bash
curl -X POST http://localhost:5000/api/message-center/send \
  -H "Content-Type: application/json" \
  -d '{
    "sourceSystem": "workflow-center",
    "businessType": "process_task",
    "businessId":   "TASK_001",
    "title":        "You have a new workflow task",
    "content":      "Please process the inspection approval workflow",
    "url":          "/process/tasks/TASK_001",
    "receivers": [
      { "type": "user", "id": "EMP001" }
    ]
  }'
```

**Response `201`**

```json
{
  "transactionId": "abc123",
  "status": "processed",
  "acknowledged": true,
  "accepted": ["EMP001"],
  "skipped": []
}
```

**Notes**

- Only `receivers[].type == "user"` is supported in MVP. Other types are skipped and reported in `skipped`.
- Novu upserts the subscriber on trigger; receivers need not be pre-provisioned.
- Required fields: `sourceSystem`, `businessType`, `title`, `receivers` (non-empty). Missing fields return `400`.

---

### 2. Get my messages

`GET /api/message-center/my`

Returns the authenticated user's notification feed.

**Request**

```bash
curl http://localhost:5000/api/message-center/my \
  -H "X-User-Id: EMP001"

# With pagination (defaults: page=0, limit=100)
curl "http://localhost:5000/api/message-center/my?page=0&limit=10" \
  -H "X-User-Id: EMP001"
```

**Response `200`**

```json
[
  {
    "messageId": "6a27771843f156a3e5a9891f",
    "title":     "You have a new workflow task",
    "content":   "Please process the inspection approval workflow",
    "url":       "/process/tasks/TASK_001",
    "read":      false,
    "seen":      false,
    "createdAt": "2026-01-01T00:00:00Z"
  }
]
```

---

### 3. Get unread count

`GET /api/message-center/unread-count`

Returns the number of unread messages for the authenticated user.

**Request**

```bash
curl http://localhost:5000/api/message-center/unread-count \
  -H "X-User-Id: EMP001"
```

**Response `200`**

```json
{
  "unreadCount": 4
}
```

---

### 4. Mark a message as read

`POST /api/message-center/messages/{messageId}/read`

**Request**

```bash
curl -X POST \
  http://localhost:5000/api/message-center/messages/6a27771843f156a3e5a9891f/read \
  -H "X-User-Id: EMP001"
```

**Response `200`**

```json
{
  "messageId":   "6a27771843f156a3e5a9891f",
  "read":        true,
  "unreadCount": 3
}
```

---

### 5. Mark a message as unread

`POST /api/message-center/messages/{messageId}/unread`

**Request**

```bash
curl -X POST \
  http://localhost:5000/api/message-center/messages/6a27771843f156a3e5a9891f/unread \
  -H "X-User-Id: EMP001"
```

**Response `200`**

```json
{
  "messageId":   "6a27771843f156a3e5a9891f",
  "read":        false,
  "unreadCount": 4
}
```

---

## Error responses

| Status | Cause |
|---|---|
| `400` | Validation failure (missing required fields, empty receivers) |
| `401` | `X-User-Id` header missing on read-path endpoints |
| `502` | Novu returned a non-2xx response |
| `504` | Novu request exceeded `TimeoutSeconds` |

**502 example**

```json
{
  "error": "Novu request failed.",
  "novuStatus": 404
}
```

**504 example**

```json
{
  "error": "Novu request timed out."
}
```

---

## Validated Novu endpoints

The following Novu API paths were verified during the POC and are the only ones used:

| Method | Path | Used for |
|---|---|---|
| `POST` | `/v1/events/trigger` | Send notification |
| `GET` | `/v1/messages?page=&limit=&pageSize=` | Fetch feed / derive unread count |
| `POST` | `/v1/subscribers/{subscriberId}/messages/mark-as` | Mark read / unread |

> **Not used:** `/v1/subscribers/{id}/notifications/feed` and `/v1/subscribers/{id}/notifications/unseen` were **not** validated in the POC and are not called by this API.

---

## Project structure

```
MessageCenter.Api/
├── Audit/
│   ├── IAuditSink.cs              # Audit abstraction
│   └── LoggerAuditSink.cs         # Default: structured log; DB extension point inside
├── Controllers/
│   └── MessageCenterController.cs # All five business endpoints
├── HttpClients/
│   ├── NovuClient.cs              # Typed HTTP client
│   └── Dtos/
│       └── NovuDtos.cs            # Novu response shapes
├── Middleware/
│   └── NovuExceptionMiddleware.cs # 502 / 504 mapping
├── Models/
│   ├── MessageDto.cs              # Feed item DTO
│   ├── SendMessageRequest.cs      # Send request + Receiver
│   └── SendMessageResponse.cs     # Send response
├── Options/
│   └── NovuOptions.cs             # Typed config
├── Services/
│   ├── MessageMapper.cs           # Request → Novu trigger payload mapping
│   └── NovuTriggerPayload.cs      # Mapping result type
├── appsettings.json
└── Program.cs
```

---

## End-to-end test checkpoint

```bash
SUBSCRIBER="EMP001"
BASE="http://localhost:5000"

# 1. Send 5 messages
for i in 1 2 3 4 5; do
  curl -s -X POST $BASE/api/message-center/send \
    -H "Content-Type: application/json" \
    -d "{\"sourceSystem\":\"test\",\"businessType\":\"test\",\"title\":\"Msg $i\",\"receivers\":[{\"type\":\"user\",\"id\":\"$SUBSCRIBER\"}]}"
done

# 2. Get feed — note a messageId from the response
curl -s "$BASE/api/message-center/my" -H "X-User-Id: $SUBSCRIBER"

# 3. Check initial unread count (expect ≥ 5)
curl -s "$BASE/api/message-center/unread-count" -H "X-User-Id: $SUBSCRIBER"

# 4. Mark one message as read (replace with a real messageId)
MESSAGE_ID="<messageId from step 2>"
curl -s -X POST "$BASE/api/message-center/messages/$MESSAGE_ID/read" \
  -H "X-User-Id: $SUBSCRIBER"
# Expect: read=true, unreadCount decreased by 1

# 5. Mark it back as unread
curl -s -X POST "$BASE/api/message-center/messages/$MESSAGE_ID/unread" \
  -H "X-User-Id: $SUBSCRIBER"
# Expect: read=false, unreadCount restored
```
