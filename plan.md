# MessageCenter API — Implementation Plan

## 1. Context

The Novu POC has passed end-to-end validation. Novu is confirmed as the **source of truth** for in-app message state (read/unread/seen, unread count, real-time delivery). This plan covers only a **lightweight `MessageCenter API` wrapper** in front of Novu.

We do **not** re-evaluate Novu, do **not** add a second message database, and do **not** reimplement read/unread/unread-count/real-time.

```text
Novu API:                http://192.168.124.2:13000
Workflow Trigger Id:     system-notification
In-App channel:          in_app
```

## 2. Architecture boundary

```text
Backend services ──► MessageCenter API ──► Novu (trigger)         [send path]
Web UI           ──► MessageCenter API ──► Novu (query/mark)      [read path]
```

- **Novu** owns: message storage, read/unread, seen, unread count, real-time push.
- **MessageCenter API** owns: business-facing contract, `businessType`/`sourceSystem` mapping, payload normalization, receiver→subscriber mapping, Novu abstraction, minimal audit logging.

## 3. Tech assumptions (adjustable)

- **ASP.NET Core (.NET 6) Web API**, C#. Inferred from `NovuOptions`/`NovuClient` + Options pattern. Swap if your stack differs — the task list maps cleanly to any HTTP-client framework.
- `HttpClient` via `IHttpClientFactory`, typed client `NovuClient`.
- Config via `IOptions<NovuOptions>` (`appsettings.json` + env override).
- No persistence in MVP beyond optional thin audit records.

## 4. Components

### 4.1 `NovuOptions`
```text
BaseUrl              = http://192.168.124.2:13000
ApiKey               (secret; from env / appsettings)
DefaultWorkflowId    = system-notification
InAppChannel         = in_app
TimeoutSeconds       = 10
```
Auth header on every Novu call: `Authorization: ApiKey {ApiKey}`.

### 4.2 `NovuClient` (Novu abstraction)
| Method | Novu call |
|---|---|
| `TriggerAsync(workflowId, subscriberId, payload)` | `POST /v1/events/trigger` |
| `GetFeedAsync(page, limit)` | `GET /v1/messages?page=&limit=&pageSize=` |
| `GetUnreadCountAsync(subscriberId)` | `GET /v1/messages?page=0&limit=100&pageSize=100` (derive count from result set) |
| `MarkAsAsync(subscriberId, messageId, read:bool)` | `POST /v1/subscribers/{subscriberId}/messages/mark-as` |

> Note: `GET /v1/messages` is the validated POC endpoint for message retrieval. The subscriber-scoped paths `/v1/subscribers/{id}/notifications/feed` and `/v1/subscribers/{id}/notifications/unseen` were **not** validated in the POC and must not be used.

### 4.3 Business-facing endpoints
```text
POST /api/message-center/send                          (backend services only)
GET  /api/message-center/my?page=&limit=
GET  /api/message-center/unread-count
POST /api/message-center/messages/{messageId}/read
POST /api/message-center/messages/{messageId}/unread
```

`subscriberId` is resolved server-side from the authenticated user context (JWT / Gateway / UserContext) on all read-path endpoints. It is never accepted as a client-supplied query parameter or request body field.

### 4.4 Send contract → Novu mapping
Inbound request:
```json
{
  "sourceSystem": "workflow-center",
  "businessType": "process_task",
  "businessId": "TASK_001",
  "title": "You have a new workflow task",
  "content": "Please process the inspection approval workflow",
  "url": "/process/tasks/TASK_001",
  "receivers": [{ "type": "user", "id": "EMP001" }]
}
```
Maps to Novu trigger (one trigger per user receiver):
```json
{
  "name": "system-notification",
  "to": { "subscriberId": "EMP001" },
  "payload": {
    "sourceSystem": "workflow-center",
    "businessType": "process_task",
    "businessId": "TASK_001",
    "title": "...",
    "content": "...",
    "url": "/process/tasks/TASK_001"
  }
}
```
- MVP: only `receivers[].type == "user"`; `id` is used directly as Novu `subscriberId`. Reject/skip non-`user` types with a clear message.
- Novu upserts the subscriber on trigger, so receivers need not be pre-provisioned.
- The `system-notification` in-app step template must reference `{{payload.title}}`, `{{payload.content}}`, and redirect `{{payload.url}}` (already configured in the POC — listed as a precondition).

### 4.5 Minimal audit logging
Log per send: `transactionId`, `sourceSystem`, `businessType`, `businessId`, target `subscriberId`, Novu HTTP status, `acknowledged`/`status`. Structured logging by default; optional thin `audit_log` table as an extension point (audit only — **not** message state).

### 4.6 Error / timeout handling
- `HttpClient` timeout = `TimeoutSeconds`.
- Novu `2xx` → success; non-2xx → map to `502 Bad Gateway`; timeout → `504 Gateway Timeout`.
- All responses include `transactionId` (from Novu) where available.
- No silent retries in MVP (avoid duplicate sends); leave a Polly extension point.

## 5. Preconditions
1. Novu reachable at `http://192.168.124.2:13000` with a valid API key.
2. Workflow `system-notification` exists, active, with an in-app step bound to `payload.title/content/url`.
3. Receiver `id` values correspond to Novu `subscriberId` values.

## 6. Out of scope (MVP)
Chat/IM, group/file messages, RBAC/roles/menu/policy authorization, custom MongoDB message store, duplicating Novu state, custom WebSocket, custom read/unread or unread-count logic, admin UI, department/role receiver expansion, multiple per-system workflows.

## 7. Extension points (documented, not built)
Department/role receiver expansion · per-business-type workflows · idempotency key from `businessId` · audit table + query · RBAC on the read path.
