using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

// Explicit auth/review subset. Never a full onboarding, account installation,
// progress, consent or completion capability. The original mode owns cleanup.
public sealed partial class FirstUseOnlineReviewBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.onlineReview.v1";
    public const string RetainedCapability = "onboarding.onlineReview.v2";
    public const string ReauthorizationCapability = "onboarding.onlineReauthorization.v1";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = [Capability, RetainedCapability, ReauthorizationCapability, GameIdentityCapability];
    private const string V2Prefix = "onboarding.onlineReview.v2.";
    public const string ReadRequest = "onboarding.onlineReview.read";
    public const string BeginRequest = "onboarding.onlineReview.begin";
    public const string LoginRequest = "onboarding.onlineReview.login";
    public const string ReviewRequest = "onboarding.onlineReview.review";
    public const string ConfirmRequest = "onboarding.onlineReview.confirm";
    public const string CancelRequest = "onboarding.onlineReview.cancel";
    public static bool Handles(string name) => name is ReadRequest or BeginRequest or LoginRequest or
        ReviewRequest or ConfirmRequest or CancelRequest || name is V2Prefix + "read" or V2Prefix + "begin" or
        V2Prefix + "login" or V2Prefix + "resume" or V2Prefix + "reauthorize" or V2Prefix + "review" or V2Prefix + "confirm" or V2Prefix + "cancel" || IsGameIdentityRequest(name);
    private readonly FirstUseModeRuntime _mode;
    private readonly Func<long> _generation;
    private volatile bool _disposed;
    internal FirstUseOnlineReviewBridgeDispatcher(FirstUseModeRuntime mode, Func<long> generation)
    { _mode = mode; _generation = generation; }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        bool Current() => !_disposed && request.SessionGeneration == _generation();
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (!Current()) return Error(request, "firstUse.context_changed");
            if (IsGameIdentityRequest(request.Name))
                return await DispatchGameIdentityAsync(request, Current, token).ConfigureAwait(false);
            var v2 = request.Name.StartsWith(V2Prefix, StringComparison.Ordinal);
            var action = v2 ? request.Name[V2Prefix.Length..] : request.Name.Replace("onboarding.onlineReview.", "", StringComparison.Ordinal);
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                !Handles(request.Name) || request.Payload.ValueKind != JsonValueKind.Object)
                return Error(request, "firstUse.invalid_request");
            string[] expected = action == "read" ? ["schemaVersion"] : action == "confirm"
                ? ["schemaVersion", "revision", "confirmationKey"] : ["schemaVersion", "revision"];
            var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (fields.Length != expected.Length || fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
                fields.Except(expected, StringComparer.Ordinal).Any() ||
                !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != (v2 ? 2 : 1))
                return Error(request, "firstUse.invalid_request");
            var mode = _mode.Current;
            if (!v2 && _mode.RetainsOnlineReviewSession) return Error(request, "firstUse.resume_required");
            var revision = mode.Revision;
            if (action != "read" && (!request.Payload.GetProperty("revision").TryGetInt64(out revision) ||
                revision < 0 || revision != mode.Revision)) return Error(request, "firstUse.context_changed");
            FirstUseOnlineIdentityObservation? identity = null;
            switch (action)
            {
                case "begin":
                    // Never stage an existing/unknown online owner by inference.
                    if (mode.State != "local" && !(v2 && mode.State == "offline") || !mode.PublicationSuspended)
                        return Error(request, "firstUse.context_changed");
                    mode = mode.State == "offline" ? _mode.RequestResume(revision, Guid.NewGuid().ToString("N"))
                        : _mode.RequestOnline(revision, Guid.NewGuid().ToString("N"));
                    revision = mode.Revision;
                    break;
                case "login":
                    if (_mode.RetainsOnlineReviewSession) return Error(request, "firstUse.resume_required");
                    // The candidate's events/account payload belong to a staged
                    // owner, not the installed pipe's generation or account.
                    if (!await _mode.AuthenticateOnlineCandidateAsync(revision, token).ConfigureAwait(false))
                        return Error(request, "firstUse.sign_in_not_confirmed");
                    if (!Current()) return Error(request, "firstUse.context_changed");
                    identity = await _mode.ReadOnlineIdentityAsync(revision, token).ConfigureAwait(false);
                    break;
                case "resume":
                    if (!v2 || !_mode.RetainsOnlineReviewSession) return Error(request, "firstUse.resume_required");
                    var resumed = await _mode.ResumeOnlineCandidateAsync(revision, token).ConfigureAwait(false);
                    if (!Current()) return Error(request, "firstUse.context_changed");
                    identity = resumed == "observed"
                        ? await _mode.ReadOnlineIdentityAsync(revision, token).ConfigureAwait(false) : new(resumed);
                    break;
                case "review":
                    identity = await _mode.ReadOnlineIdentityAsync(revision, token).ConfigureAwait(false);
                    break;
                case "reauthorize":
                    if (!v2 || !_mode.RetainsOnlineReviewSession) return Error(request, "firstUse.resume_required");
                    var renewed = await _mode.ReauthorizeOnlineCandidateAsync(revision, token).ConfigureAwait(false);
                    if (!Current()) return Error(request, "firstUse.context_changed");
                    identity = renewed == "observed"
                        ? await _mode.ReadOnlineIdentityAsync(revision, token).ConfigureAwait(false) : new(renewed);
                    break;
                case "confirm":
                    var key = request.Payload.GetProperty("confirmationKey");
                    if (key.ValueKind != JsonValueKind.String || !LocalFirstUseValidation.Id(key.GetString()))
                        return Error(request, "firstUse.invalid_request");
                    identity = await _mode.ConfirmOnlineIdentityAsync(revision, key.GetString()!, token).ConfigureAwait(false);
                    break;
                case "cancel":
                    mode = v2 && _mode.HasColdOnlinePending
                        ? await _mode.RecoverColdOnlineAsync(revision, Guid.NewGuid().ToString("N"), token).ConfigureAwait(false)
                        : await _mode.CancelOnlineAsync(revision, Guid.NewGuid().ToString("N"), token).ConfigureAwait(false);
                    revision = mode.Revision;
                    break;
            }
            token.ThrowIfCancellationRequested();
            var current = _mode.Current;
            if (!Current() || current.Revision != revision) return Error(request, "firstUse.context_changed");
            if (action is not ("begin" or "cancel")) mode = current;
            if (action == "cancel" && mode.State == "recoveryRequired") identity = new("recoveryRequired");
            identity ??= _mode.CurrentOnlineIdentity(revision);
            // A second review/source/credential transition may invalidate the
            // just-completed async operation before its wire projection.
            if (identity.State is "reviewRequired" or "confirmedForHandoff" or "accountReviewRequired" or
                "accountConfirmedForHandoff" or "installedReviewRequired" or "boundOnlineIdentity")
            {
                var live = _mode.CurrentOnlineIdentity(revision);
                if (live.State != identity.State || live.ConfirmationKey != identity.ConfirmationKey)
                    return Error(request, "firstUse.context_changed");
                identity = live;
            }
            var display = identity.AccountDisplayName;
            if (display is not null && (display.Length > 128 || string.IsNullOrWhiteSpace(display) || display.Any(char.IsControl)))
                display = null;
            // Dictionary values retain explicit nulls under the pipe's existing
            // ignore-null-property serializer. The strict decoder needs a fixed
            // shape in waiting/error states, not only when a review has Handles.
            var projection = new Dictionary<string, object?> {
                ["schemaVersion"] = v2 ? 2 : 1, ["revision"] = revision, ["modeState"] = mode.State,
                ["identity"] = new Dictionary<string, object?> {
                    ["state"] = identity.State, ["localHandle"] = identity.LocalHandle,
                    ["authoritativeHandle"] = identity.AuthoritativeHandle, ["accountDisplayName"] = display,
                    ["confirmationKey"] = identity.ConfirmationKey } };
            if (v2) projection["retainsSession"] = _mode.RetainsOnlineReviewSession;
            return new(BridgeEnvelope.Response(request, projection, preserveRequestAccountContext: false), []);
        }
        catch (LocalFirstUseException error) { return Error(request, error.Code); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        { return Error(request, "firstUse.invalid_request"); }
        catch { return Error(request, "firstUse.online_review_failed"); }
    }

    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null },
            new(code, "Online identity review could not be confirmed.", true)), []);
    // Borrowed route only. Original mode/candidate owns cancellation and drain.
    public void Dispose() => _disposed = true;
}
