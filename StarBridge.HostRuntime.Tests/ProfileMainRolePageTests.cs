using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

/// <summary>HK page main role (user 11-05): only with the play style group, only one of the ticked roles.</summary>
internal static class ProfileMainRolePageTests
{
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    internal static Task Run()
    {
        var web = ProfileShowcaseTests.Web;
        var content = PersonalProfileContentContract.Empty with { SkilledRoles = ["pilot", "gunner"], MainRole = "gunner" };
        JsonObject Body(PersonalProfileContentContract value, params string[] groups)
        {
            var body = ProfileShowcaseTests.BridgeEdit(value);
            body["editedGroups"] = new JsonArray(groups.Select(g => (JsonNode)JsonValue.Create(g)!).ToArray());
            return body;
        }
        PersonalProfilePageEditContract Read(JsonObject body) => PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(body, web));
        void Rejected(JsonObject body, string why)
        {
            try { Read(body); throw new Exception("accepted: " + why); }
            catch (AccountBridgeHostException error) when (error.Code == "personalProfile.write_invalid") { }
        }

        var set = Read(Body(content, "playStyle"));
        var wire = JsonDocument.Parse(OAuthPkceClient.EncodePageEdit(set)).RootElement.GetProperty("page").GetProperty("content");
        Check(wire.GetProperty("mainRole").GetString() == "gunner", "main role sent with the play style group");
        var clear = Read(Body(content with { MainRole = "" }, "playStyle"));
        Check(clear.Content.MainRole == "", "\"\" clears");
        var omitted = Read(Body(content with { MainRole = null }, "playStyle"));
        Check(omitted.Content.MainRole is null &&
            !JsonDocument.Parse(OAuthPkceClient.EncodePageEdit(omitted)).RootElement.GetProperty("page").GetProperty("content")
                .TryGetProperty("mainRole", out _), "omitted is never synthesized (the server keeps the saved one)");
        Rejected(Body(content, "introduction"), "main role outside the play style group");
        Rejected(Body(content with { MainRole = "medic" }, "playStyle"), "a role that is not ticked");
        Rejected(Body(content with { MainRole = new string('x', 81) }, "playStyle"), "too long");

        // Readback: the server returns "" for none, the saved role otherwise.
        var saved = new PersonalProfileDocumentContract(3, "synthetic-public", false, 8, DateTimeOffset.UnixEpoch,
            new("Synthetic", ""), content, null);
        Check(ScmAccountBridgeHost.PageEditMatches(set, saved) &&
              !ScmAccountBridgeHost.PageEditMatches(set, saved with { Content = content with { MainRole = "" } }) &&
              ScmAccountBridgeHost.PageEditMatches(clear, saved with { Content = content with { MainRole = "" } }) &&
              ScmAccountBridgeHost.PageEditMatches(omitted, saved), "main role readback");

        // Core: a server value that is not a ticked role reads as none; an older server sends nothing.
        var normalized = PersonalProfileContractPolicy.Normalize(content with { MainRole = "medic" });
        Check(normalized.MainRole == "", "unknown main role normalizes to none");
        Check(PersonalProfileContractPolicy.Normalize(content with { MainRole = null }).MainRole is null,
            "an older server's page stays without the field");
        return Task.CompletedTask;
    }
}
