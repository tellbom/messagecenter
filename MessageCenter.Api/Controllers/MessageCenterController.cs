using MessageCenter.Api.HttpClients;
using MessageCenter.Api.Models;
using MessageCenter.Api.Options;
using MessageCenter.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace MessageCenter.Api.Controllers;

[ApiController]
[Route("api/message-center")]
public class MessageCenterController : ControllerBase
{
    private readonly NovuClient _novu;
    private readonly NovuOptions _options;
    private readonly ILogger<MessageCenterController> _logger;

    public MessageCenterController(
        NovuClient novu,
        IOptions<NovuOptions> options,
        ILogger<MessageCenterController> logger)
    {
        _novu = novu;
        _options = options.Value;
        _logger = logger;
    }

    [HttpPost("send")]
    public async Task<IActionResult> Send(
        [FromBody] SendMessageRequest request,
        CancellationToken ct)
    {
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

            _logger.LogInformation(
                "Novu trigger sent. TransactionId={TransactionId} SubscriberId={SubscriberId} Status={Status} Acknowledged={Acknowledged}",
                result.TransactionId,
                trigger.SubscriberId,
                result.Status,
                result.Acknowledged);
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
        // TODO: replace header resolution with JWT claim extraction when auth middleware is added.
        var subscriberId = Request.Headers["X-User-Id"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(subscriberId))
        {
            return Unauthorized(new { error = "X-User-Id header is required." });
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
}
