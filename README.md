# MessageCenter API

一个轻量级的 ASP.NET Core 6 封装库，基于 [Novu](https://novu.co) 提供面向业务方的应用内通知发送和读取接口。

---

## 前置要求

| 要求 | 值 |
|---|---|
| .NET SDK | 6.0 |
| Novu 服务地址 | `http://192.168.124.2:13000` |
| Novu 工作流 | `system-notification`（已激活，且配置了 in-app 步骤） |
| Novu API Key | 从 Novu 控制台 → API Keys 获取 |

### Novu 工作流模板前置条件

`system-notification` 工作流的 **in-app 步骤** 必须引用以下 payload 变量：

```
{{payload.title}}    — 消息标题
{{payload.content}}  — 消息正文
{{payload.url}}      — 跳转链接（CTA）
```

此配置已在 POC 阶段完成，是硬性前提。即使模板中缺少这些变量，API 也不会报错，但通知将无法正常展示内容。

---

## 配置

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

`ApiKey` **禁止** 提交到源码仓库。请通过环境变量提供：

```bash
# Linux / macOS
export Novu__ApiKey=your_api_key_here

# Windows (PowerShell)
$env:Novu__ApiKey = "your_api_key_here"
```

启动时若 `ApiKey` 或 `BaseUrl` 为空或缺失，应用会抛出 `InvalidOperationException`。

---

## 运行 API

```bash
cd MessageCenter.Api
Novu__ApiKey=your_api_key_here dotnet run
```

验证服务是否启动：

```bash
curl http://localhost:5000/health
# 200 {"status":"ok"}
```

---

## 接口列表

所有读取类接口均需要携带 `X-User-Id` 请求头，值为对应用户的 Novu `subscriberId`（由 API 网关注入）。

> **TODO**：后续添加认证中间件后，将替换为从 JWT Claim 中提取。

---

### 1. 发送消息

`POST /api/message-center/send`

为每个接收用户触发 Novu `system-notification` 工作流。主要供后端服务调用。

**请求示例**

```bash
curl -X POST http://localhost:5000/api/message-center/send \
  -H "Content-Type: application/json" \
  -d '{
    "sourceSystem": "workflow-center",
    "businessType": "process_task",
    "businessId":   "TASK_001",
    "title":        "您有一条新的工作流任务",
    "content":      "请处理检验审批工作流",
    "url":          "/process/tasks/TASK_001",
    "receivers": [
      { "type": "user", "id": "EMP001" }
    ]
  }'
```

**响应 `201`**

```json
{
  "transactionId": "abc123",
  "status": "processed",
  "acknowledged": true,
  "accepted": ["EMP001"],
  "skipped": []
}
```

**说明**

- 当前 MVP 阶段仅支持 `receivers[].type == "user"`，其他类型将被跳过并记录在 `skipped` 中。
- Novu 会自动 upsert subscriber，接收者无需提前创建。
- 必填字段：`sourceSystem`、`businessType`、`title`、`receivers`（不能为空）。

---

### 2. 获取我的消息

`GET /api/message-center/my`

返回当前认证用户的通知列表。

**请求示例**

```bash
curl http://localhost:5000/api/message-center/my \
  -H "X-User-Id: EMP001"

# 分页（默认 page=0, limit=100）
curl "http://localhost:5000/api/message-center/my?page=0&limit=10" \
  -H "X-User-Id: EMP001"
```

**响应 `200`**

```json
[
  {
    "messageId": "6a27771843f156a3e5a9891f",
    "title":     "您有一条新的工作流任务",
    "content":   "请处理检验审批工作流",
    "url":       "/process/tasks/TASK_001",
    "read":      false,
    "seen":      false,
    "createdAt": "2026-01-01T00:00:00Z"
  }
]
```

---

### 3. 获取未读数量

`GET /api/message-center/unread-count`

返回当前用户的未读消息数。

**响应 `200`**

```json
{
  "unreadCount": 4
}
```

---

### 4. 标记消息为已读

`POST /api/message-center/messages/{messageId}/read`

**响应 `200`**

```json
{
  "messageId":   "6a27771843f156a3e5a9891f",
  "read":        true,
  "unreadCount": 3
}
```

---

### 5. 标记消息为未读

`POST /api/message-center/messages/{messageId}/unread`

**响应 `200`**

```json
{
  "messageId":   "6a27771843f156a3e5a9891f",
  "read":        false,
  "unreadCount": 4
}
```

---

## 错误响应

| 状态码 | 原因 |
|---|---|
| `400` | 参数校验失败（必填字段缺失、receivers 为空等） |
| `401` | 读取类接口缺少 `X-User-Id` 请求头 |
| `502` | Novu 返回非 2xx 响应 |
| `504` | Novu 请求超时 |

---

## 已验证的 Novu 接口

本 API 仅使用以下经过 POC 验证的 Novu 接口：

| 方法 | 路径 | 用途 |
|---|---|---|
| `POST` | `/v1/events/trigger` | 发送通知 |
| `GET` | `/v1/messages?page=&limit=&pageSize=` | 获取消息列表 / 计算未读数 |
| `POST` | `/v1/subscribers/{subscriberId}/messages/mark-as` | 标记已读/未读 |

---

## 项目结构

```
MessageCenter.Api/
├── Audit/
│   ├── IAuditSink.cs
│   └── LoggerAuditSink.cs
├── Controllers/
│   └── MessageCenterController.cs
├── HttpClients/
│   ├── NovuClient.cs
│   └── Dtos/
│       └── NovuDtos.cs
├── Middleware/
│   └── NovuExceptionMiddleware.cs
├── Models/
│   ├── MessageDto.cs
│   ├── SendMessageRequest.cs
│   └── SendMessageResponse.cs
├── Options/
│   └── NovuOptions.cs
├── Services/
│   ├── MessageMapper.cs
│   └── NovuTriggerPayload.cs
├── appsettings.json
└── Program.cs
```

---

## 端到端测试检查点

```bash
SUBSCRIBER="EMP001"
BASE="http://localhost:5000"

# 1. 发送 5 条测试消息
for i in 1 2 3 4 5; do
  curl -s -X POST $BASE/api/message-center/send \
    -H "Content-Type: application/json" \
    -d "{\"sourceSystem\":\"test\",\"businessType\":\"test\",\"title\":\"测试消息 $i\",\"receivers\":[{\"type\":\"user\",\"id\":\"$SUBSCRIBER\"}]}"
done

# 2. 获取消息列表（记录 messageId）
curl -s "$BASE/api/message-center/my" -H "X-User-Id: $SUBSCRIBER"

# 3. 检查未读数（应 ≥ 5）
curl -s "$BASE/api/message-center/unread-count" -H "X-User-Id: $SUBSCRIBER"
```
