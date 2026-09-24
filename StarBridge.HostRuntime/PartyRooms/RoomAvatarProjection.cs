namespace StarBridge.HostRuntime.PartyRooms;

using System.Buffers.Binary;
using System.Text.RegularExpressions;

// Optional display media, never a remote URL or a local file path. Invalid
// avatars fall back independently; they must not break the room directory.
internal static class RoomAvatarProjection
{
    internal static string? Normalize(string? value, int maximumBytes = 96 * 1024)
    {
        if (maximumBytes is < 24 or > 512 * 1024 || string.IsNullOrWhiteSpace(value) ||
            value.Length > ((maximumBytes + 2) / 3 * 4) + 24) return null;
        var raw = value.Trim();
        if (raw.StartsWith("data:image/png;base64,", StringComparison.Ordinal)) raw = raw[22..];
        else if (raw.StartsWith("data:image/jpeg;base64,", StringComparison.Ordinal)) raw = raw[23..];
        else if (raw.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) return null;
        byte[] bytes;
        try { bytes = Convert.FromBase64String(raw); } catch (FormatException) { return null; }
        if (bytes.Length < 24 || bytes.Length > maximumBytes) return null;
        var data = bytes.AsSpan();
        if (data[..8].SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }) &&
            data.Slice(12, 4).SequenceEqual("IHDR"u8) &&
            Bounded(BinaryPrimitives.ReadUInt32BigEndian(data.Slice(16, 4)), BinaryPrimitives.ReadUInt32BigEndian(data.Slice(20, 4))))
            return "data:image/png;base64," + Convert.ToBase64String(bytes);
        if (bytes[0] != 0xff || bytes[1] != 0xd8) return null;
        for (var offset = 2; offset + 4 <= bytes.Length;)
        {
            if (bytes[offset++] != 0xff) return null;
            while (offset < bytes.Length && bytes[offset] == 0xff) offset++;
            if (offset >= bytes.Length) return null;
            var marker = bytes[offset++];
            if (marker is 0xd9 or 0xda) return null;
            if (offset + 2 > bytes.Length) return null;
            var length = BinaryPrimitives.ReadUInt16BigEndian(data.Slice(offset, 2));
            if (length < 2 || offset + length > bytes.Length) return null;
            if (marker is 0xc0 or 0xc1 or 0xc2)
            {
                if (length < 8 || !Bounded(BinaryPrimitives.ReadUInt16BigEndian(data.Slice(offset + 5, 2)),
                        BinaryPrimitives.ReadUInt16BigEndian(data.Slice(offset + 3, 2)))) return null;
                return "data:image/jpeg;base64," + Convert.ToBase64String(bytes);
            }
            offset += length;
        }
        return null;
    }

    private static bool Bounded(uint width, uint height) => width is > 0 and <= 1024 && height is > 0 and <= 1024;

    internal static string PresenceKey(string? value)
    {
        var state = (value ?? "").Split('·', '•')[0].Trim().ToLowerInvariant();
        return state switch {
            "游戏中" or "遊戲中" or "ingame" or "in game" or "playing" => "presence.inGame",
            "应用在线" or "應用在線" or "在线" or "在線" or "online" or "app online" => "presence.online",
            "暂离" or "暫離" or "away" => "presence.away",
            "离线" or "離線" or "offline" => "presence.offline",
            _ => "presence.unknown"
        };
    }

    internal static string GameVersion(string? presence)
    {
        // A shard code or plain InGame does not prove the installed game channel.
        var match = Regex.Match(presence ?? "", @"^(?:游戏中|遊戲中|InGame|In game|Playing)\s*[·•]\s*([A-Za-z0-9][A-Za-z0-9._ -]{0,31})$", RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value.Trim() : "";
    }
}
