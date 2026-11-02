using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;

internal static class AchievementIdeaContentionTests
{
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential delete");
    }

    private sealed class ReadHandler : HttpMessageHandler
    {
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Entered.TrySetResult();
            await Release.Task.WaitAsync(token);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, earnedAt = new Dictionary<string, string>() }) };
        }
    }

    private sealed class MailHandler : HttpMessageHandler
    {
        internal int Sends;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Headers.Authorization?.Parameter != "synthetic-access") throw new Exception("Wrong synthetic owner");
            Sends++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, sent = true }) });
        }
    }

    internal static async Task Run()
    {
        await Check("wait");
        await Check("cancel");
        await Check("wrong-owner");
        await Check("timeout");
    }

    private static async Task Check(string scenario)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        using var read = new ReadHandler();
        using var mail = new MailHandler();
        using var client = new AchievementIdeaClient(new("https://relay.invalid"), mail);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "profile.read presence.write game_identity.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "synthetic-owner", "Synthetic", "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write", "game_identity.read"]);
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(read), new Vault(), options), new ScmProfileCacheStore(Path.GetTempPath()), "fixture", () => null, initialSession: session, initialGeneration: 1, achievementIdeas: client);
        var owner = host.CurrentContext!;
        var reading = ((IAchievementRemote)host).ReadAchievementsAsync(owner, 1, deadline.Token);
        await read.Entered.Task.WaitAsync(deadline.Token);
        var payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, submissionId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name = "Synthetic", condition = "Synthetic condition", imageData = (string?)null });
        try
        {
            using var requestCancellation = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token);
            var submitting = host.SubmitAchievementIdeaAsync(scenario == "wrong-owner" ? owner with { Subject = "other" } : owner, payload, requestCancellation.Token);
            if (submitting.IsCompleted) await submitting; // Exposes the exact pre-HTTP ideas.busy failure.
            if (mail.Sends != 0) throw new Exception("Submission bypassed account serialization");
            if (scenario == "cancel")
            {
                requestCancellation.Cancel();
                try { await submitting; throw new Exception("Canceled submission was admitted"); }
                catch (OperationCanceledException) { }
                if (mail.Sends != 0) throw new Exception("Canceled wait sent mail");
                return;
            }
            if (scenario == "timeout")
            {
                try { await submitting; throw new Exception("Busy timeout was admitted"); }
                catch (AccountBridgeHostException error) when (error.Message == "ideas.busy") { }
                if (mail.Sends != 0) throw new Exception("Busy wait sent mail");
                return;
            }
            read.Release.TrySetResult();
            await reading;
            if (scenario == "wrong-owner")
            {
                try { await submitting; throw new Exception("Wrong owner was admitted"); }
                catch (AccountBridgeHostException) { }
                if (mail.Sends != 0) throw new Exception("Wrong owner sent mail");
                return;
            }
            await submitting;
            if (mail.Sends != 1) throw new Exception("A first submission must send exactly once after the account read finishes");
        }
        finally
        {
            read.Release.TrySetResult();
            await reading;
        }
    }
}
