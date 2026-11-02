using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Achievements;

internal static class ScmAchievementRemoteTests
{
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a,string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential delete");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal string Body = "";
        internal int Triggers;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)
        {
            if (request.Method == HttpMethod.Get && request.RequestUri?.AbsolutePath == "/app-api/member/user/get")
            { Triggers++; return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":{}}", Encoding.UTF8, "application/json") }); }
            if (request.Method != HttpMethod.Get || request.RequestUri?.AbsolutePath != "/app-api/starbridge/v1/achievements/scm" ||
                request.Headers.Authorization?.Parameter != "synthetic-access") throw new Exception("SCM resource route/auth changed");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {Content=new StringContent(Body,Encoding.UTF8,"application/json")});
        }
    }
    internal static async Task Run()
    {
        using var handler=new Handler();
        var options=new ScmOAuthOptions("fixture-scm",new("http://127.0.0.1:3000/"),new("http://127.0.0.1:18080/"),new("http://127.0.0.1:18082/"),
            "starbridge-desktop","starbridge-api","profile.read","/oauth/callback");
        var session=new ScmOAuthSession("fixture-scm","synthetic-owner","Synthetic","synthetic-access",DateTimeOffset.UtcNow.AddHours(1),["profile.read"]);
        var client=new OAuthPkceClient(new ScmHttpClient(handler),new Vault(),options);
        var trigger = await client.TriggerScmAchievementsAsync(session, default);
        if (!trigger.Result || handler.Triggers != 1) throw new Exception("Daily trigger must use the existing member user/get route");
        var deniedClient = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options);
        try { await deniedClient.TriggerScmAchievementsAsync(session with { Capabilities = [] }, default); throw new Exception("Missing profile scope accepted"); }
        catch (StarBridge.HostRuntime.Account.AccountBridgeHostException) { }
        if (handler.Triggers != 1) throw new Exception("Missing profile scope must not send user/get");
        handler.Body=JsonSerializer.Serialize(new ScmAchievementCatalog(1,DateTimeOffset.UtcNow.AddMinutes(-1),[
            new("scm-1","SCM",null,null,"Official condition",null,"RARE","NORMAL",true,null,1.25m,2.5m,0)
        ]),new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var result=await client.ReadScmAchievementsAsync(session,default);
        if (result.Result.Items[0].CurrentValue!=1.25m || !result.Result.Items[0].Unlocked) throw new Exception("SCM facts changed during HTTP decoding");
        foreach (var malformed in new[]{handler.Body.Replace("\"unlocked\":true,",""),new string(' ',1500001)}) {
            handler.Body=malformed;
            try { await client.ReadScmAchievementsAsync(session,default); throw new Exception("Malformed/oversized SCM source accepted"); }
            catch (ScmApiProtocolException) { }
        }
        Console.WriteLine("PASS SCM authenticated read-only HTTP decoding and bounded source body");
    }
}
