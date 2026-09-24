using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Updates;

// Fingerprints must be calculated by the trusted coordinator from fresh evidence,
// never accepted from Flutter/installer UI as proof of installation ownership.
internal sealed record WpfMigrationBinding(string Version, string InstallerSha256,
    string OldInstallationFingerprint, string DestinationFingerprint, string DataLocationFingerprint);
internal sealed record WpfMigrationConfirmation(int SchemaVersion, string Id,
    WpfMigrationBinding Binding, string State, WpfMigrationStartupExpectation? Startup = null);
internal sealed record WpfMigrationStartupExpectation(string Nonce, int ClientProcessId,
    DateTimeOffset StartedAt, DateTimeOffset ExpiresAt);

/// <summary>Durable consent bookkeeping only. Not a signature/trust authority or
/// permission to uninstall. An interrupted attempt must be inspected, never replayed.</summary>
internal sealed class WpfMigrationConfirmationStore
{
    private readonly string _directory;
    private readonly TimeProvider _clock;
    private string? _armedConfirmationId;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };

    internal WpfMigrationConfirmationStore(string ownedDirectory, TimeProvider? clock = null)
    {
        _clock = clock ?? TimeProvider.System;
        if (!Path.IsPathFullyQualified(ownedDirectory)) throw new InvalidDataException("Absolute journal directory required.");
        _directory = Path.TrimEndingDirectorySeparator(Path.GetFullPath(ownedDirectory));
        if (_directory.StartsWith(@"\\", StringComparison.Ordinal) || _directory == Path.GetPathRoot(_directory))
            throw new InvalidDataException("Invalid journal directory.");
        RequireDirectory(); // Caller provisions a dedicated directory, not arbitrary user paths.
    }

    internal WpfMigrationConfirmation Confirm(WpfMigrationBinding binding, bool accepted)
    {
        if (!accepted) throw new InvalidOperationException("Migration was not accepted.");
        Validate(binding);
        using var lease = Lock();
        if (Read() is not null) throw new InvalidOperationException("An existing migration must be inspected first.");
        var value = new WpfMigrationConfirmation(1, Guid.NewGuid().ToString("N"), binding, "confirmed");
        Write(value);
        return value;
    }

    internal WpfMigrationConfirmation? Inspect()
    {
        using var lease = Lock();
        return Read();
    }

    internal void MarkInstallStarted(string confirmationId, WpfMigrationBinding current)
    {
        Validate(current);
        using var lease = Lock();
        var value = Read();
        if (value is null || value.Id != confirmationId || value.Binding != current || value.State != "confirmed")
            throw new InvalidOperationException("Confirmation changed or installation may already have started.");
        // Persist BEFORE launching setup; uncertain launches must not be silently retried.
        Write(value with { State = "install-started" });
    }

    // Called only by the coordinator that owns the newly launched Process object.
    // PID/nonce are not accepted from client UI. Reopening this store never restores
    // authority to accept a receipt from an interrupted attempt.
    internal void AwaitStartup(string confirmationId, WpfMigrationBinding current,
        string nonce, int clientProcessId)
    {
        Validate(current);
        using var lease = Lock();
        var value = Read();
        if (value is null || value.Id != confirmationId || value.Binding != current ||
            value.State != "startup-launching")
            throw new InvalidOperationException("Installation is not awaiting its first startup.");
        var now = _clock.GetUtcNow();
        var expectation = new WpfMigrationStartupExpectation(nonce, clientProcessId, now, now.AddMinutes(2));
        ValidateStartup(expectation);
        Write(value with { State = "awaiting-startup", Startup = expectation });
        _armedConfirmationId = confirmationId;
    }

    internal void ReserveStartup(string confirmationId, WpfMigrationBinding current)
    {
        Validate(current);
        using var lease = Lock();
        var value = Read();
        if (value is null || value.Id != confirmationId || value.Binding != current || value.State != "install-started")
            throw new InvalidOperationException("Startup may already have been attempted.");
        // Persist before Process.Start; an uncertain launch must not be replayed.
        Write(value with { State = "startup-launching" });
    }

    internal void MatchStartupReceipt(string confirmationId, WpfMigrationBinding current,
        FlutterUpdateStartupReceipt receipt)
    {
        Validate(current);
        using var lease = Lock();
        var value = Read();
        if (_armedConfirmationId != confirmationId || value is null || value.Id != confirmationId ||
            value.Binding != current || value.State != "awaiting-startup" || value.Startup is null)
            throw new InvalidOperationException("Startup must be inspected after interruption.");
        var startup = value.Startup;
        var now = _clock.GetUtcNow();
        if (now < startup.StartedAt || now >= startup.ExpiresAt)
            throw new InvalidDataException("Startup evidence expired.");
        FlutterStartupReceiptValidator.RequireMatch(receipt, startup.Nonce, current.Version, startup.ClientProcessId);
        // A matched receipt is NOT data compatibility, process ownership, shortcut
        // handoff or uninstall permission. Those gates remain separate and closed.
        Write(value with { State = "startup-receipt-matched" });
        _armedConfirmationId = null;
    }

    private static void ValidateStartup(WpfMigrationStartupExpectation startup)
    {
        if (startup.Nonce is null || startup.Nonce.Length != 64 || startup.Nonce.Any(c => !Uri.IsHexDigit(c)) ||
            startup.ClientProcessId <= 0 || startup.ExpiresAt - startup.StartedAt != TimeSpan.FromMinutes(2))
            throw new InvalidDataException("Invalid startup expectation.");
    }

    private FileStream Lock()
    {
        RequireDirectory();
        var path = Path.Combine(_directory, "migration.lock");
        RequirePlainFileIfPresent(path);
        return new(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }

    private WpfMigrationConfirmation? Read()
    {
        var path = Path.Combine(_directory, "confirmation.json");
        RequirePlainFileIfPresent(path);
        FileStream stream;
        try { stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read); }
        catch (FileNotFoundException) { return null; }
        using (stream)
        {
            if (stream.Length > 16384) throw new InvalidDataException("Oversized confirmation.");
            var value = JsonSerializer.Deserialize<WpfMigrationConfirmation>(stream, Json)
                ?? throw new InvalidDataException("Missing confirmation.");
            if (value.SchemaVersion != 1 || !Guid.TryParseExact(value.Id, "N", out _) ||
                value.State is not ("confirmed" or "install-started" or "startup-launching" or "awaiting-startup" or "startup-receipt-matched"))
                throw new InvalidDataException("Invalid confirmation.");
            if (value.State is "awaiting-startup" or "startup-receipt-matched")
            {
                if (value.Startup is null) throw new InvalidDataException("Missing startup expectation.");
                ValidateStartup(value.Startup);
            }
            else if (value.Startup is not null) throw new InvalidDataException("Unexpected startup expectation.");
            Validate(value.Binding);
            return value;
        }
    }

    private void Write(WpfMigrationConfirmation value)
    {
        RequireDirectory();
        var target = Path.Combine(_directory, "confirmation.json");
        RequirePlainFileIfPresent(target);
        var temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, value, Json);
            stream.Flush(flushToDisk: true);
        }
        // An abandoned temporary file never counts as confirmation after interruption.
        File.Move(temporary, target, overwrite: true);
    }

    private void RequireDirectory()
    {
        if (!Directory.Exists(_directory)) throw new DirectoryNotFoundException("Journal directory is unavailable.");
        for (var part = new DirectoryInfo(_directory); part is not null; part = part.Parent)
            if ((File.GetAttributes(part.FullName) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Journal directory cannot traverse a link.");
    }

    private static void RequirePlainFileIfPresent(string path)
    {
        try
        {
            var attributes = File.GetAttributes(path);
            if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
                throw new InvalidDataException("Journal entry is not a regular file.");
        }
        catch (FileNotFoundException) { }
    }

    private static void Validate(WpfMigrationBinding? binding)
    {
        if (binding is null || !Version.TryParse(binding.Version, out _)) throw new InvalidDataException("Invalid migration binding.");
        foreach (var hash in new[] { binding.InstallerSha256, binding.OldInstallationFingerprint,
            binding.DestinationFingerprint, binding.DataLocationFingerprint })
            if (hash is null || hash.Length != 64 || hash.Any(c => !Uri.IsHexDigit(c)))
                throw new InvalidDataException("Invalid migration fingerprint.");
    }
}
