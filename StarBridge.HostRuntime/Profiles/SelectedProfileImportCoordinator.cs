using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Profiles;

/// <summary>Coordinates an explicit Java import with the existing local presentation.
/// A status read never writes profile data. Confirmation/recovery remains explicit.</summary>
internal sealed partial class SelectedProfileImportCoordinator(LocalPersonalProfileStore profiles,
    Hangar.LocalHangarStore? hangar = null)
{
    internal sealed record Intent(string Ticket, long ExpectedRevision, string Operation,
        LocalProfileContent? Content, LegacyProfileMigrationView Preview, bool Confirmed = false, bool Applied = false,
        LocalProfileSnapshot? Previous = null, long? HangarRevision = null)
    {
        [JsonIgnore]
        internal bool ShowcaseAdditionsUnavailable { get; init; }
    }
    private sealed record Envelope(int Version, string Owner, Intent? Intent);
    private const int Limit = 512 * 1024;

    internal async Task<T> RunAsync<T>(BridgeAccountContext owner, Func<bool> current, Func<Session, Task<T>> action)
    {
        if (!owner.IsComplete || !current()) throw new LocalProfileException("profile_local.account_changed");
        var key = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(owner)));
        var directory = profiles.ImportJournalDirectory;
        Check(directory);
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, key + ".dat");
        Check(path); Check(path + ".lock");
        using var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        var entropy = Encoding.UTF8.GetBytes("StarBridge.SelectedProfileImport.v1\0" + key);
        Intent? intent = null;
        string? committedHash = null;
        if (File.Exists(path))
        {
            if (new FileInfo(path).Length > Limit) throw new IOException("Import journal too large.");
            var clear = ProtectedData.Unprotect(File.ReadAllBytes(path), entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length > Limit) throw new IOException("Import journal too large.");
                using var document = JsonDocument.Parse(clear);
                LocalPersonalProfileStore.RejectDuplicates(document.RootElement);
                var saved = JsonSerializer.Deserialize<Envelope>(clear, LocalPersonalProfileStore.Json);
                if (saved is null || saved.Version != 1 || saved.Owner != key) throw new IOException("Invalid import owner.");
                intent = saved.Intent;
                if (intent is not null) Validate(intent);
                committedHash = OperationBinding(clear);
                intent = ReadAdditions(path + ".showcases", key, entropy, committedHash, Digest(clear), intent);
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        void Persist(Intent value)
        {
            Validate(value);
            if (!current()) throw new LocalProfileException("profile_local.account_changed");
            var clear = FrozenBytes(key, value);
            string nextHash;
            byte[] encrypted;
            try
            {
                if (clear.Length > Limit / 2) throw new IOException("Import journal too large.");
                nextHash = OperationBinding(clear);
                encrypted = ProtectedData.Protect(clear, entropy, DataProtectionScope.CurrentUser);
                var additions = AdditionsFor(value);
                // The same committed base cannot acquire a different content identity.
                if (committedHash == nextHash && intent is not null &&
                    JsonSerializer.Serialize(AdditionsFor(intent), LocalPersonalProfileStore.Json) !=
                    JsonSerializer.Serialize(additions, LocalPersonalProfileStore.Json))
                    throw new IOException("Import journal content changed without a new operation.");
                // A progress update cannot turn missing or unreadable additions into an empty copy.
                if (committedHash != nextHash || !value.ShowcaseAdditionsUnavailable)
                {
                    var entries = new List<AdditionEntry>();
                    if (committedHash is not null && intent is not null && committedHash != nextHash)
                        entries.Add(new(committedHash, AdditionsFor(intent)));
                    entries.Add(new(nextHash, additions));
                    WriteAdditions(path + ".showcases", key, entropy, entries.ToArray(), current);
                }
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                Check(directory); Check(path);
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { stream.Write(encrypted); stream.Flush(true); }
                if (!current()) throw new LocalProfileException("profile_local.account_changed");
                if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
                committedHash = nextHash;
                intent = value;
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        return await action(new Session(profiles, hangar, owner, intent, current, Persist));
    }

    internal sealed class Session(LocalPersonalProfileStore profiles, Hangar.LocalHangarStore? hangar, BridgeAccountContext owner,
        Intent? intent, Func<bool> current, Action<Intent> persist)
    {
        private void Save(Intent next) { persist(next); intent = next; }
        internal void BeforePreview(LegacyProfileImportSelection? selection)
        {
            if (selection?.PreviousCompletedPreviewId is not { } previous) return;
            // A new round must not destroy this device's un-applied recovery intent.
            if (intent is not { Applied: true } || intent.Ticket != previous)
                throw new LocalProfileException("profile_local.import_preview_required");
            if (!current()) throw new LocalProfileException("profile_local.account_changed");
        }
        internal LegacyProfileMigrationView Stage(LegacyProfileMigrationView view, LegacyProfileImportSelection? requested = null)
        {
            if (view.Choices?.Version == 2)
            {
                if (requested?.ReplaceAllDisplayContent != true)
                    return new("selectionAlreadyCompleted");
                if (view.State == "completed")
                {
                    if (intent is { Applied: true } && intent.Ticket == view.PreviewId) return view;
                    view = view with { State = "previewed", Conflict = true, ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(15) };
                }
                if (view.State != "previewed") return Status(view);
                var before = profiles.Read(owner);
                var inventory = view.Presentation?.Content.FavoriteShipCodes.Length > 0 ? hangar?.Read(owner) : null;
                var projectedFull = FullProfilePresentationImport.Project(view, inventory);
                Save(new(view.PreviewId!, before.Revision, Guid.NewGuid().ToString("N"), projectedFull, view,
                    Previous: before, HangarRevision: inventory?.Revision));
                return view;
            }
            if (view.State == "completed" && view.Choices is { } receipt && view.SelectedContent is not null)
            {
                if (requested is null || !requested.Modules.SequenceEqual(receipt.Modules) ||
                    requested.UseLegacyCallSign != receipt.UseLegacyCallSign || requested.UseLegacyAvatar != receipt.UseLegacyAvatar)
                    return new("selectionAlreadyCompleted");
                if (intent is { Applied: true } && intent.Ticket == view.PreviewId) return view;
                // Explicit re-preview can rebase only the already imported fields onto
                // this device's current revision; it does not perform another Java write.
                view = view with { State = "previewed", ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(15),
                    Choices = receipt with { ReplaceModules = requested.ReplaceModules } };
            }
            if (view.State != "previewed") return Status(view);
            if (view.Choices is null || view.SelectedContent is null || !view.SelectedContent.Matches(view.Choices))
                throw new LocalProfileException("profile_local.invalid_request");
            var snapshot = profiles.Read(owner);
            LocalProfileContent? projected = null;
            if (snapshot.Content is { } existing)
            {
                var selected = view.SelectedContent;
                var incoming = existing with
                {
                    CallSign = selected.CallSign ?? existing.CallSign,
                    Modules = selected.Modules.Select(m => new LocalProfileLayout(m.Id, m.Span, false, -1,
                        m.Id == "favorite-ships" ? [] : null)).ToArray(),
                    FavoriteShipIds = [],
                    MainRole = null,
                    PlayStyle = selected.SkilledRoles is null ? null : new(selected.SkilledRoles,
                        selected.ParticipationInterests, selected.SupportCapabilities)
                };
                projected = SelectedLocalProfileImport.Project(existing, incoming, new(view.Choices.Modules,
                    view.Choices.ReplaceModules, view.Choices.UseLegacyCallSign, view.Choices.UseLegacyAvatar))
                    with { FieldStates = null };
            }
            Save(new(view.PreviewId!, snapshot.Revision, Guid.NewGuid().ToString("N"), projected, view));
            return view;
        }
        internal LegacyProfileMigrationView Status(LegacyProfileMigrationView remote)
        {
            if (remote.State == "completed" && remote.Choices is not null)
            {
                if (intent is null || intent.Ticket != remote.PreviewId) return remote with { State = "localPreviewRequired" };
                if (!intent.Applied) return intent.Preview with { State = "localApplyRequired" };
            }
            return remote;
        }
        internal void BeforeConfirm(string ticket, bool recordConsent = true)
        {
            if (intent is null || intent.Ticket != ticket) throw new LocalProfileException("profile_local.import_preview_required");
            if (intent.Applied) return;
            if (!current()) throw new LocalProfileException("profile_local.account_changed");
            if (intent.HangarRevision is { } inventoryRevision && hangar?.Read(owner).Revision != inventoryRevision)
                throw new LocalProfileException("profile_local.conflict");
            var snapshot = profiles.Read(owner);
            if (snapshot.Revision != intent.ExpectedRevision && !AlreadySaved())
                throw new LocalProfileException("profile_local.conflict");
            if (recordConsent) Save(intent with { Confirmed = true });
        }
        internal LegacyProfileMigrationView Apply(LegacyProfileMigrationView remote)
        {
            if (remote.State != "completed") return remote;
            if (intent is not { Confirmed: true } || intent.Ticket != remote.PreviewId)
                return remote with { State = "localPreviewRequired" };
            if (intent.Applied) return remote;
            if (!current()) throw new LocalProfileException("profile_local.account_changed");
            // Never substitute a later server projection for the user-approved preview.
            if (JsonSerializer.Serialize(remote.SelectedContent) != JsonSerializer.Serialize(intent.Preview.SelectedContent) ||
                JsonSerializer.Serialize(remote.Presentation) != JsonSerializer.Serialize(intent.Preview.Presentation) ||
                remote.Choices is null || JsonSerializer.Serialize(remote.Choices with {
                    ReplaceModules = intent.Preview.Choices!.ReplaceModules }) != JsonSerializer.Serialize(intent.Preview.Choices))
                throw new LocalProfileException("profile_local.invalid_request");
            if (intent.HangarRevision is { } inventoryRevision && hangar?.Read(owner).Revision != inventoryRevision)
                throw new LocalProfileException("profile_local.conflict");
            if (intent.Content is { } content)
            {
                // Selected modules and tags come from the preview. Preserve
                // explicit clears only for untouched groups on the live revision.
                var before = profiles.Read(owner);
                var choices = intent.Preview.Choices!;
                var clears = choices.Version == 1 && before.Revision == intent.ExpectedRevision
                    ? before.Content?.FieldStates?.Where(field => field.Key switch
                    {
                        "modules" => choices.Modules.Length == 0,
                        "roles" or "interests" or "support" => !choices.Modules.Contains("skilled-roles", StringComparer.Ordinal),
                        "favoriteShipIds" => !choices.Modules.Contains("favorite-ships", StringComparer.Ordinal),
                        _ => true
                    }).ToDictionary(field => field.Key, field => field.Value, StringComparer.Ordinal)
                    : null;
                profiles.SaveImported(owner, intent.ExpectedRevision, intent.Operation,
                    content with { FieldStates = clears is { Count: > 0 } ? clears : null }, current,
                    hasJournalShowcases: !intent.ShowcaseAdditionsUnavailable ||
                        content.Showcases is not null || content.AchievementShowcase is not null);
            }
            else if (profiles.Read(owner).Revision != intent.ExpectedRevision)
                throw new LocalProfileException("profile_local.conflict");
            Save(intent with { Applied = true });
            return remote;
        }
        internal bool FullPresentation(string ticket) => intent?.Ticket == ticket && intent.Preview.Choices?.Version == 2;
        private bool AlreadySaved() => intent is not null &&
            profiles.IsCommittedImport(owner, intent.ExpectedRevision, intent.Operation, intent.Content);
    }
    private static void Validate(Intent intent)
    {
        if (string.IsNullOrWhiteSpace(intent.Ticket) || intent.Ticket.Length > 64 || intent.ExpectedRevision < 0 ||
            !Guid.TryParseExact(intent.Operation, "N", out _) || intent.Preview.State != "previewed" ||
            intent.Preview.PreviewId != intent.Ticket || intent.Preview.Choices is null ||
            (intent.Preview.Choices.Version == 2 ? intent.Preview.Presentation is null || intent.Previous is null || intent.Content is null
                : intent.Preview.SelectedContent is null || !intent.Preview.SelectedContent.Matches(intent.Preview.Choices)) ||
            intent.Applied && !intent.Confirmed)
            throw new IOException("Invalid import journal.");
        if (intent.Content is not null) LocalPersonalProfileStore.Validate(intent.Content);
        if (intent.Previous?.Content is { } previous) LocalPersonalProfileStore.Validate(previous);
    }
    private static void Check(string path)
    {
        for (string? item = Path.GetFullPath(path); item is not null; item = Directory.GetParent(item)?.FullName)
        {
            try
            {
                if ((File.GetAttributes(item) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Import path cannot traverse links.");
            }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
}
