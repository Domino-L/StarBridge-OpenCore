using System.Text.Json;
using StarBridge.HostRuntime.Account;

internal static class PublicOrganizationLogoTests
{
    internal static async Task Run()
    {
        var passed = 0;
        void Check(bool condition, string name)
        {
            if (!condition) throw new Exception(name);
            passed++;
            Console.WriteLine("PASS " + name);
        }
        static JsonDocument Body(string sid, string image = "https://example.invalid/logo.png") =>
            JsonDocument.Parse(JsonSerializer.Serialize(new { id = "17", sid, image }));
        var now = DateTimeOffset.UtcNow;
        var calls = 0;
        var reader = new PublicOrganizationLogoReader((sid, _) => {
            calls++; return Task.FromResult(Body(sid));
        }, () => now);
        var logo = await reader.ReadAsync("FIXTURE");
        Check(logo is { Id: 17, Sid: "FIXTURE", Image: "https://example.invalid/logo.png" }, "public metadata projection");
        now += TimeSpan.FromHours(23);
        await reader.ReadAsync("FIXTURE");
        Check(calls == 1, "successful cache lasts 24 hours");
        now += TimeSpan.FromHours(1);
        await reader.ReadAsync("FIXTURE");
        Check(calls == 2, "successful cache expires");
        calls = 0;
        reader = new PublicOrganizationLogoReader((sid, _) => {
            calls++; return Task.FromResult(Body("OTHER"));
        }, () => now);
        Check(await reader.ReadAsync("FIXTURE") is null, "SID mismatch discarded");
        now += TimeSpan.FromMinutes(4);
        await reader.ReadAsync("FIXTURE");
        Check(calls == 1, "failure cached for 5 minutes");
        now += TimeSpan.FromMinutes(1);
        await reader.ReadAsync("FIXTURE");
        Check(calls == 2, "failure cache expires");
        calls = 0;
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        reader = new PublicOrganizationLogoReader(async (sid, token) => {
            Interlocked.Increment(ref calls);
            await release.Task.WaitAsync(token);
            return Body(sid);
        });
        var pending = Enumerable.Range(0, 20).Select(_ => reader.ReadAsync("FIXTURE")).ToArray();
        Check(calls == 1, "same SID concurrent requests coalesce");
        release.SetResult();
        await Task.WhenAll(pending);
        Check(pending.All(task => task.Result?.Id == 17), "all waiters receive metadata");
        release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var active = 0; var maximum = 0; calls = 0;
        async Task<JsonDocument> Read(string sid, CancellationToken token)
        {
            var count = Interlocked.Increment(ref active);
            Interlocked.Increment(ref calls);
            maximum = Math.Max(maximum, count);
            if (count == 2) entered.TrySetResult();
            try { await release.Task.WaitAsync(token); return Body(sid); }
            finally { Interlocked.Decrement(ref active); }
        }
        var first = new PublicOrganizationLogoReader(Read);
        var second = new PublicOrganizationLogoReader(Read);
        pending = [first.ReadAsync("A"), second.ReadAsync("B"), first.ReadAsync("C"), second.ReadAsync("D")];
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(calls == 2, "global limit applies across reader instances");
        release.SetResult();
        await Task.WhenAll(pending);
        Check(maximum == 2 && calls == 4, "queued requests complete within limit");
        reader = new PublicOrganizationLogoReader((sid, _) => Task.FromResult(Body(sid, "http://example.invalid/logo.png")));
        Check(await reader.ReadAsync("FIXTURE") is null, "unsafe image URL discarded");
        reader = new PublicOrganizationLogoReader((_, _) => throw new HttpRequestException());
        Check(await reader.ReadAsync("FIXTURE") is null, "transport failure is optional decoration failure");
        // Bounded queue: beyond the pending limit distinct SIDs get no logo and no read.
        var hold = new TaskCompletionSource<JsonDocument>(TaskCreationOptions.RunContinuationsAsynchronously);
        calls = 0;
        reader = new PublicOrganizationLogoReader((sid, token) => { Interlocked.Increment(ref calls); return hold.Task.WaitAsync(token); });
        var queued = Enumerable.Range(0, PublicOrganizationLogoReader.MaxPendingReads + 4)
            .Select(index => reader.ReadAsync("SID" + index)).ToArray();
        var refused = queued.Skip(PublicOrganizationLogoReader.MaxPendingReads).ToArray();
        Check(refused.All(task => task.IsCompletedSuccessfully && task.Result is null),
            "reads beyond the pending limit are left out at once");
        hold.SetResult(Body("SID0"));
        await Task.WhenAll(queued);
        Check(calls <= PublicOrganizationLogoReader.MaxPendingReads, "refused reads never reach the source");
        calls = 0;
        reader = new PublicOrganizationLogoReader((sid, _) => {
            calls++; return Task.FromResult(Body(sid));
        }, () => now);
        var filled = new List<PublicOrganizationLogoReader.Logo?>();
        for (var index = 0; index < 256; index++) filled.Add(await reader.ReadAsync("CACHE" + index));
        Check(filled.All(value => value is not null) && calls == 256, "all 256 cache entries admitted");
        Check(await reader.ReadAsync("CACHE256") is null && calls == 256,
            "257th distinct SID returns null without a source read");
        Check(await reader.ReadAsync("CACHE0") is not null && calls == 256,
            "full cache still serves an existing SID");

        foreach (var fail in new[] { false, true })
        {
            var unblock = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var readSids = new System.Collections.Concurrent.ConcurrentBag<string>();
            reader = new PublicOrganizationLogoReader(async (sid, token) => {
                readSids.Add(sid);
                await unblock.Task.WaitAsync(token);
                if (fail && sid.StartsWith("PENDING", StringComparison.Ordinal)) throw new HttpRequestException();
                return Body(sid);
            });
            var full = Enumerable.Range(0, PublicOrganizationLogoReader.MaxPendingReads)
                .Select(index => reader.ReadAsync("PENDING" + index)).ToArray();
            Check(await reader.ReadAsync("AFTER") is null && !readSids.Contains("AFTER"),
                "full pending queue refuses new SID before " + (fail ? "exception" : "completion"));
            unblock.SetResult();
            var completed = await Task.WhenAll(full);
            Check(completed.All(value => (value is null) == fail), "pending reads settle after " + (fail ? "exception" : "completion"));
            Check(await reader.ReadAsync("AFTER") is not null && readSids.Count == full.Length + 1,
                "pending capacity recovers after " + (fail ? "exception" : "completion"));
        }
        Console.WriteLine($"Public organization logo: {passed} passed, 0 failed");
    }
}
