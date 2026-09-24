namespace StarBridge.Core.Hangar;

// Input is supplied by an explicitly authorized, read-only adapter. This module
// neither discovers accounts nor reads files, fetches data, merges, or publishes.
public enum MigrationSourceState { Complete, Unavailable, Partial }
public sealed record MigrationOwner(string Environment, string Authority, string Subject);
public sealed record MigrationShipFields(string Code, string DisplayName, string Source,
    DateTimeOffset ImportedAt, DateTimeOffset SyncedAt, string? ImageMediaId,
    double CropFocusX, double CropFocusY, double CropZoom);
public sealed record MigrationShip(string? InstanceId, MigrationShipFields Fields,
    DateTimeOffset? LocalAddedAt = null);
public sealed record MigrationHangarSource(MigrationOwner Owner, string IdentityNamespace,
    MigrationSourceState State, IReadOnlyList<MigrationShip> Ships);
public enum MigrationRowState { SharedFieldsMatch, Different, LocalOnly, ServerOnly, Ambiguous, NotCompared }
public sealed record MigrationPreviewRow(int? LocalIndex, int? ServerIndex, MigrationRowState State);
public sealed record HangarMigrationPreviewResult(bool SourcesComparable, IReadOnlyList<MigrationPreviewRow> Rows);
public enum ObservedMigrationRowState { SharedFieldsMatch, Different, NotObservedOnServer, NotObservedLocally, Ambiguous, NotCompared }
public sealed record ObservedMigrationRow(int? LocalIndex, int? ServerIndex, ObservedMigrationRowState State);
public sealed record ObservedHangarComparison(bool CanCompareObservedRecords, bool BothSourcesComplete,
    IReadOnlyList<ObservedMigrationRow> Rows);

public static class HangarMigrationPreview
{
    // Stable field keys for presentation; this does not select a winning value.
    public static IReadOnlyList<string> DifferentFields(MigrationShipFields local, MigrationShipFields server)
    {
        ArgumentNullException.ThrowIfNull(local);
        ArgumentNullException.ThrowIfNull(server);
        var fields = new List<string>();
        if (local.Code != server.Code) fields.Add("code");
        if (local.DisplayName != server.DisplayName) fields.Add("displayName");
        if (local.Source != server.Source) fields.Add("source");
        if (local.ImportedAt != server.ImportedAt) fields.Add("importedAt");
        if (local.SyncedAt != server.SyncedAt) fields.Add("syncedAt");
        if (local.ImageMediaId != server.ImageMediaId) fields.Add("imageMediaId");
        if (local.CropFocusX != server.CropFocusX) fields.Add("cropFocusX");
        if (local.CropFocusY != server.CropFocusY) fields.Add("cropFocusY");
        if (local.CropZoom != server.CropZoom) fields.Add("cropZoom");
        return fields.ToArray();
    }
    public static HangarMigrationPreviewResult Compare(MigrationHangarSource local, MigrationHangarSource server)
        => CompareCore(local, server, allowPartial: false);

    // Compares only records actually observed. Absence is not deletion, and even
    // matching shared fields never authorizes overwriting local-only metadata.
    public static ObservedHangarComparison CompareObserved(MigrationHangarSource local, MigrationHangarSource server)
    {
        var result = CompareCore(local, server, allowPartial: true);
        return new(result.SourcesComparable,
            local.State == MigrationSourceState.Complete && server.State == MigrationSourceState.Complete,
            result.Rows.Select(r => new ObservedMigrationRow(r.LocalIndex, r.ServerIndex, r.State switch
            {
                MigrationRowState.SharedFieldsMatch => ObservedMigrationRowState.SharedFieldsMatch,
                MigrationRowState.Different => ObservedMigrationRowState.Different,
                MigrationRowState.LocalOnly => ObservedMigrationRowState.NotObservedOnServer,
                MigrationRowState.ServerOnly => ObservedMigrationRowState.NotObservedLocally,
                MigrationRowState.Ambiguous => ObservedMigrationRowState.Ambiguous,
                _ => ObservedMigrationRowState.NotCompared,
            })).ToArray());
    }

