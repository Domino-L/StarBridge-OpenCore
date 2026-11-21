using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;

/// <summary>
/// Account plan item 13: two relay refusals of community writes are explained instead of
/// being shown as an uncertain outcome or a taken code. Fixtures use example.invalid data only.
/// </summary>
internal static class CommunityRelayRefusalTests
{
    private const string AmbiguousBody =
        "{\"code\":\"IDENTITY_AMBIGUOUS\",\"error\":\"synthetic relay text that is never forwarded\"}";

    internal static async Task Verify()
    {
        await VerifyReader();
        await VerifyExecute();
        await VerifyCreation();
        await VerifyBodyLimits();
    }

    private static async Task VerifyReader()
    {
        async Task<string?> Read(HttpStatusCode status, string? body = null)
        {
            using var response = new HttpResponseMessage(status);
            if (body is not null) response.Content = new StringContent(body, Encoding.UTF8, "application/json");
            return await CommunityRelayRefusal.ReasonAsync(response, default);
        }
        Check(await Read(HttpStatusCode.PreconditionRequired) == "identityRequired", "bare 428 means game identity required");
        Check(await Read(HttpStatusCode.Conflict, AmbiguousBody) == "identityAmbiguous", "named 409 is the ambiguous identity refusal");
        Check(await Read(HttpStatusCode.Conflict) is null, "a bare 409 keeps its existing meaning");
        Check(await Read(HttpStatusCode.Conflict, "{\"code\":\"OTHER\"}") is null, "another 409 code keeps its existing meaning");
        Check(await Read(HttpStatusCode.Conflict, "{\"code\":\"identity_ambiguous\"}") is null, "the code is matched exactly");
        Check(await Read(HttpStatusCode.Conflict, "[\"IDENTITY_AMBIGUOUS\"]") is null, "a non-object body is ignored");
        Check(await Read(HttpStatusCode.Conflict, "{\"code\":1}") is null, "a non-string code is ignored");
        Check(await Read(HttpStatusCode.Conflict, "not json") is null, "malformed JSON is ignored");
        Check(await Read(HttpStatusCode.Conflict, "{\"code\":\"IDENTITY_AMBIGUOUS\",\"pad\":\"" + new string('x', 5000) + "\"}") is null,
            "an oversized body is not read past the limit");
        Check(await Read(HttpStatusCode.BadRequest, AmbiguousBody) is null, "only 409 bodies are read");
    }

