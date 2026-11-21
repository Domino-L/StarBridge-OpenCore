using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class LeaderboardTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "scm", "synthetic-pilot");
    private static readonly DateTimeOffset At = DateTimeOffset.Parse("2026-11-03T12:00:00Z");
    private static TsgSwiftLeaderboard Board => new(1, At, [new(1, "Verified-Pilot", 500000, DateOnly.FromDateTime(At.UtcDateTime))], new(1, 500000, true));
    private static LeaderboardConsent Consent(bool value) => new(1, value ? "opted-in" : "withdrawn", value, At);
    private static void Check(bool ok, string why) { if (!ok) throw new Exception(why); }
    private static void Invalid(Action run) { try { run(); } catch (InvalidDataException) { return; } throw new Exception("Invalid data accepted"); }
    internal static async Task Run()
    {
        var tests = new (string, Func<Task>)[] {
            ("three authenticated operations", Wire),
            ("404, 429, malformed and timeout", Failures),
            ("shared fixture and validation", () => { Validate(); return Task.CompletedTask; }),
            ("cache, withdrawal and old backend", Runtime),
            ("late owner and malformed bridge request", Ownership),
        };
        int failed = 0, skipped = 0;
        foreach (var (name, test) in tests) {
            try { await test(); Console.WriteLine("PASS LEADERBOARD " + name); }
            catch (RestrictedSampleAbsentException e) { skipped++; e.Report(name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL LEADERBOARD " + name + ": " + e); }
        }
        Console.WriteLine($"SUMMARY LEADERBOARD passed={tests.Length - failed - skipped} failed={failed} skipped={skipped}");
        Check(failed == 0, "leaderboard regressions");
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("No vault writes");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("No vault deletes");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal bool Malformed, Held;
        internal int Calls;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.Headers.Authorization?.Parameter == "synthetic-access", "bearer authentication");
            var path = request.RequestUri!.AbsolutePath;
            Check(path.StartsWith("/app-api/starbridge/v1/achievements/leaderboards/tsg-swift"), "exact endpoint");
            if (Held) await Task.Delay(Timeout.Infinite, token);
            object value = Board;
            if (path.EndsWith("/consent")) {
                value = new LeaderboardConsent(1, "undecided", false, null);
                if (request.Method == HttpMethod.Put) {
                    using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                    Check(json.RootElement.EnumerateObject().Count() == 1, "only optIn written");
                    value = Consent(json.RootElement.GetProperty("optIn").GetBoolean());
                }
            } else Check(request.Method == HttpMethod.Get, "board GET");
            var response = new HttpResponseMessage(Status) { Content = Malformed ? new StringContent("{\"schemaVersion\":2}") : JsonContent.Create(value) };
            if (Status == HttpStatusCode.TooManyRequests) response.Headers.RetryAfter = new(TimeSpan.FromSeconds(60));
            return response;
        }
    }
    private static (OAuthPkceClient Client, ScmOAuthSession Session) Client(Handler handler, bool write = true)
    {
        var options = new ScmOAuthOptions("fixture", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "profile.read", "/oauth/callback");
        return (new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options), new ScmOAuthSession("fixture", "synthetic-pilot", "Synthetic",
            "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), write ? ["profile.read", "profile.write"] : ["profile.read"]));
    }
    private static async Task Wire()
    {
        using var handler = new Handler(); var (client, session) = Client(handler);
        Check((await client.ReadLeaderboardAsync(session, default)).Result.Entries.Length == 1, "board");
        Check((await client.ReadLeaderboardConsentAsync(session, default)).Result.State == "undecided", "undecided");
        Check((await client.WriteLeaderboardConsentAsync(session, true, default)).Result.OptedIn, "join");
        Check(!(await client.WriteLeaderboardConsentAsync(session, false, default)).Result.OptedIn, "withdraw");
        using var noWriteHandler = new Handler(); var noWrite = Client(noWriteHandler, false);
        try { await noWrite.Client.WriteLeaderboardConsentAsync(noWrite.Session, true, default); throw new Exception("scope accepted"); }
        catch (ScmApiForbiddenException) { Check(noWriteHandler.Calls == 0, "no unauthorized write"); }
    }
    private static async Task Failures()
    {
        using var handler = new Handler(); var (client, session) = Client(handler);
        var calls = new Func<CancellationToken, Task>[] {
            async t => { await client.ReadLeaderboardAsync(session, t); },
            async t => { await client.ReadLeaderboardConsentAsync(session, t); },
            async t => { await client.WriteLeaderboardConsentAsync(session, true, t); },
        };
        foreach (var call in calls) {
            handler.Status = HttpStatusCode.NotFound;
            try { await call(default); throw new Exception("404 accepted"); }
            catch (HttpRequestException e) when (e.StatusCode == HttpStatusCode.NotFound) { }
            handler.Status = HttpStatusCode.TooManyRequests;
            try { await call(default); throw new Exception("429 accepted"); }
            catch (ScmApiRateLimitException e) { Check(e.RetryAfter == TimeSpan.FromSeconds(60), "Retry-After retained"); }
            handler.Status = HttpStatusCode.OK; handler.Malformed = true;
            try { await call(default); throw new Exception("invalid accepted"); }
            catch (Exception e) when (e is InvalidDataException or ScmApiProtocolException) { }
            handler.Malformed = false; handler.Held = true;
            using var timeout = new CancellationTokenSource(30);
            try { await call(timeout.Token); throw new Exception("timeout accepted"); }
            catch (OperationCanceledException) { }
            handler.Held = false;
        }
    }
    private static void Validate()
    {
        Board.Validate(); Consent(true).Validate(); new LeaderboardConsent(1,"undecided",false,null).Validate();
        foreach (var board in new[] { Board with { SchemaVersion = 2 }, Board with { Entries = [new(2,"Pilot",500000,DateOnly.FromDateTime(At.UtcDateTime))] },
            Board with { Entries = [new(1,"SCM nickname!",500000,DateOnly.FromDateTime(At.UtcDateTime))] }, Board with { Me = new(1,500000,false) },
            Board with { Entries = [new(1,"Pilot",299999,DateOnly.FromDateTime(At.UtcDateTime))] }, Board with { Entries = [new(1,"Pilot",5400001,DateOnly.FromDateTime(At.UtcDateTime))] },
            Board with { Entries = Enumerable.Range(1,101).Select(i => new LeaderboardEntry(i,"P"+i,500000,DateOnly.FromDateTime(At.UtcDateTime))).ToArray() } }) Invalid(board.Validate);
        Invalid(() => new LeaderboardConsent(1,"withdrawn",true,At).Validate());
        Invalid(() => new LeaderboardConsent(1,"undecided",false,At).Validate());
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var entry = JsonSerializer.Serialize(Board.Entries[0], options);
        Check(entry.Contains("\"achievedOn\":\"2026-11-03\"") && !entry.Contains("achievedAt") && !entry.Contains("T12:"), "only UTC day serialized");
        foreach (var raw in new[] {
            entry.Replace("2026-11-03", "2026-11-03T12:00:00Z"),
            entry.Replace("2026-11-03", "2026-02-30"),
            entry.Replace("achievedOn", "achievedAt"),
            entry.Replace("}", ",\"achievedAt\":\"2026-11-03T12:00:00Z\"}") }) {
            try { JsonSerializer.Deserialize<LeaderboardEntry>(raw, options); throw new Exception("full timestamp accepted"); }
            catch (JsonException) { }
        }
        foreach(var file in new[]{"leaderboard-response.json","leaderboard-consent.json"}) {
            using var json=JsonDocument.Parse(RestrictedSamples.Read(file));
            foreach(var sample in json.RootElement.EnumerateObject()) {
                if(file.Contains("response")) JsonSerializer.Deserialize<TsgSwiftLeaderboard>(sample.Value,options)!.Validate();
                else JsonSerializer.Deserialize<LeaderboardConsent>(sample.Value,options)!.Validate();
            }
        }
    }
    private sealed class Remote : IAchievementRemote
    {
        internal int Reads, ConsentReads;
        internal TsgSwiftLeaderboard Value = Board;
        internal LeaderboardConsent Choice = Consent(true);
        internal Exception? Error;
        internal TaskCompletionSource<TsgSwiftLeaderboard>? Held;
        public async Task<TsgSwiftLeaderboard> ReadLeaderboardAsync(BridgeAccountContext o,long g,CancellationToken t)
        { Reads++; if(Error is not null)throw Error; return Held is null ? Value : await Held.Task.WaitAsync(t); }
        public Task<LeaderboardConsent> ReadLeaderboardConsentAsync(BridgeAccountContext o,long g,CancellationToken t)
        { ConsentReads++; if(Error is not null)throw Error; return Task.FromResult(Choice); }
        public Task<LeaderboardConsent> WriteLeaderboardConsentAsync(BridgeAccountContext o,long g,bool opt,CancellationToken t)
        { Choice=Consent(opt); return Task.FromResult(Choice); }
        public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext o,long g,CancellationToken t) => Task.FromResult(new AchievementSnapshot(1,[]));
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext o,long g,FirstEntryObservation v,CancellationToken t) => throw new NotSupportedException();
    }
    private static BridgeEnvelope Request(string action, long generation=1, BridgeAccountContext? owner=null, bool? opt=null) =>
        BridgeEnvelope.Request("achievements.leaderboard."+action,Guid.NewGuid().ToString("N"),generation,
            opt is null ? (object)new {schemaVersion=1} : new {schemaVersion=1,optIn=opt.Value},owner??Owner);
    private static AchievementRuntime Runtime(Remote remote,Func<(BridgeAccountContext?,long)> owner) =>
        new(new(Path.Combine(Path.GetTempPath(),"leaderboard-"+Guid.NewGuid().ToString("N"))),remote,owner,()=>null,_=>{},startTimer:false);
    private static async Task Runtime()
    {
        var remote=new Remote(); using var runtime=Runtime(remote,()=> (Owner,1));
        var request=Request("read");
        Check((await runtime.DispatchAsync(request,default)).Response.Payload.GetProperty("supported").GetBoolean(),"supported");
        remote.Value = Board with { Entries = [] };
        var withdrawn = await runtime.DispatchAsync(Request("read"),default);
        Check(remote.Reads==2,"every read revalidates public eligibility");
        Check(withdrawn.Response.Payload.GetProperty("board").GetProperty("entries").GetArrayLength()==0,
            "another player withdrawal or hidden eligibility removes the row on the next read");
        await runtime.DispatchAsync(Request("consent.read"),default);
        await runtime.DispatchAsync(Request("consent.write",opt:false),default);
        var read=await runtime.DispatchAsync(Request("consent.read"),default);
        Check(!read.Response.Payload.GetProperty("consent").GetProperty("optedIn").GetBoolean(),"withdrawal shared immediately");
        Check(remote.ConsentReads==1,"consent budget");
        await runtime.DispatchAsync(Request("read"),default); Check(remote.Reads==3,"withdrawal revalidates board");
        remote=new Remote {Error=new HttpRequestException("old backend",null,HttpStatusCode.NotFound)};
        using var old=Runtime(remote,()=> (Owner,1));
        Check(!(await old.DispatchAsync(Request("read"),default)).Response.Payload.GetProperty("supported").GetBoolean(),"404 hides entry");
        await old.DispatchAsync(Request("read"),default); Check(remote.Reads==1,"404 low frequency");
        remote=new Remote {Error=new ScmApiRateLimitException("rate",TimeSpan.FromSeconds(60))};
        using var limited=Runtime(remote,()=> (Owner,1));
        Check((await limited.DispatchAsync(Request("read"),default)).Response.Status==BridgeResponseStatuses.Error,"429 reported");
        await limited.DispatchAsync(Request("read"),default); Check(remote.Reads==1,"429 cooldown");
        Check((await limited.DispatchAsync(Request("consent.write",opt:false),default)).Response.Status==BridgeResponseStatuses.Ok,"withdraw bypasses read cooldown");
    }
    private static async Task Ownership()
    {
        (BridgeAccountContext?,long) current=(Owner,1);
        var remote=new Remote { Held=new() }; using var runtime=Runtime(remote,()=>current);
        var pending=runtime.DispatchAsync(Request("read"),default);
        current=(Owner with {Subject="other-synthetic"},2); runtime.Invalidate(2); remote.Held.SetResult(Board);
        Check((await pending).Response.Status==BridgeResponseStatuses.Error,"late old response rejected");
        Check((await runtime.DispatchAsync(Request("read"),default)).Response.Status==BridgeResponseStatuses.Error,"old owner rejected");
        var invalid=BridgeEnvelope.Request("achievements.leaderboard.consent.write","invalid",2,new{schemaVersion=1,optIn=true,extra=true},current.Item1);
        Check((await runtime.DispatchAsync(invalid,default)).Response.Status==BridgeResponseStatuses.Error,"extra fields rejected");
    }
}
