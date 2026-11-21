using System.Text.Json;

namespace StarBridge.HostRuntime.Ships;

internal static class ScmShipThumbnail
{
    // Only public catalogue artwork on the existing SCM media hosts. Never an
    // owner-supplied image or a URL inferred from a name/base model.
    internal static string? From(JsonElement item) =>
        Read(item, "thumbnailUrlHd") ?? Read(item, "thumbnailUrl");

    private static string? Read(JsonElement item, string field)
    {
        var value = ShipSpecificationProjection.At(item, field);
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { Length: > 0 and <= 2048 } text ||
            text.Any(char.IsControl) || !Uri.TryCreate(text, UriKind.Absolute, out var uri) ||
            uri.Scheme != "https" || uri.Port != 443 || uri.UserInfo.Length != 0 || uri.Fragment.Length != 0 ||
            !AllowedHost(uri.Host)) return null;
        return uri.AbsoluteUri;
    }

    private static bool AllowedHost(string host) =>
        new[] { "flowcld.com", "flowcld.xyz", "flowcld.top" }.Any(domain =>
            host.Equals(domain, StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase));
}
