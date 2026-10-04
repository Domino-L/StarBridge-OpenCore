using System.Security.Cryptography;
using System.Text;
namespace StarBridge.HostRuntime.Overlay;

/// <summary>Local stable display key. Never derives identity from a callsign or game handle.</summary>
public static class OverlayMemberIdentity
{
    public static string? FromAccountId(string? accountId)
    {
        if (string.IsNullOrWhiteSpace(accountId)) return null;
        var id = accountId.Trim();
        if (id.StartsWith("account:", StringComparison.OrdinalIgnoreCase)) id = id[8..];
        return "member:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(id.ToUpperInvariant())));
    }
}
