using System.Net;
using System.Net.Http.Json;
using StarBridge.Core.ShipMedia;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Hangar;

internal static class HangarMediaTransportTests
{
    internal static async Task Verify()
    {
        await HangarImagePublicationTests.Verify();
        await ScmHangarImageDraftTests.RunAsync();
        using var transport = new Transport();
        using var client = new HangarMediaClient(new Uri("https://media.example.invalid"), transport);
        var image = new ShipMediaUploadRequestContract("ship-one", "test-code", "Synthetic", "AA==", Guid.NewGuid().ToString("N"));
        var receipt = await client.UploadAsync("synthetic-token", "owner", image, () => { }, default);
        Check(receipt.OwnerAccountId == "owner" && transport.Calls == 1, "one upload with verified receipt");
        foreach (var mode in new[] { "foreign-owner", "foreign-ship", "wrong-status", "malformed", "offline" })
        {
            transport.Mode = mode;
            var before = transport.Calls;
            await Reject(() => client.UploadAsync("synthetic-token", "owner", image, () => { }, default), "hangar.image_outcome_unknown");
            Check(transport.Calls == before + 1, "uncertain upload is never replayed: " + mode);
        }
        transport.Mode = "forbidden";
        await Reject(() => client.UploadAsync("synthetic-token", "owner", image, () => { }, default), "hangar.image_not_allowed");
        transport.Mode = "foreign-owner";
        await Reject(() => client.ReadAsync("synthetic-token", "owner", () => { }, default), "hangar.image_invalid_response");
        var calls = transport.Calls;
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await client.UploadAsync("synthetic-token", "owner", image, () => { }, cancelled.Token); throw new Exception("Cancellation expected"); }
        catch (OperationCanceledException) { }
        Check(calls == transport.Calls, "cancelled request never reaches transport");
        await Reject(() => client.UploadAsync("synthetic-token", "owner", image with { ClientRequestId = "invalid" }, () => { }, default), "hangar.invalid_request");
        Check(calls == transport.Calls, "invalid operation ID never reaches transport");
    }

    private static async Task Reject(Func<Task> action, string code)
    {
        try { await action(); }
        catch (AccountBridgeHostException error) { Check(error.Code == code, "typed error: " + code); return; }
        throw new Exception("Expected error: " + code);
    }
    private static void Check(bool valid, string message) { if (!valid) throw new Exception(message); }
    private sealed class Transport : HttpMessageHandler
    {
        internal int Calls;
        internal string Mode = "ok";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.Headers.Authorization?.Parameter == "synthetic-token", "Host bearer");
            Check(request.RequestUri!.Host == "media.example.invalid", "configured origin only");
            if (Mode == "offline") throw new HttpRequestException("synthetic outage");
            if (Mode == "forbidden") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
            if (Mode == "malformed") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{") });
            var row = new ShipMediaSummaryContract(new string('a', 32), Mode == "foreign-ship" ? "other" : "ship-one",
                "test-code", "Synthetic", Mode == "foreign-owner" ? "other" : "owner", "Synthetic", "image/png", 1, 1, 1, DateTimeOffset.UtcNow);
            object body = request.Method == HttpMethod.Get
                ? new ShipMediaCatalogContract([row], DateTimeOffset.UtcNow)
                : new ShipMediaUploadResponseContract(row, Mode == "wrong-status" ? "pending" : "uploaded");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }
    }
}