    private static HangarMigrationPreviewResult CompareCore(MigrationHangarSource local, MigrationHangarSource server,
        bool allowPartial)
    {
        Validate(local);
        Validate(server);
        // No username/case normalization or inferred legacy-to-SCM identity mapping.
        if (local.Owner != server.Owner) throw new ArgumentException("Source owners differ.");
        var left = local.Ships.ToArray();
        var right = server.Ships.ToArray();
        if (local.State == MigrationSourceState.Unavailable || server.State == MigrationSourceState.Unavailable ||
            (!allowPartial && (local.State != MigrationSourceState.Complete || server.State != MigrationSourceState.Complete)) ||
            local.IdentityNamespace != server.IdentityNamespace)
            return new(false, left.Select((_, i) => new MigrationPreviewRow(i, null, MigrationRowState.NotCompared))
                .Concat(right.Select((_, i) => new MigrationPreviewRow(null, i, MigrationRowState.NotCompared))).ToArray());
        var leftIds = Index(left);
        var rightIds = Index(right);
        var used = new HashSet<int>();
        var rows = new List<MigrationPreviewRow>();
        for (var i = 0; i < left.Length; i++)
        {
            var id = left[i].InstanceId;
            if (string.IsNullOrWhiteSpace(id) || leftIds[id].Count != 1 ||
                (rightIds.TryGetValue(id, out var candidates) && candidates.Count != 1))
            {
                rows.Add(new(i, null, MigrationRowState.Ambiguous));
                continue;
            }
            if (!rightIds.TryGetValue(id, out candidates))
            {
                rows.Add(new(i, null, MigrationRowState.LocalOnly));
                continue;
            }
            var j = candidates[0];
            used.Add(j);
            // Equal shared fields is NOT proof that local-only metadata, media
            // bytes or future fields can be discarded, or that import is lossless.
            rows.Add(new(i, j, left[i].Fields == right[j].Fields
                ? MigrationRowState.SharedFieldsMatch : MigrationRowState.Different));
        }
        for (var j = 0; j < right.Length; j++)
        {
            if (used.Contains(j)) continue;
            var id = right[j].InstanceId;
            var ambiguous = string.IsNullOrWhiteSpace(id) || rightIds[id].Count != 1 ||
                (leftIds.TryGetValue(id, out var candidates) && candidates.Count != 1);
            rows.Add(new(null, j, ambiguous ? MigrationRowState.Ambiguous : MigrationRowState.ServerOnly));
        }
        return new(true, rows.ToArray());
    }

    private static Dictionary<string, List<int>> Index(MigrationShip[] ships)
    {
        var result = new Dictionary<string, List<int>>(StringComparer.Ordinal);
        for (var i = 0; i < ships.Length; i++)
        {
            if (string.IsNullOrWhiteSpace(ships[i].InstanceId)) continue;
            var id = ships[i].InstanceId!;
            if (!result.TryGetValue(id, out var indices)) result.Add(id, indices = []);
            indices.Add(i);
        }
        return result;
    }

    private static void Validate(MigrationHangarSource source)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (source.Owner is null || new[] { source.Owner.Environment, source.Owner.Authority,
                source.Owner.Subject, source.IdentityNamespace }.Any(string.IsNullOrWhiteSpace) ||
            !Enum.IsDefined(source.State) || source.Ships is null || source.Ships.Count > 10000 ||
            source.Ships.Any(s => s is null || s.Fields is null ||
                !double.IsFinite(s.Fields.CropFocusX) || !double.IsFinite(s.Fields.CropFocusY) ||
                !double.IsFinite(s.Fields.CropZoom)))
            throw new ArgumentException("Invalid migration source.");
    }
}
