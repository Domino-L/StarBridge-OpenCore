using System.Text;
using StarBridge.Core.Hangar;
using StarBridge.HostRuntime.Hangar;

internal static class LegacyHangarMigrationReaderTests
{
    internal static void Verify()
    {
        var owner = new MigrationOwner("production", "legacy", "fixture");
        var date = DateTimeOffset.UnixEpoch.ToString("O");
        var row = $"code\tname\tsource\t{date}\t{date}\t\tid-1\tmedia\t0.5\t0.5\t1";
        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(row + "\r\n" + row + "\r\n")).ToArray();
        var original = bytes.ToArray();
        var result = LegacyHangarMigrationReader.Read(bytes, owner);
        Assert(result.Source.State == MigrationSourceState.Complete && result.Rows.Count == 2, "complete rows");
        Assert(result.Source.Ships.Count == 2 && result.Source.Ships[0].Fields.ImageMediaId == "media", "duplicates/media retained");
        Assert(result.Source.Ships[0].LocalAddedAt == DateTimeOffset.UnixEpoch, "local date retained");
        Assert(bytes.SequenceEqual(original) && result.Sha256.Length == 64, "read-only fingerprint");
        foreach (var bad in new[] { "old\tformat\tsource\t" + date, row + "\tfuture", row.Replace("0.5", "NaN"), row.Replace(date, "invalid"), "" })
        {
            var partial = LegacyHangarMigrationReader.Read(Encoding.UTF8.GetBytes(row + "\n" + bad + "\n"), owner);
            Assert(partial.Source.State == MigrationSourceState.Partial && partial.Rows.Count == 2 && partial.Rows[1].Raw == bad,
                "bad rows retained for review");
            Assert(!HangarMigrationPreview.Compare(partial.Source, result.Source).SourcesComparable, "partial not compared");
        }
        Assert(LegacyHangarMigrationReader.Read([], owner).Source.State == MigrationSourceState.Complete, "explicit empty bytes");
        try { LegacyHangarMigrationReader.Read(new byte[] { 0xff }, owner); throw new Exception("encoding accepted"); }
        catch (DecoderFallbackException) { }
        try { LegacyHangarMigrationReader.Read(new byte[4 * 1024 * 1024 + 1], owner); throw new Exception("oversize accepted"); }
        catch (InvalidDataException) { }
        var directory = Path.Combine(Path.GetTempPath(), "starbridge-migration-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "synthetic.database");
        try
        {
            Assert(LegacyHangarMigrationFile.Inspect(path, owner).State == "not-present", "missing is not empty");
            File.WriteAllBytes(path, bytes);
            Assert(LegacyHangarMigrationFile.Inspect(path, owner).Snapshot?.Sha256 == result.Sha256, "file snapshot hash");
            using (var locked = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                Assert(LegacyHangarMigrationFile.Inspect(path, owner).State == "unavailable", "locked is not empty");
            Assert(File.ReadAllBytes(path).SequenceEqual(original), "source bytes untouched");
            Assert(LegacyHangarMigrationFile.Inspect("relative.database", owner).State == "unavailable", "relative path rejected");
            File.WriteAllBytes(path, [0xff]);
            Assert(LegacyHangarMigrationFile.Inspect(path, owner).State == "unavailable", "encoding failure not empty");
        }
        finally { File.Delete(path); Directory.Delete(directory); }
        Console.WriteLine("PASS legacy hangar read-only decoding, provenance and partial-source protection");
    }
    private static void Assert(bool value, string reason) { if (!value) throw new Exception(reason); }
}
