using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using StarBridge.Core.Hangar;

namespace StarBridge.HostRuntime.Hangar;

internal sealed record LegacyHangarRow(int Line, string Raw, MigrationShip? Ship, string? Issue);
internal sealed record LegacyHangarRead(string Sha256, MigrationHangarSource Source,
    IReadOnlyList<LegacyHangarRow> Rows);

// Caller must explicitly select and authorize the source and owner. No file discovery,
// owner inference, legacy promotion, write, or network operation belongs here.
internal static class LegacyHangarMigrationReader
{
    internal static LegacyHangarRead Read(ReadOnlySpan<byte> input, MigrationOwner owner)
    {
        ArgumentNullException.ThrowIfNull(owner);
        if (new[] { owner.Environment, owner.Authority, owner.Subject }.Any(string.IsNullOrWhiteSpace))
            throw new ArgumentException("Owner is required.");
        if (input.Length > 4 * 1024 * 1024) throw new InvalidDataException("Source is too large.");
        var hash = Convert.ToHexString(SHA256.HashData(input));
        if (input.StartsWith(new byte[] { 0xef, 0xbb, 0xbf })) input = input[3..];
        // Invalid encoding fails the source, never becomes an empty complete hangar.
        var text = new UTF8Encoding(false, true).GetString(input);
        using var reader = new StringReader(text);
        var rows = new List<LegacyHangarRow>();
        string? line;
        while ((line = reader.ReadLine()) is not null)
        {
            if (rows.Count >= 10000) throw new InvalidDataException("Too many source rows.");
            rows.Add(Parse(rows.Count + 1, line));
        }
        var source = new MigrationHangarSource(owner, "legacy-instance-v1",
            rows.Any(r => r.Issue is not null) ? MigrationSourceState.Partial : MigrationSourceState.Complete,
            rows.Where(r => r.Ship is not null).Select(r => r.Ship!).ToArray());
        return new(hash, source, rows);
    }

    private static LegacyHangarRow Parse(int number, string raw)
    {
        var p = raw.Split('\t');
        // Current WPF writer emits 11 columns. Older/future layouts are retained
        // for review instead of supplying guessed dates, IDs or crop defaults.
        if (p.Length != 11) return new(number, raw, null, "unsupported-layout");
        if (string.IsNullOrWhiteSpace(p[0]) || string.IsNullOrWhiteSpace(p[1]) ||
            !Date(p[3], out var imported) || !Date(p[4], out var added))
            return new(number, raw, null, "invalid-fields");
        DateTimeOffset synced = default;
        if (p[5].Length != 0 && !Date(p[5], out synced))
            return new(number, raw, null, "invalid-date");
        if (!Number(p[8], out var x) || !Number(p[9], out var y) || !Number(p[10], out var zoom) ||
            x < 0 || x > 1 || y < 0 || y > 1 || zoom < 1 || zoom > 3)
            return new(number, raw, null, "invalid-crop");
        var ship = new MigrationShip(string.IsNullOrWhiteSpace(p[6]) ? null : p[6],
            new(p[0], p[1], p[2], imported, synced, p[7].Length == 0 ? null : p[7], x, y, zoom), added);
        return new(number, raw, ship, null);
    }

    private static bool Date(string value, out DateTimeOffset result) =>
        DateTimeOffset.TryParseExact(value, "O", CultureInfo.InvariantCulture, DateTimeStyles.None, out result);
    private static bool Number(string value, out double result) =>
        double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out result) && double.IsFinite(result);
}
