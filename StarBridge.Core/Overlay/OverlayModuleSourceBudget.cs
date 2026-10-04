namespace StarBridge.Core.Overlay;

/// <summary>Session-scoped source admission. Stores intent and budget state only,
/// never payloads or grants. Both display and shared refresh use this interface.</summary>
public sealed class OverlayModuleSourceBudget
{
    internal sealed record Scope(string Owner, long Generation, string Policy, OverlaySourceBinding AccountChoice,
        OverlaySourceBinding? Temporary, string? Focus, string Modules);
    public sealed class Admission
    {
        internal readonly Scope Scope;
        internal readonly OverlayPresetSources Preset;
        internal readonly IReadOnlyCollection<OverlaySourceModule> Modules;
        internal Admission(Scope scope, OverlayPresetSources preset, IReadOnlyCollection<OverlaySourceModule>? modules)
        { Scope = scope; Preset = preset; Modules = Array.AsReadOnly((modules ?? Enum.GetValues<OverlaySourceModule>()).ToArray()); }
    }
    private readonly object _gate = new();
    private Scope? _scope;
    private HashSet<string>? _blocked;
    private Admission? _admission;
    private long _evidenceVersion;
    public long EvidenceVersion { get { lock (_gate) return _evidenceVersion; } }
    public bool RequiresRoomConfirmation(string owner, long generation)
    {
        lock (_gate) return _scope?.Owner == owner && _scope.Generation == generation &&
            _blocked?.Any(key => key.StartsWith("Room:", StringComparison.Ordinal)) == true;
    }
    public bool RequiresCommunityConfirmation(string owner, long generation)
    {
        lock (_gate) return _scope?.Owner == owner && _scope.Generation == generation &&
            _blocked?.Any(key => key.StartsWith("Community:", StringComparison.Ordinal)) == true;
    }
    public bool TryResolve(OverlayPresetSources preset, OverlaySourceResolutionContext context, long evidenceVersion,
        OverlaySourceBinding? temporaryChoice = null, IReadOnlyCollection<OverlaySourceModule>? activeModules = null)
    {
        lock (_gate)
        {
            if (evidenceVersion != _evidenceVersion) return false;
            Resolve(preset, context, temporaryChoice, activeModules);
            return true;
        }
    }

    public OverlayModuleSourcePlan Resolve(OverlayPresetSources preset, OverlaySourceResolutionContext context,
        OverlaySourceBinding? temporaryChoice = null, IReadOnlyCollection<OverlaySourceModule>? activeModules = null)
    {
        var scope = CreateScope(preset, context, temporaryChoice, activeModules);
        lock (_gate)
        {
            // A late caller must not reset the newer account's admission state.
            // Its frame still performs the ordinary current-owner authorization.
            if (_scope is not null && scope.Generation < _scope.Generation)
                return OverlayModuleSourceResolver.Resolve(preset, context, temporaryChoice, activeModules);
            if (_scope != scope)
            {
                var focusOnly = _scope is not null && _scope with { Focus = scope.Focus } == scope;
                // Focus/account choice may change automatic resolution, but
                // need not interrupt a module with an unchanged explicit source.
                // Probes resolve against the latest context and compare targets.
                if (_admission is null || !SameIntent(_admission.Scope, scope))
                    _admission = new(scope, preset, activeModules);
                _scope = scope;
                if (!focusOnly) _blocked = null;
            }
            if (_blocked is not null) throw new OverlaySourceLimitException(_blocked);
            try { return OverlayModuleSourceResolver.Resolve(preset, context, temporaryChoice, activeModules); }
            catch (OverlaySourceLimitException error)
            {
                _blocked = error.ResourceKeys.ToHashSet(StringComparer.Ordinal);
                throw;
            }
        }
    }

    private static Scope CreateScope(OverlayPresetSources preset, OverlaySourceResolutionContext context,
        OverlaySourceBinding? temporary, IReadOnlyCollection<OverlaySourceModule>? modules) =>
        new(context.OwnerKey, context.Generation,
            OverlayPresetSourcesCodec.Serialize(new(preset.Binding, modules: preset.Modules, chatSources: preset.ChatSources)), context.AccountChoice,
            temporary, context.FocusedCommunityCode,
            string.Join(",", (modules ?? Enum.GetValues<OverlaySourceModule>()).Distinct().Order()));

    private static bool SameIntent(Scope left, Scope right) =>
        left.Owner == right.Owner && left.Generation == right.Generation && left.Policy == right.Policy &&
        left.Temporary == right.Temporary && left.Modules == right.Modules;

    public Admission? CaptureAdmission(OverlayPresetSources preset, OverlaySourceResolutionContext context,
        OverlaySourceBinding? temporaryChoice = null, IReadOnlyCollection<OverlaySourceModule>? activeModules = null)
    {
        var scope = CreateScope(preset, context, temporaryChoice, activeModules);
        lock (_gate) return _blocked is null && _scope == scope ? _admission : null;
    }

    // A validation-only read. Never admits a new intent, clears a limit, renews
    // authority or serializes the policy. A receipt from a replaced scope fails.
    public OverlayModuleSourcePlan? Inspect(Admission admission, OverlaySourceResolutionContext context)
    {
        lock (_gate)
        {
            if (!ReferenceEquals(_admission, admission) || _blocked is not null ||
                context.OwnerKey != admission.Scope.Owner || context.Generation != admission.Scope.Generation) return null;
            try { return OverlayModuleSourceResolver.Resolve(admission.Preset, context, admission.Scope.Temporary, admission.Modules); }
            catch (OverlaySourceLimitException) { return null; }
        }
    }

    // Call only for accepted, authenticated membership results. Expiry, failed
    // reads and disappearing payloads are not evidence that a source was left.
    public void ConfirmRoom(string owner, long generation, string? currentRoom) =>
        RemoveConfirmed(owner, generation, key => key.StartsWith("Room:", StringComparison.Ordinal) && key != "Room:" + currentRoom);

    public void ConfirmCommunities(string owner, long generation, IReadOnlySet<string> joined) =>
        RemoveConfirmed(owner, generation, key => key.StartsWith("Community:", StringComparison.Ordinal) && !joined.Contains(key[10..]));

    public void RevokeCommunity(string owner, long generation, string code) =>
        RemoveConfirmed(owner, generation, key => key == "Community:" + code);

    private void RemoveConfirmed(string owner, long generation, Predicate<string> removed)
    {
        lock (_gate)
        {
            _evidenceVersion++;
            if (_scope?.Owner != owner || _scope.Generation != generation || _blocked is null) return;
            if (_blocked.RemoveWhere(removed) > 0 && _blocked.Count <= OverlayModuleSourceResolver.MaximumSources)
                _blocked = null;
        }
    }
}
