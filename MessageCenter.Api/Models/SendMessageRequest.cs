using System.ComponentModel.DataAnnotations;

namespace MessageCenter.Api.Models;

public class SendMessageRequest
{
    [Required]
    public string SourceSystem { get; set; } = string.Empty;

    [Required]
    public string BusinessType { get; set; } = string.Empty;

    public string? BusinessId { get; set; }

    [Required]
    public string Title { get; set; } = string.Empty;

    public string? Content { get; set; }

    public string? Url { get; set; }

    [Required, MinLength(1)]
    public List<Receiver> Receivers { get; set; } = new();
}

public class Receiver
{
    [Required]
    public string Type { get; set; } = string.Empty;

    [Required]
    public string Id { get; set; } = string.Empty;
}
