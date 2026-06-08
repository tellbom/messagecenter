# MessageCenter API — Tasks

Ordered, directly executable. Stack assumption: **ASP.NET Core (.NET 6)** Web API (adjust if different). Each task lists the work and acceptance criteria. Build on the validated Novu POC; do not re-evaluate or expand scope.

---

## T1 — Project scaffold
- Create ASP.NET Core Web API project `MessageCenter.Api`.
- Add `IHttpClientFactory`, options binding, structured logging (Serilog or built-in `ILogger`).
- **Done when:** project builds and serves a `GET /health` returning `200 { "status": "ok" }`.

## T2 — `NovuOptions` configuration
- Add `NovuOptions { BaseUrl, ApiKey, DefaultWorkflowId, InAppChannel, TimeoutSeconds }`.
- Bind from `appsettings.json` section `Novu`; allow env override; `ApiKey` from env/secret.
- Defaults: `BaseUrl=http://192.168.124.2:13000`, `DefaultWorkflowId=system-notification`, `InAppChannel=in_app`, `TimeoutSeconds=10`.
- **Done when:** options resolve via `IOptions<NovuOptions>`; app fails fast on startup if `ApiKey` or `BaseUrl` is missing.

## T3 — `NovuClient` typed HTTP client
- Register typed `NovuClient` with `BaseUrl` and `Timeout = TimeoutSeconds`.
- Attach `Authorization: ApiKey {ApiKey}` to every request.
- Implement:
  - `Task<TriggerResult> TriggerAsync(string workflowId, string subscriberId, object payload, ct)` → `POST /v1/events/trigger`.
  - `Task<FeedResult> GetFeedAsync(int page, int limit, ct)` → `GET /v1/messages?page=&limit=&pageSize=`.
  - `Task MarkAsAsync(string subscriberId, string messageId, bool read, ct)` → `POST /v1/subscribers/{subscriberId}/messages/mark-as` with body `{ "messageId": "...", "mark": { "read": <bool> } }`.
- Unread count is derived from the `GET /v1/messages` result set; there is no separate validated unseen endpoint. Do **not** call `/v1/subscribers/{id}/notifications/feed`, `/v1/subscribers/{id}/notifications/unseen`, or any other subscriber-scoped notification path — these were not validated in the POC.
- **Done when:** each method round-trips against the live Novu instance and deserializes Novu's `{ data: ... }` envelope.

## T4 — Send request model + receiver mapping
- Add `SendMessageRequest { sourceSystem, businessType, businessId, title, content, url, receivers[] }`, `Receiver { type, id }`.
- Validate: `sourceSystem`, `businessType`, `title` required; `receivers` non-empty.
- MVP: process only `type == "user"`; for each, `subscriberId = receiver.id`. Skip non-`user` receivers and record a warning in the response.
- **Done when:** invalid requests return `400` with field-level errors; valid request yields one `subscriberId` per user receiver.

## T5 — Build Novu payload from business fields
- Map `SendMessageRequest` → Novu payload `{ sourceSystem, businessType, businessId, title, content, url }`.
- Use `DefaultWorkflowId` (`system-notification`) as the trigger name in MVP.
- **Done when:** a unit test asserts the example request (`workflow-center`/`process_task`/`TASK_001`) produces the expected trigger body with `to.subscriberId = "EMP001"`.

## T6 — `POST /api/message-center/send`
- Accept `SendMessageRequest`; for each resolved user receiver call `NovuClient.TriggerAsync`.
- Return `{ transactionId, status, acknowledged, accepted: [...], skipped: [...] }`.
- **Done when:** sending to a real subscriber returns `201`-equivalent success and the message appears in that subscriber's Novu feed.

## T7 — `GET /api/message-center/my`
- Params: `page` (default 0), `limit` (default 100). `subscriberId` is resolved from the authenticated user context — it is not a client-supplied parameter.
- Call `NovuClient.GetFeedAsync`; project Novu items to a slim DTO: `{ messageId, title, content, url, read, seen, createdAt }`.
- **Done when:** a subscriber with 5 messages returns 5 items with correct `read` flags; 1 read + 4 unread reflects exactly as validated in the POC.

## T8 — `GET /api/message-center/unread-count`
- No client-supplied params. `subscriberId` is resolved from the authenticated user context.
- Derive unread count from `NovuClient.GetFeedAsync` result (count items where `read=false`). There is no separate validated unseen-count endpoint.
- Return `{ unreadCount }`.
- **Done when:** count matches Novu; decreases by exactly 1 after one read; restores after marking unread.

## T9 — Mark read / unread endpoints
- `POST /api/message-center/messages/{messageId}/read` → `MarkAsAsync(..., read:true)`.
- `POST /api/message-center/messages/{messageId}/unread` → `MarkAsAsync(..., read:false)`.
- `subscriberId` is resolved from the authenticated user context — it is not accepted in the request body.
- Return updated `{ messageId, read, unreadCount }`.
- **Done when:** marking one `messageId` affects only that message; other messages' state is unchanged (matches POC core result).

## T10 — Minimal audit logging
- On every send, emit a structured log entry: `transactionId, sourceSystem, businessType, businessId, subscriberId, novuHttpStatus, status, acknowledged, timestamp`.
- Provide an `IAuditSink` abstraction with a default logging implementation; leave a thin `audit_log` table as a commented extension point (audit only — no message state).
- **Done when:** each send produces exactly one audit entry containing the Novu `transactionId` and status.

## T11 — Error & timeout handling
- Apply `TimeoutSeconds` to the typed client.
- Map Novu non-2xx → `502` with `{ error, novuStatus, transactionId? }`; timeout/cancellation → `504`.
- No automatic retries in MVP (avoid duplicate sends); leave a Polly registration point.
- **Done when:** simulated Novu failure returns `502` (not `500`) and a forced timeout returns `504`, both logged.

## T12 — README documentation
- Document: Novu API base URL/port (`http://192.168.124.2:13000`), workflow trigger identifier (`system-notification`), in-app channel, required `appsettings`/env keys.
- List validated/used Novu endpoints (`POST /v1/events/trigger`, `GET /v1/messages`, `POST /v1/subscribers/{subscriberId}/messages/mark-as`) and the `system-notification` template prerequisite (`payload.title/content/url`). Explicitly note that `/v1/subscribers/{id}/notifications/feed` and `/v1/subscribers/{id}/notifications/unseen` were **not** validated and are not used.
- Include curl/HTTP examples for all five `MessageCenter` endpoints.
- **Done when:** a new developer can configure and run the API and successfully send + read a message following the README only.

---

### Test checkpoint (mirrors POC)
Send 5 messages to one subscriber → mark 1 as read → assert: that message `read=true`, other 4 `read=false`, `unreadCount` dropped by exactly 1 → mark it unread → assert count restored.
