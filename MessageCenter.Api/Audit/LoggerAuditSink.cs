namespace MessageCenter.Api.Audit;

public class LoggerAuditSink : IAuditSink
{
    private readonly ILogger<LoggerAuditSink> _logger;

    public LoggerAuditSink(ILogger<LoggerAuditSink> logger)
    {
        _logger = logger;
    }

    public void Record(AuditEntry entry)
    {
        _logger.LogInformation(
            "AUDIT send. TransactionId={TransactionId} SourceSystem={SourceSystem} BusinessType={BusinessType} BusinessId={BusinessId} SubscriberId={SubscriberId} NovuHttpStatus={NovuHttpStatus} Status={Status} Acknowledged={Acknowledged} Timestamp={Timestamp}",
            entry.TransactionId,
            entry.SourceSystem,
            entry.BusinessType,
            entry.BusinessId,
            entry.SubscriberId,
            entry.NovuHttpStatus,
            entry.Status,
            entry.Acknowledged,
            entry.Timestamp);

        // Extension point: persist this entry to an audit_log table in a DB-backed sink.
    }
}
