using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceAvatarTests
{
    internal static void Run()
    {
        const string root = "https://robertsspaceindustries.com/avatar.png";
        const string subdomain = "https://cdn.robertsspaceindustries.com/avatar.png";
        var cases = new (string Label, object? Input, string? Expected)[]
        {
            ("mixed case", "HTTPS://RobertsSpaceIndustries.COM/media/x.png",
                "https://robertsspaceindustries.com/media/x.png"),
            ("evil suffix", "https://robertsspaceindustries.com.evil.test/x", null),
            ("evil prefix", "https://evilrobertsspaceindustries.com/x", null),
            ("RSI as userinfo", "https://robertsspaceindustries.com" + "@evil.test/x", null),
            ("RSI in path", "https://evil.test/robertsspaceindustries.com/x", null),
            // .NET 8 rejects these malformed authorities rather than accepting an RSI host.
            ("backslash authority", @"https://evil.test\@robertsspaceindustries.com/x", null),
            ("backslash scheme", @"https:\robertsspaceindustries.com\x", null),
            ("encoded host dot", "https://robertsspaceindustries%2Ecom/x", null),
            ("encoded slash userinfo", "https://robertsspaceindustries.com%2F" + "@evil.test/x", null),
            ("IDN dotless i", "https://robertsspace\u0131ndustries.com/x", null),
            ("IDN punycode", "https://xn--robertsspacendustries-vgd.com/x", null),
            ("surrounding whitespace", " \t\r\nHTTPS://RobertsSpaceIndustries.COM:443/media/x.png \r\n\t",
                "https://robertsspaceindustries.com/media/x.png"),
            ("RSI root", root, root),
            ("RSI subdomain", subdomain, subdomain),
            // The shared validator accepts an explicit default HTTPS port and canonicalizes it.
            ("default port", "https://robertsspaceindustries.com:443/avatar.png", root),
            ("foreign host", "https://uploads.example.invalid/avatar.png", null),
            ("host suffix spoof", "https://robertsspaceindustries.com.example.invalid/avatar.png", null),
            ("host prefix spoof", "https://notrobertsspaceindustries.com/avatar.png", null),
            ("http", "http://robertsspaceindustries.com/avatar.png", null),
            ("nondefault port", "https://robertsspaceindustries.com:8443/avatar.png", null),
            ("userinfo", "https://fixture" + "@robertsspaceindustries.com/avatar.png", null),
            ("IP", "https://127.0.0.1/avatar.png", null),
            ("oversized", root + new string('a', 2049), null),
            ("empty", "", null),
            ("whitespace", "   ", null),
            ("null", null, null),
            ("number", 123, null),
            ("boolean", true, null),
            ("array", new[] { root }, null),
            ("object", new { url = root }, null),
        };
        var quote = typeof(ScmMarketplaceReader).GetMethod("Quote", BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new Exception("Quote projection missing");
        var checks = 0;
        foreach (var (label, input, expected) in cases)
        {
            Verify(BridgePayload.From(quote.Invoke(null, new object?[] { BridgePayload.From(new { avatar = input }), null })!),
                "avatar", expected, "quote " + label);
            checks++;
            foreach (var role in new[] { "buyer", "seller" })
            foreach (var creatorType in new[] { 0, 1 })
            {
                var ownsOrder = (role == "buyer") == (creatorType == 0);
                // Keep the unselected avatar valid and different to catch wrong-side selection or fallback.
                var row = BridgePayload.From(new
                {
                    actorRole = role, creatorType,
                    tradingerAvatar = ownsOrder ? input : subdomain,
                    orderOwnerAvatar = ownsOrder ? subdomain : input,
                });
                Verify(BridgePayload.From(MarketplaceTradePolicy.Project(row)), "counterpartyAvatar", expected,
                    "trade " + label + " " + role + " " + creatorType);
                checks++;
            }
        }
        foreach (var (label, input, expected) in cases)
        {
            Uri? parsed = null;
            if (input is string value) Uri.TryCreate(value.Trim(), UriKind.Absolute, out parsed);
            Console.WriteLine("AVATAR_CASE " + JsonSerializer.Serialize(new
            {
                label, input, output = expected,
                parsedHost = parsed?.Host, parsedIdnHost = parsed?.IdnHost,
            }));
        }
        Verify(BridgePayload.From(quote.Invoke(null, new object?[] { BridgePayload.From(new { }), null })!),
            "avatar", null, "quote missing");
        Verify(BridgePayload.From(MarketplaceTradePolicy.Project(BridgePayload.From(new { actorRole = "buyer", creatorType = 1 }))),
            "counterpartyAvatar", null, "trade missing");
        Console.WriteLine($"PASS marketplace avatars: {checks + 2} projection checks; no image transport");
    }

    private static void Verify(JsonElement row, string key, string? expected, string label)
    {
        if (!row.TryGetProperty(key, out var actual) ||
            (expected is null ? actual.ValueKind != JsonValueKind.Null :
                actual.ValueKind != JsonValueKind.String || actual.GetString() != expected))
            throw new Exception("Avatar projection mismatch: " + label);
    }
}
