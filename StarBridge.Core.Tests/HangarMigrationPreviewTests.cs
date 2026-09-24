using StarBridge.Core.Hangar;

namespace StarBridge.Core.Tests;

internal static class HangarMigrationPreviewTests
{
    internal static void RunAll()
    {
        var owner = new MigrationOwner("production", "legacy", "synthetic-owner");
        var fields = new MigrationShipFields("test-code", "same model", "test", DateTimeOffset.UnixEpoch,
            DateTimeOffset.UnixEpoch, "image-id", .5, .5, 1);
        var a = new MigrationShip("a", fields, DateTimeOffset.UnixEpoch.AddDays(1));
        var b = a with { InstanceId = "b" };
        if (!HangarMigrationPreview.DifferentFields(fields, fields with { DisplayName = "renamed", CropZoom = 2 })
                .SequenceEqual(new[] { "displayName", "cropZoom" }) ||
            HangarMigrationPreview.DifferentFields(fields, fields).Count != 0 ||
            HangarMigrationPreview.DifferentFields(fields, fields with { ImportedAt = fields.ImportedAt.ToOffset(TimeSpan.FromHours(2)) }).Count != 0)
            throw new Exception("Field details disagree with value equality or invent a winning source.");
        var wire = new ServerHangarSnapshot(1, "available", "synthetic-owner", "unknown", new string('A', 64), [a, b]);
        var roundTrip = System.Text.Json.JsonSerializer.Deserialize<ServerHangarSnapshot>(System.Text.Json.JsonSerializer.Serialize(wire))!;
        if (roundTrip.LocalCoverage != "unknown" || !roundTrip.Ships.SequenceEqual(new[] { a, b }))
            throw new Exception("Server snapshot contract lost instances or coverage semantics.");
        MigrationHangarSource Source(params MigrationShip[] ships) => new(owner, "legacy-instance-v1", MigrationSourceState.Complete, ships);
        void Check(MigrationHangarSource left, MigrationHangarSource right, params MigrationRowState[] expected)
        {
            var result = HangarMigrationPreview.Compare(left, right);
            if (!result.Rows.Select(r => r.State).SequenceEqual(expected)) throw new Exception("Incorrect preview classification.");
            if (result.Rows.Count(r => r.LocalIndex.HasValue) != left.Ships.Count ||
                result.Rows.Count(r => r.ServerIndex.HasValue) != right.Ships.Count)
                throw new Exception("Preview dropped an input record.");
        }
        Check(Source(a, b), Source(a with { LocalAddedAt = null }, b),
            MigrationRowState.SharedFieldsMatch, MigrationRowState.SharedFieldsMatch);
        Check(Source(a), Source(a with { Fields = fields with { ImageMediaId = null } }), MigrationRowState.Different);
        Check(Source(a), Source(a with { Fields = fields with { CropZoom = 2 } }), MigrationRowState.Different);
        Check(Source(a), Source(b), MigrationRowState.LocalOnly, MigrationRowState.ServerOnly);
        Check(Source(a, a), Source(a), MigrationRowState.Ambiguous, MigrationRowState.Ambiguous, MigrationRowState.Ambiguous);
        Check(Source(a), Source(a, a), MigrationRowState.Ambiguous, MigrationRowState.Ambiguous, MigrationRowState.Ambiguous);
        Check(Source(a with { InstanceId = null }), Source(b with { InstanceId = null }),
            MigrationRowState.Ambiguous, MigrationRowState.Ambiguous);
        Check(Source(a), Source(), MigrationRowState.LocalOnly);
        foreach (var state in new[] { MigrationSourceState.Unavailable, MigrationSourceState.Partial })
        {
            var result = HangarMigrationPreview.Compare(Source(a), Source() with { State = state });
            if (result.SourcesComparable) throw new Exception("Unknown source treated as complete.");
            Check(Source(a), Source() with { State = state }, MigrationRowState.NotCompared);
        }
        Check(Source(a), Source(a) with { IdentityNamespace = "new-local-id-v1" },
            MigrationRowState.NotCompared, MigrationRowState.NotCompared);
        try
        {
            HangarMigrationPreview.Compare(Source(a), Source(a) with { Owner = owner with { Authority = "scm" } });
            throw new Exception("Different identity sources were merged.");
        }
        catch (ArgumentException) { }
        if (a.LocalAddedAt is null || a.Fields.ImageMediaId != "image-id") throw new Exception("Source was modified.");
        var partial = Source(a with { Fields = fields with { CropZoom = 2 } }, b) with { State = MigrationSourceState.Partial };
        var observed = HangarMigrationPreview.CompareObserved(Source(a, a with { InstanceId = "c" }), partial);
        if (!observed.CanCompareObservedRecords || observed.BothSourcesComplete ||
            !observed.Rows.Select(r => r.State).SequenceEqual(new[] {
                ObservedMigrationRowState.Different, ObservedMigrationRowState.NotObservedOnServer,
                ObservedMigrationRowState.NotObservedLocally }))
            throw new Exception("Observed comparison confused incomplete coverage with deletion or matching models.");
        var duplicate = HangarMigrationPreview.CompareObserved(Source(a, a), partial);
        if (duplicate.Rows.Count != 4 || duplicate.Rows.Take(3).Any(r => r.State != ObservedMigrationRowState.Ambiguous))
            throw new Exception("Observed comparison paired a duplicate identity.");
        var unknown = HangarMigrationPreview.CompareObserved(Source(a), partial with { State = MigrationSourceState.Unavailable });
        if (unknown.CanCompareObservedRecords || unknown.Rows.Any(r => r.State != ObservedMigrationRowState.NotCompared))
            throw new Exception("Unavailable records were compared.");
        var missing = HangarMigrationPreview.CompareObserved(Source(a with { InstanceId = null }), partial);
        if (missing.Rows[0].State != ObservedMigrationRowState.Ambiguous || missing.Rows.Count != 3)
            throw new Exception("Missing identity was paired by model.");
        var wrongNamespace = HangarMigrationPreview.CompareObserved(Source(a), partial with { IdentityNamespace = "other" });
        if (wrongNamespace.CanCompareObservedRecords) throw new Exception("Identity namespaces were mixed.");
        var shared = HangarMigrationPreview.CompareObserved(Source(a), Source(a with { LocalAddedAt = null }) with { State = MigrationSourceState.Partial });
        if (shared.Rows.Single().State != ObservedMigrationRowState.SharedFieldsMatch || shared.BothSourcesComplete)
            throw new Exception("Matching shared fields claimed a complete backup.");
        if (HangarMigrationPreview.Compare(Source(a), partial).SourcesComparable)
            throw new Exception("Strict comparison gate was weakened.");
        foreach (var left in new[] { Source(), Source(a, b), Source(a, a), Source(a with { InstanceId = "A" }) })
        foreach (var right in new[] { Source(), Source(a, b), Source(a, a), partial })
        {
            var comparison = HangarMigrationPreview.CompareObserved(left, right);
            var localIndices = comparison.Rows.Where(r => r.LocalIndex.HasValue).Select(r => r.LocalIndex!.Value).Order().ToArray();
            var serverIndices = comparison.Rows.Where(r => r.ServerIndex.HasValue).Select(r => r.ServerIndex!.Value).Order().ToArray();
            if (!localIndices.SequenceEqual(Enumerable.Range(0, left.Ships.Count)) ||
                !serverIndices.SequenceEqual(Enumerable.Range(0, right.Ships.Count)))
                throw new Exception("Observed comparison dropped or duplicated a source row.");
        }
        if (HangarMigrationPreview.CompareObserved(Source(a with { InstanceId = "A" }), partial).Rows[0].ServerIndex.HasValue)
            throw new Exception("Observed comparison normalized an instance identifier.");
        try
        {
            HangarMigrationPreview.CompareObserved(Source(a), partial with { Owner = owner with { Subject = "other" } });
            throw new Exception("Observed comparison crossed account boundaries.");
        }
        catch (ArgumentException) { }
    }
}
