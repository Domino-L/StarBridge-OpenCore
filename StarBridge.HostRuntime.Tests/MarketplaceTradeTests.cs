using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceTradeTests
{
    internal static async Task Run()
    {
        MarketplaceAvatarTests.Run();
        foreach (var creator in new[] {0,1})
        foreach (var role in new[] {"buyer","seller","stranger"})
        foreach (var state in Enumerable.Range(0,5))
        {
            var row=BridgePayload.From(new {actorRole=role,creatorType=creator,deliveryStatus=state,transactionStatus=state==3?2:state==4?3:1});
            var expected=role=="stranger"?null:state==0&&creator==0&&role=="buyer"?"approve":state==1&&role=="seller"?"ship":state==2&&role=="buyer"?"receive":state==3?"review":null;
            Check(MarketplaceTradePolicy.Action(row)==expected,"role/status action matrix");
            Check(MarketplaceTradePolicy.Allows(row,"cancel")== (role!="stranger" && state<2),"shipped cannot cancel");
        }
        var options=new ScmOAuthOptions("synthetic",new("https://web.invalid/"),new("https://auth.invalid/"),new("https://resource.invalid/"),"desktop","starbridge-api","openid profile.read","/callback");
        var session=new ScmOAuthSession("synthetic","owner","Fixture","synthetic-token",DateTimeOffset.UtcNow.AddHours(1),["profile.read","trade.write"]);
        var handler=new Handler();
        var client=new OAuthPkceClient(new ScmHttpClient(handler),new EmptyVault(),options);
        foreach (var code in new[] {401,403})
        {
            handler.BusinessCode=code;
            try { await client.MarketplaceTradeAsync(session,BridgePayload.From(new {operation="list"}),()=>true,default); throw new Exception("expected business auth rejection"); }
            catch (AccountBridgeHostException e) { Check(e.Code==(code==401?"marketplace.sign_in_required":"marketplace.forbidden"), "HTTP 200 business auth code preserved"); }
        }
        foreach (var (scm, stable) in new[] {
            (1004001009, "marketplace.account_unbound"), (1004001010, "marketplace.trade_time_required"),
            (1004001011, "marketplace.contact_required"), (1004001012, "marketplace.account_abnormal"),
            (1004015007, "marketplace.account_banned"), (1011010004, "marketplace.own_listing"), (1004001099, "marketplace.trade_rejected") })
        {
            handler.BusinessCode=scm;
            try { await client.MarketplaceTradeAsync(session,BridgePayload.From(new {operation="list"}),()=>true,default); throw new Exception("expected account precheck rejection"); }
            catch (AccountBridgeHostException e) { Check(e.Code==stable, $"SCM {scm} maps to {stable}, got {e.Code}"); }
        }
        Check(OAuthPkceClient.TradeRejection(BridgePayload.From(new {code="1004001010"}))=="marketplace.trade_rejected", "non-numeric code stays generic");
        handler.BusinessCode=0;
        var input=BridgePayload.From(new {operation="ship",transactionNumber="T1"});
        await client.MarketplaceTradeAsync(session,input,()=>true,default);
        Check(handler.Writes==1,"exactly one write after fresh detail");
        handler.Role="buyer";
        await Reject(()=>client.MarketplaceTradeAsync(session,input,()=>true,default));
        Check(handler.Writes==1,"buyer cannot ship");
        handler.Role="seller";handler.State=2;
        await Reject(()=>client.MarketplaceTradeAsync(session,BridgePayload.From(new {operation="cancel",transactionNumber="T1"}),()=>true,default));
        Check(handler.Writes==1,"shipped cancel rejected before PUT");
        handler.State=1;handler.FailWrite=true;
        try { await client.MarketplaceTradeAsync(session,input,()=>true,default);throw new Exception("expected failure"); }
        catch(HttpRequestException) {}
        Check(handler.Writes==2,"uncertain write never replayed");
        handler.FailWrite=false;
        await client.MarketplaceTradeAsync(session,BridgePayload.From(new { operation="block",transactionNumber="T1",blockedUserId=12345 }),()=>true,default);
        Check(handler.LastBody?.Contains("\"blockedUserId\":999")==true,"block resolves trusted SCM counterparty, ignores supplied identity");
        handler.Ongoing=true;
        var before=handler.Writes;
        await Reject(()=>client.MarketplaceTradeAsync(session,BridgePayload.From(new {operation="create",orderNumber="O1",number=1,locationId=1,deliveryMethod=0,shippingFee=0}),()=>true,default));
        Check(handler.Writes==before,"ongoing transaction rejects duplicate creation");
        await Reject(()=>client.MarketplaceTradeAsync(session,BridgePayload.From(new {operation="create",orderNumber="O1",number=1,locationId="wrong",deliveryMethod=0,shippingFee=0}),()=>true,default));
        await Reject(()=>client.MarketplaceTradeAsync(session,input,()=>false,default));
        var projected=BridgePayload.From(MarketplaceTradePolicy.Project(BridgePayload.From(new {actorRole="buyer",creatorType=1,deliveryStatus=2,transactionStatus=1,receiptDeadline="2026-10-18T10:00:00Z",orderOwnerMobile="private",tradingerId=999})));
        Check(!projected.TryGetProperty("orderOwnerMobile",out _)&&!projected.TryGetProperty("tradingerId",out _),"private contacts and identifiers excluded");
        Check(projected.GetProperty("receiptDeadline").GetString()=="2026-10-18T10:00:00Z"&&!projected.TryGetProperty("shipmentDeadline",out _),"deadline preserved without synthesis");
        var names = BridgePayload.From(MarketplaceTradePolicy.Project(BridgePayload.From(new { itemsName="科力晶（单个矿块）", itemsId="original-id" })));
        Check(names.GetProperty("itemsName").GetString()=="科力晶（单个矿块）", "SCM original name preserved");
        Check(names.GetProperty("itemsId").GetString()=="original-id", "SCM item identity preserved");
        if (OperatingSystem.IsWindows()) Check(names.GetProperty("itemsNameHant").GetString()=="科力晶（單個礦塊）", "trade names share catalog Traditional display conversion");
        var ownerViewing=BridgePayload.From(MarketplaceTradePolicy.Project(BridgePayload.From(new {actorRole="seller",creatorType=1,creatorStatus=1,orderOwnerAvatar="https://robertsspaceindustries.com/owner.png",tradingerAvatar="https://cdn.robertsspaceindustries.com/other.png"})));
        Check(ownerViewing.GetProperty("counterpartyStatus").ValueKind==JsonValueKind.Null,"owner status is not the applicant's status");
        Check(ownerViewing.GetProperty("counterpartyAvatar").GetString()=="https://cdn.robertsspaceindustries.com/other.png","counterparty avatar follows role ownership");
        Console.WriteLine("PASS marketplace trades: role/status matrix, fresh preflight, no replay, context guard, bounded projection");
    }
    private static void Check(bool value,string label){if(!value)throw new Exception(label);}
    private static async Task Reject(Func<Task> action){try{await action();}catch(AccountBridgeHostException){return;}throw new Exception("expected rejection");}
    private sealed class Handler:HttpMessageHandler
    {
        internal string Role="seller"; internal int State=1,Writes;internal bool FailWrite;
        internal bool Ongoing; internal string? LastBody;
        internal int BusinessCode;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter=="synthetic-token","Host-owned bearer");
            if(BusinessCode!=0) return new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("{\"code\":"+BusinessCode+",\"data\":null}")};
            if(request.Method!=HttpMethod.Get){Writes++;if(FailWrite)throw new HttpRequestException("uncertain"); LastBody=request.Content is null?null:await request.Content.ReadAsStringAsync(token);}
            var data=request.RequestUri!.AbsolutePath.EndsWith("check-ongoing")?JsonSerializer.Serialize(Ongoing):request.Method==HttpMethod.Get?JsonSerializer.Serialize(new {actorRole=Role,creatorType=1,deliveryStatus=State,transactionStatus=1,tradingerId=999,orderOwnerId=888}):"null";
            return new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("{\"code\":0,\"data\":"+data+"}")};
        }
    }
    private sealed class EmptyVault:ITokenVault
    {
        public string? LoadActiveAccountKey()=>null;
        public string? LoadRefreshToken(string key)=>null;
        public void SaveRefreshToken(string key,string token){}
        public void DeleteRefreshToken(string key){}
    }
}
