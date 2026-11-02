using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // SCM's time-zone directory changes rarely; one read per hour is plenty for a visitor header.
    private (DateTimeOffset At, IReadOnlyList<ScmTimeZoneDirectoryEntry> Entries)? _publicHeaderZones;

    /// <summary>Adds the owner's current UTC offset to a public header's trade window and facts. A missing
    /// directory or unknown zone leaves it null: the client then shows the owner's own setting.</summary>
    private async Task<PersonalProfilePublicHeader> WithOwnerOffsetAsync(PersonalProfilePublicHeader header, CancellationToken token)
    {
        if (header.TradeWindow is null && header.Facts?.TimezoneId is null) return header;
        IReadOnlyList<ScmTimeZoneDirectoryEntry> zones;
        try
        {
            if (_publicHeaderZones is { } cached && DateTimeOffset.UtcNow - cached.At < TimeSpan.FromHours(1))
                zones = cached.Entries;
            else
            {
                zones = await _oauth.LoadTimeZoneDirectoryAsync(token);
                _publicHeaderZones = (DateTimeOffset.UtcNow, zones);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception) { return header; }
        int? Offset(long id)
        {
            var zone = zones.FirstOrDefault(z => z.Id == id);
            if (zone is null) return null;
            int? offset = zone.OffsetMinutes is >= -14 * 60 and <= 14 * 60 ? zone.OffsetMinutes : null;
            if (TimeZoneInfo.TryFindSystemTimeZoneById(zone.Value, out var info))
                offset = (int)info.GetUtcOffset(DateTimeOffset.UtcNow).TotalMinutes;
            return offset;
        }
        return header with
        {
            TradeWindow = header.TradeWindow is { } window ? window with { OwnerOffsetMinutes = Offset(window.TimezoneId) } : null,
            Facts = header.Facts is { TimezoneId: { } id } facts ? facts with { UtcOffsetMinutes = Offset(id) } : header.Facts
        };
    }
}
