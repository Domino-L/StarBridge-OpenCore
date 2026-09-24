using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

public sealed record HangarAccountIdentity(
    BridgeAccountContext Account, long Generation, ScmGameIdentitySnapshot Identity)
{
    // Call only with the Host's current authenticated session, never browser/Dart input.
    public static HangarAccountIdentity FromSession(string environment, long generation, ScmOAuthSession session) =>
        new(new(environment, session.AuthorityId, session.Subject), generation, session.AuthoritativeGameIdentity);
}

public enum HangarIdentityGuardState
{
    Matched, IdentityRejected, DocumentUnavailable, InvalidObservation, AccountChanged, Cancelled
}

public sealed record HangarIdentityCheck(
    HangarIdentityGuardState State, RsiHangarIdentityAssessment? Identity = null)
{
    public bool CanContinue => State == HangarIdentityGuardState.Matched;
}

/// <summary>
/// One guard per import. Native browser events supply navigation/source, not web JSON.
/// Validates a fresh explicit Handle observation. The reader uses it once before
/// its locked scan; the dispatcher separately confines continuation to that scan.
/// This module does not grant a Java upload scope or a reusable write lease.
/// </summary>
public sealed class HangarIdentityGuard
{
    private readonly object _sync = new();
    private readonly HangarAccountIdentity _startedAs;
    private readonly Func<HangarAccountIdentity?> _currentIdentity;
    private ulong _navigation;
    private Uri? _committedSource;
    private bool _navigationPending;
    private bool _cancelled;
    private bool _accountChanged;

    public HangarIdentityGuard(HangarAccountIdentity startedAs, Func<HangarAccountIdentity?> currentIdentity)
    {
        ArgumentNullException.ThrowIfNull(startedAs);
        ArgumentNullException.ThrowIfNull(currentIdentity);
        if (!startedAs.Account.IsComplete || startedAs.Generation < 0)
            throw new ArgumentException("A current authenticated account is required.", nameof(startedAs));
        _startedAs = startedAs;
        _currentIdentity = currentIdentity;
    }

    // navigation is an adapter-owned increasing document generation, not the
    // browser's opaque NavigationId. Advance it before every new document read.
    public void NavigationStarted(ulong navigation)
    {
        lock (_sync)
        {
            _committedSource = null;
            _navigationPending = navigation > _navigation;
            if (_navigationPending) _navigation = navigation;
        }
    }

    public void NavigationCompleted(ulong navigation, Uri source, bool successful)
    {
        lock (_sync)
        {
            if (!_navigationPending || navigation == 0 || navigation != _navigation) return;
            _navigationPending = false;
            _committedSource = successful && IsHangarDocument(source) ? source : null;
        }
    }

    public void Cancel()
    {
        lock (_sync) { _cancelled = true; _committedSource = null; }
    }

    public HangarIdentityCheck Assess(ulong navigation, Uri nativeSource, string observationJson)
    {
        lock (_sync)
        {
            if (_cancelled) return new(HangarIdentityGuardState.Cancelled);
            var current = _currentIdentity();
            if (_accountChanged || current is null || current.Account != _startedAs.Account ||
                current.Generation != _startedAs.Generation ||
                !string.Equals(current.Identity.CanonicalHandle, _startedAs.Identity.CanonicalHandle, StringComparison.Ordinal))
            {
                _accountChanged = true;
                return new(HangarIdentityGuardState.AccountChanged);
            }
            if (_committedSource is null || navigation != _navigation ||
                !IsHangarDocument(nativeSource) || !SameDocument(nativeSource, _committedSource))
                return new(HangarIdentityGuardState.DocumentUnavailable);

            if (string.IsNullOrEmpty(observationJson) || observationJson.Length > 4096)
                return new(HangarIdentityGuardState.InvalidObservation);
            try
            {
                using var document = JsonDocument.Parse(observationJson, new() { MaxDepth = 4 });
                var root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object)
                    return new(HangarIdentityGuardState.InvalidObservation);
                var fields = root.EnumerateObject().Select(p => p.Name).ToArray();
                if (fields.Length != 4 || fields.Distinct(StringComparer.Ordinal).Count() != 4 ||
                    fields.Any(name => name is not ("schemaVersion" or "sourceKind" or "documentUrl" or "handles")) ||
                    !root.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
                    root.GetProperty("sourceKind").GetString() != "current-account" ||
                    !Uri.TryCreate(root.GetProperty("documentUrl").GetString(), UriKind.Absolute, out var reportedSource) ||
                    !IsHangarDocument(reportedSource) || !SameDocument(reportedSource, nativeSource))
                    return new(HangarIdentityGuardState.InvalidObservation);
                var handles = root.GetProperty("handles");
                if (handles.ValueKind != JsonValueKind.Array || handles.GetArrayLength() > RsiHangarIdentityPolicy.MaximumHandleClaims)
                    return new(HangarIdentityGuardState.InvalidObservation);
                var values = handles.EnumerateArray().Select(value => value.GetString()).ToArray();
                var assessment = RsiHangarIdentityPolicy.Evaluate(current.Identity, values);
                return new(assessment.CanContinue ? HangarIdentityGuardState.Matched : HangarIdentityGuardState.IdentityRejected, assessment);
            }
            catch (Exception exception) when (exception is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
            {
                return new(HangarIdentityGuardState.InvalidObservation);
            }
        }
    }

    public static bool IsHangarDocument(Uri? uri) =>
        uri is { IsAbsoluteUri: true } && uri.IsWellFormedOriginalString() &&
        uri.Scheme == Uri.UriSchemeHttps && uri.Port == 443 &&
        uri.UserInfo.Length == 0 && uri.Fragment.Length == 0 &&
        uri.IdnHost.Equals("robertsspaceindustries.com", StringComparison.OrdinalIgnoreCase) &&
        uri.AbsolutePath is "/account/pledges" or "/en/account/pledges";

    private static bool SameDocument(Uri first, Uri second) =>
        string.Equals(first.AbsoluteUri, second.AbsoluteUri, StringComparison.Ordinal);
}
