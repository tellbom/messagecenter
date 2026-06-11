using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using MessageCenter.Api.HttpClients.Dtos;

namespace MessageCenter.Api.HttpClients;

public class NovuClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly HttpClient _http;

    public NovuClient(HttpClient http)
    {
        _http = http;
    }

    public async Task<TriggerResult> TriggerAsync(
        string workflowId,
        string subscriberId,
        object payload,
        CancellationToken ct = default)
    {
        var body = new
        {
            name = workflowId,
            to = new { subscriberId },
            payload
        };

        var response = await _http.PostAsJsonAsync("/v1/events/trigger", body, JsonOptions, ct);
        response.EnsureSuccessStatusCode();

        var envelope = await response.Content.ReadFromJsonAsync<NovuEnvelope<TriggerResult>>(
            JsonOptions,
            ct);

        return envelope?.Data ?? throw new InvalidOperationException("Empty trigger response from Novu.");
    }

    public async Task<FeedResult> GetFeedAsync(
        int page,
        int limit,
        string? subscriberId = null,
        CancellationToken ct = default)
    {
        var url = $"/v1/messages?page={page}&limit={limit}&pageSize={limit}";
        if (!string.IsNullOrWhiteSpace(subscriberId))
        {
            url += $"&subscriberId={Uri.EscapeDataString(subscriberId)}";
        }

        var response = await _http.GetAsync(url, ct);
        response.EnsureSuccessStatusCode();

        var envelope = await response.Content.ReadFromJsonAsync<NovuEnvelope<List<NovuMessageItem>>>(
            JsonOptions,
            ct);

        return new FeedResult
        {
            Data = envelope?.Data ?? new List<NovuMessageItem>(),
            HasMore = envelope?.HasMore ?? false,
            TotalCount = envelope?.TotalCount ?? 0,
            PageSize = envelope?.PageSize ?? 0,
            Page = envelope?.Page ?? page
        };
    }

    public async Task MarkAsAsync(
        string subscriberId,
        string messageId,
        bool read,
        CancellationToken ct = default)
    {
        var body = new
        {
            messageId,
            markAs = read ? "read" : "unread"
        };

        var url = $"/v1/subscribers/{Uri.EscapeDataString(subscriberId)}/messages/mark-as";
        var response = await _http.PostAsJsonAsync(url, body, JsonOptions, ct);
        response.EnsureSuccessStatusCode();
    }

    private class NovuEnvelope<T>
    {
        public T? Data { get; set; }
        public int TotalCount { get; set; }
        public int PageSize { get; set; }
        public int Page { get; set; }
        public bool HasMore { get; set; }
    }
}
