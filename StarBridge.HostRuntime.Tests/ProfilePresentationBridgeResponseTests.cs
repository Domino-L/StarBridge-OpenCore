using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static class ProfilePresentationBridgeResponseTests
{
    public static Task Verify()
    {
        var request = BridgeEnvelope.Request("personalProfile.getSelf", "profile-fixture", 1);
        var origins = new Dictionary<string, string>
        {
            ["introduction"] = "default", ["layout"] = "default", ["favorites"] = "default",
            ["schedule"] = "default", ["playStyle"] = "default", ["wishlist"] = "default",
            ["avatarStyle"] = "default", ["wallpaper"] = "default"
        };
        var profile = new PersonalProfileDocumentContract(1, "fixture", false, 0, DateTimeOffset.UnixEpoch,
            new("Fixture", "Fixture"), PersonalProfileContentContract.Empty, FleetAffiliation: null,
            Presentation: new(1, origins, SourceVersion: null));

        var versioned = AccountBridgeDispatcher.ToPersonalProfileResponse(request, profile)
            .Payload.GetProperty("profile").GetProperty("presentation");
        if (versioned.EnumerateObject().Count() != 3 ||
            versioned.GetProperty("schemaVersion").GetInt32() != 1 ||
            !versioned.GetProperty("origins").Deserialize<Dictionary<string, string>>()!
                .OrderBy(pair => pair.Key).SequenceEqual(origins.OrderBy(pair => pair.Key)) ||
            !versioned.TryGetProperty("sourceVersion", out var sourceVersion) ||
            sourceVersion.ValueKind != JsonValueKind.Null)
            throw new InvalidOperationException("Versioned profile must include schemaVersion, origins and a null sourceVersion.");

        var unversioned = AccountBridgeDispatcher.ToPersonalProfileResponse(request, profile with { Presentation = null })
            .Payload.GetProperty("profile");
        if (!unversioned.TryGetProperty("presentation", out var legacyValue) || legacyValue.ValueKind != JsonValueKind.Null)
            throw new InvalidOperationException("A legacy profile must retain its null presentation value.");
        return Task.CompletedTask;
    }
}