    private static async Task VerifyExecute()
    {
        var cases = new (string Action, HttpStatusCode Status, string? Body, string Expected, string Error)[]
        {
            ("join", HttpStatusCode.PreconditionRequired, null, "rejected", "identityRequired"),
            ("join", HttpStatusCode.Conflict, AmbiguousBody, "rejected", "identityAmbiguous"),
            ("leave", HttpStatusCode.Conflict, AmbiguousBody, "rejected", "identityAmbiguous"),
            ("join", HttpStatusCode.Conflict, null, "unknown", "refreshRequired"),
        };
        foreach (var item in cases)
        {
            var writes = 0;
            var member = item.Action == "leave";
            using var handler = new Handler(request =>
            {
                if (request.Method == HttpMethod.Post)
                {
                    writes++;
                    return Task.FromResult(Reply(item.Status, item.Body));
                }
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new
                {
                    schemaVersion = 1, membershipModelVersion = 2, directoryVersion = 2, totalCount = 1, view = "discover", query = "",
                    next = (string?)null,
                    items = new[] { new { code = "SYN", name = "Synthetic organization", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = member ? "member" : "none", joinMode = "direct",
                        actions = new[] { member ? "leave" : "join" }, logoImageData = (string?)null } }
                }) });
            });
            using var client = new CommunityClient(new Uri("https://communities.example.invalid"), handler);
            var page = await client.ReadAsync("scm-only", new("discover", "", null, null), "SCM:1", default);
            var command = JsonSerializer.SerializeToElement(new { schemaVersion = 1, action = item.Action, targetRef = page.Items[0].TargetRef });
            var result = await client.ExecuteAsync("scm-only", command, "SCM:1", () => { }, default);
            var label = item.Action + " " + (int)item.Status + (item.Body is null ? " bare" : " named");
            Check(result.Status == item.Expected && result.Error == item.Error && writes == 1, "execute maps relay refusal: " + label);
            var replay = await client.ExecuteAsync("scm-only", command, "SCM:1", () => { }, default);
            Check(replay.Status == "rejected" && writes == 1, "a refused target is not replayed: " + label);
        }
    }

    private static async Task VerifyCreation()
    {
        var cases = new (HttpStatusCode Status, string? Body, string Error)[]
        {
            (HttpStatusCode.PreconditionRequired, null, "identityRequired"),
            (HttpStatusCode.Conflict, AmbiguousBody, "identityAmbiguous"),
            (HttpStatusCode.Conflict, null, "codeUnavailable"),
        };
        foreach (var item in cases)
        {
            var writes = 0;
            using var handler = new Handler(request =>
            {
                Check(request.Method == HttpMethod.Post, "a refused creation is not confirmed by a read");
                writes++;
                return Task.FromResult(Reply(item.Status, item.Body));
            });
            using var client = new CommunityClient(new Uri("https://communities.example.invalid"), handler);
            var command = Creation(Guid.NewGuid().ToString("N"));
            var result = await client.CreateAsync("scm-only", command, "SCM:1", () => { }, default);
            Check(result.Status == "rejected" && result.Error == item.Error, "creation maps relay refusal: " + item.Error);
            var again = await client.CreateAsync("scm-only", command, "SCM:1", () => { }, default);
            Check(again.Error == item.Error && writes == 1, "the same refused intent is answered without sending again: " + item.Error);
        }
    }

    private static async Task VerifyBodyLimits()
    {
        var endless = new CountingStream(stall: false);
        using (var response = new HttpResponseMessage(HttpStatusCode.Conflict) { Content = new StreamContent(endless) })
        {
            Check(response.Content.Headers.ContentLength is null, "the fixture sends no length header");
            Check(await CommunityRelayRefusal.ReasonAsync(response, default) is null, "an endless body is not a refusal");
        }
        Check(endless.Served <= 4097, "at most one byte past the 4 KB limit is read: " + endless.Served);

        HttpResponseMessage Stalled() =>
            new(HttpStatusCode.Conflict) { Content = new StreamContent(new CountingStream(stall: true)) };

        // The body's own short timeout: the 409 keeps the caller's plain meaning.
        using (var response = Stalled())
        {
            Check(await CommunityRelayRefusal.ReasonAsync(response, default, TimeSpan.FromMilliseconds(100)) is null,
                "a body that times out on its own leaves the caller's own 409 meaning");
        }

        // A cancellation by the caller is not a timeout: it keeps propagating.
        using (var response = Stalled())
        using (var caller = new CancellationTokenSource(TimeSpan.FromMilliseconds(100)))
        {
            var cancelled = false;
            try { await CommunityRelayRefusal.ReasonAsync(response, caller.Token, TimeSpan.FromSeconds(30)); }
            catch (OperationCanceledException) { cancelled = true; }
            Check(cancelled, "a caller cancellation during the body read is not swallowed");
        }

        // Creation, body timeout: the plain conflict is the answer and is cached.
        var writes = 0;
        using var handler = new Handler(request =>
        {
            writes++;
            return Task.FromResult(Stalled());
        });
        using var client = new CommunityClient(new Uri("https://communities.example.invalid"), handler);
        var command = Creation(Guid.NewGuid().ToString("N"));
        var result = await client.CreateAsync("scm-only", command, "SCM:1", () => { }, default);
        Check(result.Status == "rejected" && result.Error == "codeUnavailable",
            "a 409 whose body times out keeps the plain conflict outcome: " + result.Error);
        var again = await client.CreateAsync("scm-only", command, "SCM:1", () => { }, default);
        Check(again.Error == "codeUnavailable" && writes == 1, "the cached result is the plain conflict and nothing is sent again");

        // Creation, caller cancellation: never recorded as a definite conflict.
        var cancelledCommand = Creation(Guid.NewGuid().ToString("N"));
        string? outcome = null;
        using (var caller = new CancellationTokenSource(TimeSpan.FromMilliseconds(200)))
        {
            try { outcome = (await client.CreateAsync("scm-only", cancelledCommand, "SCM:1", () => { }, caller.Token)).Error; }
            catch (OperationCanceledException) { outcome = "cancelled"; }
        }
        Check(outcome is not "codeUnavailable", "a caller cancellation is not answered as a conflict: " + outcome);
        var retry = await client.CreateAsync("scm-only", cancelledCommand, "SCM:1", () => { }, default);
        Check(retry.Error != "codeUnavailable" && writes == 2,
            "the cancelled intent is not cached as a conflict and is not sent again: " + retry.Error);
    }

    /// Endless synthetic body: either serves 'x' bytes and counts them, or never answers.
    private sealed class CountingStream(bool stall) : Stream
    {
        internal long Served { get; private set; }
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override int Read(byte[] buffer, int offset, int count) => Read(buffer.AsSpan(offset, count));
        public override int Read(Span<byte> buffer)
        {
            buffer.Fill((byte)'x');
            Served += buffer.Length;
            return buffer.Length;
        }
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (stall) await Task.Delay(Timeout.Infinite, cancellationToken);
            return Read(buffer.Span);
        }
        public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
            ReadAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();
    }

    private static HttpResponseMessage Reply(HttpStatusCode status, string? body)
    {
        var response = new HttpResponseMessage(status);
        if (body is not null) response.Content = new StringContent(body, Encoding.UTF8, "application/json");
        return response;
    }

    private static JsonElement Creation(string id) => JsonSerializer.SerializeToElement(new
    {
        schemaVersion = 1, requestId = id.PadLeft(32, '0'), draft = new
        {
            schemaVersion = 1, name = "Synthetic Organization", code = "SYNORG", description = "", joinPolicy = "Open",
            tagIds = new[] { "combat_pvp" }, activeSystemIds = new[] { "stanton" }, activeFrom = "19:00", activeTo = "22:00",
            timeZoneId = "UTC"
        }
    });

    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request);
    }
}
