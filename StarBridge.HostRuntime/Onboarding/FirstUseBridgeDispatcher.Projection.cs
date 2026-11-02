using System.Text.Json;

namespace StarBridge.HostRuntime.Onboarding;

public sealed partial class FirstUseBridgeDispatcher
{
    private async Task<View> Capture(CancellationToken token)
    {
        var generation = _mode.ControlGeneration;
        var local = _local.Read();
        var mode = _mode.Current;
        var source = local.Sources.SingleOrDefault(s => s.SourceKey == local.SelectedSourceKey);
        var profile = local.Profiles.SingleOrDefault(p => p.Id == source?.ConfirmedProfileId);
        var evidence = _evidence.Current;
        if (evidence.State != "candidate" && source is { NeedsFreshGameEvidence: false, ConfirmedObservedAt: not null } &&
            profile is not null && local.ActiveProfileId == profile.Id)
            evidence = new("candidate", source.SourceKey, StableKey(source), false, profile.Handle,
                source.ConfirmedObservedAt, "confirmedLocal", false, true);
        var candidate = evidence.State == "candidate" && evidence.Handle is not null;
        var completed = _completed.Read();
        var choice = local.Progress?.Mode;
        var completion = await _completion.ReadAsync(token).ConfigureAwait(false);
        var onlineInstalled = _mode.HasInstalledOnlineForCompletion;
        var matched = onlineInstalled || _mode.HasConfirmedOnlineIdentity(mode.Revision);
        var signedIn = _mode.HasInstalledOnlineAccount || _mode.HasAuthenticatedOnlineCandidate;
        var facts = new Dictionary<string, object?> {
            ["eligibility"] = _startup.Read().Eligibility, ["available"] = !_closed, ["canSave"] = !_closed,
            ["sourceKey"] = source?.SourceKey, ["evidenceKey"] = candidate ? evidence.IdentityConfirmed && source is not null ? StableKey(source) : evidence.EvidenceKey : null,
            ["version"] = source?.Version, ["logReady"] = source is not null,
            ["evidence"] = candidate ? "candidate" : evidence.State switch { "missing" => "missing", "conflict" => "conflict", "unselected" => "unavailable", "checking" or "waiting" => "checking", _ => "failed" },
            ["origin"] = candidate ? evidence.Origin : null, ["handle"] = candidate ? evidence.Handle : null,
            ["observedAt"] = candidate ? evidence.ObservedAt : null, ["scopeChecked"] = evidence.ScopeChecked,
            ["requiresFreshEvidence"] = source?.NeedsFreshGameEvidence == true && evidence.Origin != "freshSession",
            ["localIdentityConfirmed"] = candidate && evidence.IdentityConfirmed,
            ["localSettingsReady"] = completion.State is "ready" or "completed",
            ["signedIn"] = signedIn, ["onlineIdentityMatched"] = signedIn && matched,
            ["onlineChoicesReviewed"] = onlineInstalled, ["activeMode"] = mode.ActiveMode,
            ["publicationSuspended"] = mode.PublicationSuspended,
            ["onlineSetupPending"] = choice == "online" && mode.ActiveMode == "local" && mode.PublicationSuspended
        };
        Dictionary<string, object?>? receipt = completed is not null && profile?.Id == completed.ProfileId &&
            source?.SourceKey == completed.SourceKey && (choice is null || choice == completed.Mode)
            ? Checkpoint("summary", completed.Mode, source.SourceKey, facts["evidenceKey"] as string) : null;
        token.ThrowIfCancellationRequested();
        if (_closed || generation != _mode.ControlGeneration || mode != _mode.Current || local.Revision != _local.Read().Revision)
            throw new LocalFirstUseException("firstUse.context_changed");
        return new(facts, local, completion, receipt, generation);
    }

    private static string StableKey(LocalFirstUseSource source) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(source)));
    private static Dictionary<string, object?> Checkpoint(string step, string? mode, string? source, string? evidence) => new() {
        ["step"] = step, ["mode"] = mode, ["sourceKey"] = source, ["evidenceKey"] = evidence };
    private static Dictionary<string, object?>? ProgressWire(LocalFirstUseProgress? progress, View view) => progress is null ? null :
        Checkpoint(progress.SourceKey is not null && progress.SourceKey != view.Facts["sourceKey"] as string ? "log" : progress.Step,
            progress.Mode, view.Facts["sourceKey"] as string, view.Facts["evidenceKey"] as string);

    private static Dictionary<string, object?> ReadCheckpoint(JsonElement body, View view)
    {
        if (body.ValueKind != JsonValueKind.Object) throw new LocalFirstUseException("firstUse.invalid_request");
        var fields = body.EnumerateObject().Select(p => p.Name).ToArray();
        string[] expected = ["step", "mode", "sourceKey", "evidenceKey"];
        if (fields.Length != 4 || fields.Distinct().Count() != 4 || fields.Except(expected).Any())
            throw new LocalFirstUseException("firstUse.invalid_request");
        string? Text(string name) => body.GetProperty(name).ValueKind == JsonValueKind.Null ? null : body.GetProperty(name).GetString();
        var step = Text("step"); var mode = Text("mode"); var source = Text("sourceKey"); var evidence = Text("evidenceKey");
        if (step is not ("welcome" or "mode" or "log" or "identity" or "local" or "online" or "summary") ||
            mode is not (null or "local" or "online") || step is not ("welcome" or "mode") && mode is null ||
            step == "online" && mode != "online" || source != view.Facts["sourceKey"] as string || evidence != view.Facts["evidenceKey"] as string)
            throw new LocalFirstUseException("firstUse.context_changed");
        return Checkpoint(step, mode, source, evidence);
    }

    private void SaveProgress(Dictionary<string, object?> checkpoint, View view, CancellationToken token)
    {
        var step = (string)checkpoint["step"]!;
        var profile = step is "local" or "online" or "summary" ? view.Local.ActiveProfileId : null;
        var progress = new LocalFirstUseProgress(step, checkpoint["mode"] as string, checkpoint["sourceKey"] as string,
            checkpoint["evidenceKey"] as string, profile);
        _local.SaveProgress(view.Local.Revision, Guid.NewGuid().ToString("N"), progress,
            () => !_closed && !token.IsCancellationRequested && _mode.ControlGeneration == view.Generation);
    }
}
