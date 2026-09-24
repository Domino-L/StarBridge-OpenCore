using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Settings;

internal enum RetirementSlot { Startup, DesktopShortcut, MenuShortcut }
internal enum RetirementRepair { AlreadyPresent, Restored, Conflict, Failed }
internal sealed record RetirementEntry(RetirementSlot Slot, byte[] Content);
internal sealed record RetirementRecord(int Schema, string Binding, string Phase,
    RetirementEntry[] Entries, RetirementSlot[] Repaired, int? ExitCode = null);
internal sealed record RetirementOutcome(string State, int? ExitCode, RetirementSlot[] NeedsReview,
    bool InstallationStateVerified = false);

// Durability and replay control only. Not permission to uninstall: the caller must
// freshly verify registration, supported uninstaller, data separation and startup.
// Binding fingerprints that evidence; never take it from installer UI or a manifest.
internal sealed class WpfRetirementRecovery
{
    private readonly string _directory;
    private readonly Func<IDisposable> _acquireSettingsLease;
    private const int MaxBytes = 1024 * 1024;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };

    internal WpfRetirementRecovery(string ownedJournalDirectory, Func<IDisposable>? acquireSettingsLease = null)
    {
        if (!Path.IsPathFullyQualified(ownedJournalDirectory) ||
            ownedJournalDirectory.StartsWith(@"\\", StringComparison.Ordinal) ||
            Path.GetFullPath(ownedJournalDirectory) != ownedJournalDirectory ||
            Path.GetPathRoot(ownedJournalDirectory) == ownedJournalDirectory) throw new InvalidDataException();
        _directory = ownedJournalDirectory;
        _acquireSettingsLease = acquireSettingsLease ?? ApplicationStartupLease.Acquire;
        RequireDirectory();
    }

    internal async Task<RetirementOutcome> ExecuteAsync(string binding,
        Func<RetirementEntry[]> capture, Func<Task<int>> uninstall,
        Func<RetirementSlot, byte[], RetirementRepair> restoreMissing, Func<bool>? verifyInstallationState = null)
    {
        ValidateBinding(binding);
        using var lease = Lock();
        using var settingsLease = _acquireSettingsLease();
        if (Read() is not null) throw new InvalidOperationException("Inspect existing removal; never replay it.");
        var record = new RetirementRecord(1, binding, "prepared", capture(), []);
        Validate(record);
        record = record with { Entries = record.Entries.Select(x => x with { Content = x.Content.ToArray() }).ToArray() };
        Write(record); // No uninstall without durable, validated protection snapshot.
        record = record with { Phase = "removal-started" };
        Write(record); // Persist intent before invoking an operation with uncertain results.
        int code;
        try { code = await uninstall(); }
        catch { return new("removal-uncertain", null, record.Entries.Select(x => x.Slot).ToArray()); }
        record = record with { Phase = "repair-pending", ExitCode = code };
        Write(record);
        var outcome = Repair(record, restoreMissing);
        // Protection restoration and installation removal are separate facts.
        // Never infer the latter from exit code or persist this time-sensitive result.
        if (outcome.State == "protected" && verifyInstallationState is not null)
        {
            try { outcome = outcome with { InstallationStateVerified = verifyInstallationState() }; }
            catch { }
        }
        return outcome;
    }

    // Fresh process/installation inspection must show that no uninstaller is still
    // running. Recovery restores protection only: it never runs an uninstaller.
    internal RetirementOutcome Recover(string binding, bool removalDefinitelyStopped,
        Func<RetirementSlot, byte[], RetirementRepair> restoreMissing)
    {
        ValidateBinding(binding);
        using var lease = Lock();
        using var settingsLease = _acquireSettingsLease();
        var record = Read() ?? throw new InvalidOperationException("No retirement record.");
        if (record.Binding != binding) throw new InvalidOperationException("Installation evidence changed.");
        if (record.Phase == "prepared") return new("not-started", null, []);
        if (record.Phase is "protected" or "removal-needs-review") return new(record.Phase, record.ExitCode, []);
        if (!removalDefinitelyStopped) return new("inspection-required", record.ExitCode, []);
        // Between attempts the settings lease was released. An absent Run value
        // might now be a user's deliberate choice, not damage from the uninstaller.
        // Never restore an unfinished startup slot on a later attempt.
        return Repair(record, (slot, bytes) => slot == RetirementSlot.Startup
            ? RetirementRepair.Conflict : restoreMissing(slot, bytes));
    }

    private RetirementOutcome Repair(RetirementRecord record, Func<RetirementSlot, byte[], RetirementRepair> restoreMissing)
    {
        var review = new List<RetirementSlot>();
        foreach (var entry in record.Entries)
        {
            if (record.Repaired.Contains(entry.Slot)) continue;
            try
            {
                if (restoreMissing(entry.Slot, entry.Content.ToArray()) is not (RetirementRepair.AlreadyPresent or RetirementRepair.Restored))
                    review.Add(entry.Slot);
                else
                {
                    record = record with { Repaired = [.. record.Repaired, entry.Slot] };
                    Write(record); // Later retries cannot undo a user's change to an already-repaired slot.
                }
            }
            catch { review.Add(entry.Slot); }
        }
        // A nonzero/unknown exit is never converted into removal success by repair.
        var state = review.Count != 0 ? "repair-pending" : record.ExitCode == 0 ? "protected" : "removal-needs-review";
        Write(record with { Phase = state });
        return new(state, record.ExitCode, review.ToArray());
    }

    private FileStream Lock()
    {
        RequireDirectory();
        var path = Path.Combine(_directory, "retirement.lock");
        RequirePlainFile(path);
        return new(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    private RetirementRecord? Read()
    {
        var path = Path.Combine(_directory, "retirement.json");
        RequirePlainFile(path);
        FileStream stream;
        try { stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read); }
        catch (FileNotFoundException) { return null; }
        using (stream)
        {
            if (stream.Length > MaxBytes) throw new InvalidDataException("Oversized retirement record.");
            var record = JsonSerializer.Deserialize<RetirementRecord>(stream, Json) ?? throw new InvalidDataException();
            Validate(record);
            return record;
        }
    }
    private void Write(RetirementRecord record)
    {
        Validate(record);
        RequireDirectory();
        var target = Path.Combine(_directory, "retirement.json");
        RequirePlainFile(target);
        var temp = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
        using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, record, Json);
            stream.Flush(true);
        }
        File.Move(temp, target, true);
    }
    private void RequireDirectory()
    {
        if (!Directory.Exists(_directory)) throw new DirectoryNotFoundException();
        for (var part = new DirectoryInfo(_directory); part is not null; part = part.Parent)
            if ((part.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Linked journal.");
    }
    private static void RequirePlainFile(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
                throw new InvalidDataException("Non-regular journal entry.");
        }
        catch (FileNotFoundException) { }
    }
    private static void ValidateBinding(string binding)
    {
        if (binding is null || binding.Length != 64 || binding.Any(c => !Uri.IsHexDigit(c))) throw new InvalidDataException("Invalid binding.");
    }
    private static void Validate(RetirementRecord record)
    {
        ValidateBinding(record.Binding);
        if (record.Schema != 1 || record.Phase is not ("prepared" or "removal-started" or "repair-pending" or "protected" or "removal-needs-review") ||
            record.Entries is null || record.Entries.Length > 3 || record.Entries.Any(x => x is null || !Enum.IsDefined(x.Slot) || x.Content is null || x.Content.Length == 0 || x.Content.Length > 196608) ||
            record.Entries.Select(x => x.Slot).Distinct().Count() != record.Entries.Length ||
            record.Repaired is null || record.Repaired.Distinct().Count() != record.Repaired.Length ||
            record.Repaired.Any(x => !record.Entries.Any(e => e.Slot == x)) ||
            (record.Phase is "prepared" or "removal-started" && record.ExitCode is not null) ||
            (record.Phase == "protected" && record.ExitCode != 0)) throw new InvalidDataException("Invalid retirement record.");
    }
}
