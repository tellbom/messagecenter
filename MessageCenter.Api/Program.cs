using MessageCenter.Api.Audit;
using MessageCenter.Api.HttpClients;
using MessageCenter.Api.Middleware;
using MessageCenter.Api.Options;
using System.Net.Http.Headers;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.Configure<NovuOptions>(
    builder.Configuration.GetSection(NovuOptions.Section));
builder.Services.AddHttpClient<NovuClient>((sp, client) =>
{
    var novuOptions = sp.GetRequiredService<IOptions<NovuOptions>>().Value;

    client.BaseAddress = new Uri(novuOptions.BaseUrl, UriKind.Absolute);
    client.Timeout = TimeSpan.FromSeconds(novuOptions.TimeoutSeconds);
    client.DefaultRequestHeaders.Authorization =
        new AuthenticationHeaderValue("ApiKey", novuOptions.ApiKey);
});
// Polly extension point: add .AddPolicyHandler(...) to the NovuClient IHttpClientBuilder when retries are introduced.
builder.Services.AddSingleton<IAuditSink, LoggerAuditSink>();

var app = builder.Build();

var novu = app.Services.GetRequiredService<IOptions<NovuOptions>>().Value;
if (string.IsNullOrWhiteSpace(novu.BaseUrl))
{
    throw new InvalidOperationException("Novu:BaseUrl is required.");
}

if (string.IsNullOrWhiteSpace(novu.ApiKey))
{
    throw new InvalidOperationException("Novu:ApiKey is required.");
}

app.UseMiddleware<NovuExceptionMiddleware>();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapControllers();

app.Run();
