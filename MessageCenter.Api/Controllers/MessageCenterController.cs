using System.Security.Claims;
using MessageCenter.Api.Audit;
using MessageCenter.Api.HttpClients;
using MessageCenter.Api.Models;
using MessageCenter.Api.Options;
using MessageCenter.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace MessageCenter.Api.Controllers;

[ApiController]
[Route("api/message-center")]
[Authorize]
public class MessageCenterController : ControllerBase
{
    private readonly NovuClient _novu;
    private readonly NovuOptions _options;
    private readonly IAuditSink _audit;

    public MessageCenterController(
        NovuClient novu,
        IOptions<NovuOptions> options,
        IAuditSink audit)
    {
        _novu = novu;
        _options = options.Value;
        _audit = audit;
    }

    [HttpPost("send")]
    public async Task<IActionResult> Send(
        [FromBody] SendMessageRequest request,
        CancellationToken ct)
    {
        var sourceSystem = GetPreferredUsername();
        if (sourceSystem is null)
        {
            return Unauthorized(new { error = "preferred_username claim is missing from token." });
        }

        request.SourceSystem = sourceSystem;
        var triggers = MessageMapper.Map(request, _options.DefaultWorkflowId, out var skipped);

        if (triggers.Count == 0)
        {
            return BadRequest(new
            {
                error = "No actionable receivers. All receivers were skipped.",
                skipped
            });
        }

        var accepted = new List<string>();
        string? transactionId = null;
        string? status = null;
        var acknowledged = false;

        foreach (var trigger in triggers)
        {
            var result = await _novu.TriggerAsync(
                trigger.WorkflowId,
                trigger.SubscriberId,
                trigger.Payload,
                ct);

            accepted.Add(trigger.SubscriberId);
            transactionId = result.TransactionId;
            status = result.Status;
            acknowledged = result.Acknowledged;

            _audit.Record(new AuditEntry(
                result.TransactionId,
                sourceSystem,
                request.BusinessType,
                request.BusinessId,
                trigger.SubscriberId,
                StatusCodes.Status200OK,
                result.Status,
                result.Acknowledged,
                DateTime.UtcNow));
        }

        var response = new SendMessageResponse
        {
            TransactionId = transactionId,
            Status = status,
            Acknowledged = acknowledged,
            Accepted = accepted,
            Skipped = skipped
        };

        return StatusCode(StatusCodes.Status201Created, response);
    }

    [HttpGet("my")]
    public async Task<IActionResult> GetMyMessages(
        [FromQuery] int page = 0,
        [FromQuery] int limit = 100,
        CancellationToken ct = default)
    {
        var subscriberId = GetPreferredUsername();
        if (subscriberId is null)
        {
            return Unauthorized(new { error = "preferred_username claim is missing from token." });
        }

        var feed = await _novu.GetFeedAsync(page, limit, ct);
        var messages = feed.Data.Select(message => new
        {
            messageId = message.Id,
            title = message.Subject,
            content = message.Content,
            url = message.Cta?.Data?.Url,
            read = message.Read,
            seen = message.Seen,
            createdAt = message.CreatedAt
        }).ToList();

        return Ok(messages);
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> GetUnreadCount(CancellationToken ct)
    {
        var subscriberId = GetPreferredUsername();
        if (subscriberId is null)
        {
            return Unauthorized(new { error = "preferred_username claim is missing from token." });
        }

        var feed = await _novu.GetFeedAsync(page: 0, limit: 100, ct);
        var unreadCount = feed.Data.Count(message => !message.Read);

        return Ok(new { unreadCount });
    }

    [HttpPost("messages/{messageId}/read")]
    public async Task<IActionResult> MarkRead(string messageId, CancellationToken ct)
        => await MarkAs(messageId, read: true, ct);

    [HttpPost("messages/{messageId}/unread")]
    public async Task<IActionResult> MarkUnread(string messageId, CancellationToken ct)
        => await MarkAs(messageId, read: false, ct);

    private async Task<IActionResult> MarkAs(string messageId, bool read, CancellationToken ct)
    {
        var subscriberId = GetPreferredUsername();
        if (subscriberId is null)
        {
            return Unauthorized(new { error = "preferred_username claim is missing from token." });
        }

        await _novu.MarkAsAsync(subscriberId, messageId, read, ct);

        var feed = await _novu.GetFeedAsync(page: 0, limit: 100, ct);
        var unreadCount = feed.Data.Count(message => !message.Read);
        var updated = feed.Data.FirstOrDefault(message => message.Id == messageId);

        return Ok(new
        {
            messageId,
            read = updated?.Read ?? read,
            unreadCount
        });
    }

    private string? GetPreferredUsername()
        => User.FindFirstValue("preferred_username");
}
