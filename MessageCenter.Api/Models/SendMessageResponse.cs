namespace MessageCenter.Api.Models;

public class SendMessageResponse
{
    public string? TransactionId { get; init; }
    public string? Status { get; init; }
    public bool Acknowledged { get; init; }
    public IReadOnlyList<string> Accepted { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> Skipped { get; init; } = Array.Empty<string>();
}
