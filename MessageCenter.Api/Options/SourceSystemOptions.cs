namespace MessageCenter.Api.Options;

public class SourceSystemOptions
{
    public const string Section = "SourceSystemNames";

    public Dictionary<string, string> Names { get; set; } = new();
}
