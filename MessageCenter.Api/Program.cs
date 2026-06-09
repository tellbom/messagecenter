using MessageCenter.Api.Audit;
using MessageCenter.Api.HttpClients;
using MessageCenter.Api.Middleware;
using MessageCenter.Api.Options;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using System.Net.Http.Headers;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.Configure<NovuOptions>(
    builder.Configuration.GetSection(NovuOptions.Section));
builder.Services.Configure<SourceSystemOptions>(options =>
{
    builder.Configuration.GetSection(SourceSystemOptions.Section).Bind(options.Names);
});
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
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Jwt:Authority"]
            ?? throw new InvalidOperationException("Jwt:Authority is not configured.");
        options.RequireHttpsMetadata = builder.Configuration.GetValue<bool>("Jwt:RequireHttpsMetadata");
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = false,
            ValidateLifetime = true,
            RequireSignedTokens = true,
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });
builder.Services.AddAuthorization();

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

var sourceSystemOptions = app.Services.GetRequiredService<IOptions<SourceSystemOptions>>().Value;
if (sourceSystemOptions.Names.Count == 0)
{
    throw new InvalidOperationException("SourceSystemNames is empty. At least one client mapping is required.");
}

app.UseMiddleware<NovuExceptionMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapControllers();

app.Run();
