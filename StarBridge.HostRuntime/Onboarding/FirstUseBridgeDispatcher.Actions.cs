using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

public sealed partial class FirstUseBridgeDispatcher
{
    private async Task Execute(string action, Dictionary<string, object?> checkpoint, View view, CancellationToken token)
    {
        var step = checkpoint["step"] as string;
        switch (action)
        {
            case "applyMode":
                if (step != "mode" || checkpoint["mode"] is not string choice)
                    throw new LocalFirstUseException("firstUse.invalid_request");
                if (choice == "online" && _mode.HasInstalledOnlineAccount)
                {
                    SaveProgress(checkpoint, view, token);
                    break;
                }
                if (_mode.Current.State == "signInRequired" && choice == "local")
                {
                    var cancelled = _mode.HasColdOnlinePending
                        ? await _mode.RecoverColdOnlineAsync(_mode.Current.Revision, Op(), token).ConfigureAwait(false)
                        : await _mode.CancelOnlineAsync(_mode.Current.Revision, Op(), token).ConfigureAwait(false);
                    if (cancelled.State is not ("local" or "offline"))
                        throw new LocalFirstUseException("firstUse.recovery_required");
                }
                await EnsureLocal(token).ConfigureAwait(false);
                if (choice == "online")
                {
                    var current = _mode.Current;
                    if (current.State == "offline") _mode.RequestResume(current.Revision, Op());
                    else _mode.RequestOnline(current.Revision, Op());
                }
                var local = _local.Read();
                _local.SaveProgress(local.Revision, Op(), new("mode", choice, local.SelectedSourceKey,
                    checkpoint["evidenceKey"] as string, null), () => !_closed && !token.IsCancellationRequested && _mode.LocalMode().Active);
                break;
            case "login":
                if (step != "mode" || checkpoint["mode"] as string != "online") throw new LocalFirstUseException("firstUse.invalid_request");
                if (_mode.RetainsOnlineReviewSession) await _mode.ResumeOnlineCandidateAsync(_mode.Current.Revision, token).ConfigureAwait(false);
                else if (!await _mode.AuthenticateOnlineCandidateAsync(_mode.Current.Revision, token).ConfigureAwait(false))
                    throw new LocalFirstUseException("firstUse.sign_in_not_confirmed");
                break;
            case "cancelLogin":
                await _mode.CancelOnlineAsync(_mode.Current.Revision, Op(), token).ConfigureAwait(false);
                break;
            case "selectLog":
                if (step != "log" || !_mode.AllowsLocalIdentitySetup) throw new LocalFirstUseException("firstUse.context_changed");
                var path = await _picker.PickAsync(_locale(), token).ConfigureAwait(false);
                token.ThrowIfCancellationRequested();
                if (_closed || _mode.ControlGeneration != view.Generation || _local.Read().Revision != view.Local.Revision)
                    throw new LocalFirstUseException("firstUse.context_changed");
                if (path is not null)
                {
                    var version = GameLogLocator.ChannelOf(path) ?? throw new LocalFirstUseException("firstUse.source_invalid");
                    _evidence.Select(view.Local.Revision, path, version);
                }
                break;
            case "refresh":
                if (_local.Read().SelectedSourceKey is string selected) _evidence.Refresh(selected, token);
                break;
            case "confirmHandle":
                if (step != "identity" || checkpoint["sourceKey"] is not string source || checkpoint["evidenceKey"] is not string evidence)
                    throw new LocalFirstUseException("firstUse.evidence_required");
                // A cold projection of a persisted association is not an issued
                // live evidence key. Refresh the same source before confirming.
                var currentEvidence = _evidence.Current;
                if (currentEvidence.EvidenceKey != evidence)
                {
                    currentEvidence = _evidence.Refresh(source, token);
                    if (!currentEvidence.IdentityConfirmed) throw new LocalFirstUseException("firstUse.evidence_required");
                }
                _evidence.Confirm(source, currentEvidence.EvidenceKey!);
                var confirmed = _local.Read();
                _local.SetListening(confirmed.Revision, Op(), source, true, () => !_closed && !token.IsCancellationRequested && _mode.AllowsLocalIdentitySetup);
                break;
            case "reviewLocalSettings":
                if (step != "local" || (await _completion.ReadAsync(token).ConfigureAwait(false)).State is not ("ready" or "completed"))
                    throw new LocalFirstUseException("firstUse.device_review_required");
                break;
            case "reviewOnlineChoices":
                if (step == "online" && checkpoint["mode"] as string == "online" && _mode.HasInstalledOnlineForCompletion &&
                    (await _completion.ReadAsync(token).ConfigureAwait(false)).State is "ready" or "completed") break;
                if (step != "online" || checkpoint["mode"] as string != "online" ||
                    (await _completion.ReadAsync(token).ConfigureAwait(false)).State is not ("ready" or "completed") ||
                    !_mode.HasConfirmedOnlineIdentity(_mode.Current.Revision))
                    throw new LocalFirstUseException("firstUse.completion_required");
                await _native.InstallConfirmedOnlineAsync(_mode.Current.Revision, _configure, token).ConfigureAwait(false);
                if (!_mode.HasInstalledOnlineForCompletion) throw new LocalFirstUseException("firstUse.installation_failed");
                break;
            default: throw new LocalFirstUseException("firstUse.invalid_request");
        }
    }

    private async Task EnsureLocal(CancellationToken token)
    {
        if (_mode.LocalMode().Active) return;
        if (_mode.Current is { State: "recoveryRequired" } pending)
        {
            // This is reached only by an explicit applyMode action. Reuse the
            // original retirement/provenance checks; never reset unknown data,
            // infer an exited owner, or substitute a fresh empty mode receipt.
            var recovered = await _mode.RecoverLocalAsync(pending.Revision, Op(), token).ConfigureAwait(false);
            if (recovered.State != "local" || !_mode.LocalMode().Active)
                throw new LocalFirstUseException("firstUse.recovery_required");
            return;
        }
        if (_mode.Current.State != "online") throw new LocalFirstUseException("firstUse.mode_receipt_required");
        var current = await _native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), _native.Generation,
            new { schemaVersion = 1 }), token).ConfigureAwait(false);
        if (current.Response.Status != "ok") throw new LocalFirstUseException("firstUse.mode_receipt_required");
        var state = current.Response.Payload.GetProperty("state").GetString();
        if (state == "signedIn")
            await _mode.ApplyManualOfflineAsync(_mode.Current.Revision, Op(), _native, token).ConfigureAwait(false);
        else if (state == "signedOut")
            await _mode.ApplyLocalAsync(_mode.Current.Revision, Op(), _root.Generation, token).ConfigureAwait(false);
        else throw new LocalFirstUseException("firstUse.mode_receipt_required");
        if (!_mode.LocalMode().Active) throw new LocalFirstUseException("firstUse.mode_receipt_required");
    }
    private static string Op() => Guid.NewGuid().ToString("N");
}
