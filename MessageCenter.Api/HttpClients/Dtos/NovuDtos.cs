namespace MessageCenter.Api.HttpClients.Dtos;

public class TriggerResult
{
    public bool Acknowledged { get; set; }
    public string? Status { get; set; }
    public string? TransactionId { get; set; }
}

public class NovuMessageItem
{
    public string? Id { get; set; }
    public NovuMessageContent? Content { get; set; }
    public bool Read { get; set; }
    public bool Seen { get; set; }
    public DateTime? CreatedAt { get; set; }
}

public class NovuMessageContent
{
    public string? Title { get; set; }
    public string? Body { get; set; }
    public string? Url { get; set; }
}

public class FeedResult
{
    public List<NovuMessageItem> Data { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageSize { get; set; }
    public int Page { get; set; }
}
