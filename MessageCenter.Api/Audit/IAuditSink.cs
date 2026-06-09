namespace MessageCenter.Api.Audit;

public record AuditEntry(
    string? TransactionId,
    string SourceSystem,
    string BusinessType,
    string? BusinessId,
    string SubscriberId,
    int NovuHttpStatus,
    string? Status,
    bool Acknowledged,
    DateTime Timestamp);

public interface IAuditSink
{
    void Record(AuditEntry entry);
}
