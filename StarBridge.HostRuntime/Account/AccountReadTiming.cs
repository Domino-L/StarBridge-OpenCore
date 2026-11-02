using System.Diagnostics;
using System.Globalization;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal enum AccountReadPhase { DispatchWait, DispatchWork, Restore, LocalOwner, Participation, Projection }
internal enum MemberReadCheckpoint { None, OwnerFence, Bootstrap, RegisteredPage, G1Read, G1Deadline, Relay, Materialize }

// Opt-in evidence under the existing session switch or the narrower member-read switch.
// No payload, owner, URI, credential, Bridge ID or exception text is accepted.
#if STARBRIDGE_SESSION_PROBE || STARBRIDGE_MEMBER_READ_PROBE
internal sealed class AccountReadTiming : IDisposable
{
    private static readonly AsyncLocal<AccountReadTiming?> Active = new();
    private static long _sequence;
    private readonly AccountReadTiming? _previous;
    private readonly long _span = Interlocked.Increment(ref _sequence);
    private readonly string _operation;
    private readonly string? _command;
    private readonly string _schema;
    private string _code = "pending";
    private MemberReadCheckpoint _checkpoint;
    private string _g1 = "none";
    private int _disposed;

    private AccountReadTiming(string name, int schema)
    {
        _previous = Active.Value;
        _command = Command(name);
        _schema = schema switch { 1 => "1", 2 => "2", _ => "invalid" };
        _operation = name switch
        {
            AccountBridgeRequestNames.GetOfficialFleetMembers or AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers => "official-fleet",
            AccountBridgeRequestNames.GetCurrent => "current",
            AccountBridgeRequestNames.ReadCommunities => "communities",
            AccountBridgeRequestNames.ReadFriends => "friends",
            AccountBridgeRequestNames.GetPersonalProfile => "profile",
            AccountBridgeRequestNames.GetCompatibilityState => "compatibility",
            AccountBridgeRequestNames.Login => "login",
            AccountBridgeRequestNames.Logout => "logout",
            _ => "other"
        };
        Active.Value = this;
    }

    internal static AccountReadTiming? Begin(string name, int schema = 0) => new(name, schema);

    private static string? Command(string? name) => name switch
    {
        AccountBridgeRequestNames.GetOfficialFleetMembers => "officialFleet.getMembers",
        AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers => "officialFleet.getRuntimeMembers",
        _ => null
    };

    // A last reached checkpoint, not an exception cause or proof of an HTTP send.
    // No clock, new event or business value is collected here.
    [Conditional("STARBRIDGE_SESSION_PROBE")]
    [Conditional("STARBRIDGE_MEMBER_READ_PROBE")]
    internal static void Checkpoint(MemberReadCheckpoint checkpoint)
    {
        if (Active.Value is not { } active || active._command is null || Volatile.Read(ref active._disposed) != 0) return;
        if (checkpoint is MemberReadCheckpoint.None or MemberReadCheckpoint.OwnerFence or MemberReadCheckpoint.Bootstrap or
            MemberReadCheckpoint.RegisteredPage or MemberReadCheckpoint.G1Read or MemberReadCheckpoint.G1Deadline or
            MemberReadCheckpoint.Relay or MemberReadCheckpoint.Materialize) active._checkpoint = checkpoint;
    }

    // Fixed G1 failure class only: the HTTP status family or a local category,
    // never exception text, URI, payload or identifiers. Identity reads still fail closed.
    [Conditional("STARBRIDGE_SESSION_PROBE")]
    [Conditional("STARBRIDGE_MEMBER_READ_PROBE")]
    internal static void G1Failure(Exception error)
    {
        if (Active.Value is not { } active || active._command is null || Volatile.Read(ref active._disposed) != 0) return;
        active._g1 = error switch
        {
            ScmApiAuthenticationException => "status-401",
            ScmApiForbiddenException => "status-403",
            ScmApiRateLimitException => "status-429",
            ScmApiUnavailableException => "status-5xx",
            HttpRequestException { StatusCode: System.Net.HttpStatusCode.BadRequest } => "status-400",
            HttpRequestException { StatusCode: System.Net.HttpStatusCode.NotFound } => "status-404",
            HttpRequestException { StatusCode: not null } => "status-other",
            HttpRequestException or IOException => "transport",
            OperationCanceledException or TimeoutException => "timeout",
            AccountBridgeHostException { Code: OfficialFleet.OfficialFleetMemberIdentity.Unavailable } or
                System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException or ArgumentException => "contract",
            AccountBridgeHostException => "host-other",
            _ => "other"
        };
    }

    [Conditional("STARBRIDGE_SESSION_PROBE")]
    [Conditional("STARBRIDGE_MEMBER_READ_PROBE")]
    internal static void Response(string? name, string? status, string? code)
    {
        if (Active.Value is not { } active || Volatile.Read(ref active._disposed) != 0 ||
            Command(name) is not { } command || active._command != command) return;
        active._code = status switch
        {
            "ok" when code is null => "none",
            "cancelled" when code == "bridge.cancelled" => "bridge.cancelled",
            "error" => code switch
            {
                "bridge.host_error" => "bridge.host_error",
                "bridge.protocol_incompatible" => "bridge.protocol_incompatible",
                "bridge.invalid_envelope" => "bridge.invalid_envelope",
                "bridge.account_context_required" => "bridge.account_context_required",
                "bridge.stale_generation" => "bridge.stale_generation",
                "bridge.timeout" => "bridge.timeout",
                "bridge.disconnected" => "bridge.disconnected",
                "bridge.backpressure" => "bridge.backpressure",
                "bridge.capability_unavailable" => "bridge.capability_unavailable",
                "account.reauthorization_required" => "account.reauthorization_required",
                "account.operation_in_progress" => "account.operation_in_progress",
                "official_fleet.read_unavailable" => "official_fleet.read_unavailable",
                "official_fleet.read_transient" => "official_fleet.read_transient",
                "official_fleet.read_forbidden" => "official_fleet.read_forbidden",
                "official_fleet.data_invalid" => "official_fleet.data_invalid",
                "official_fleet.identity_unavailable" => "official_fleet.identity_unavailable",
                "official_fleet.runtime_unavailable" => "official_fleet.runtime_unavailable",
                "privacy_publication.identity_unavailable" => "privacy_publication.identity_unavailable",
                "privacy_publication.forbidden" => "privacy_publication.forbidden",
                "privacy_publication.identity_required" => "privacy_publication.identity_required",
                "privacy_publication.route_retired" => "privacy_publication.route_retired",
                "privacy_publication.temporarily_unavailable" => "privacy_publication.temporarily_unavailable",
                "privacy_publication.unavailable" => "privacy_publication.unavailable",
                "privacy_publication.response_invalid" => "privacy_publication.response_invalid",
                _ => "other"
            },
            _ => "other"
        };
    }
    internal static Measurement? Measure(AccountReadPhase phase) =>
        Active.Value is { } active && Volatile.Read(ref active._disposed) == 0 ? new(active, phase) : null;

    public void Dispose()
    {
        Interlocked.Exchange(ref _disposed, 1);
        if (ReferenceEquals(Active.Value, this)) Active.Value = _previous;
    }

    private void Record(AccountReadPhase phase, string state, long elapsedUs)
    {
        if (Volatile.Read(ref _disposed) != 0) return;
#if STARBRIDGE_MEMBER_READ_PROBE && !STARBRIDGE_SESSION_PROBE
        if (_command is null) return;
#endif
        var label = phase switch
        {
            AccountReadPhase.DispatchWait => "dispatch-wait",
            AccountReadPhase.DispatchWork => "dispatch-work",
            AccountReadPhase.Restore => "restore",
            AccountReadPhase.LocalOwner => "local-owner",
            AccountReadPhase.Participation => "participation",
            _ => "projection"
        };
        var detail = string.Create(CultureInfo.InvariantCulture,
            $"[DEBUG-account-wait-20261017] pid={Environment.ProcessId} span={_span} operation={_operation} phase={label} event={state} elapsedUs={Math.Max(0, elapsedUs)}");
        if (_command is not null)
        {
            var checkpoint = _checkpoint switch
            {
                MemberReadCheckpoint.OwnerFence => "owner-fence",
                MemberReadCheckpoint.Bootstrap => "bootstrap",
                MemberReadCheckpoint.RegisteredPage => "registered-page",
                MemberReadCheckpoint.G1Read => "g1-read",
                MemberReadCheckpoint.G1Deadline => "g1-deadline",
                MemberReadCheckpoint.Relay => "relay",
                MemberReadCheckpoint.Materialize => "materialize",
                _ => "none"
            };
            detail += $" command={_command} schema={_schema} code={_code} checkpoint={checkpoint} g1={_g1}";
        }
        ScmAuthDiagnostics.Write("account-wait", "account-wait", "observation", detail);
    }

    internal sealed class Measurement : IDisposable
    {
        private readonly AccountReadTiming _owner;
        private readonly AccountReadPhase _phase;
        private readonly long _started;
        private bool _returned, _disposed;
        internal Measurement(AccountReadTiming owner, AccountReadPhase phase)
        {
            _owner = owner;
            _phase = phase;
            owner.Record(phase, "start", 0);
            _started = Stopwatch.GetTimestamp();
        }
        internal void Returned() => _returned = true;
        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            var elapsed = Stopwatch.GetElapsedTime(_started);
            _owner.Record(_phase, _returned ? "returned" : "interrupted", elapsed.Ticks / 10);
        }
    }
}
#else
// No AsyncLocal, clocks or log writes in ordinary builds.
internal sealed class AccountReadTiming : IDisposable
{
    internal static AccountReadTiming? Begin(string name) => null;
    [Conditional("STARBRIDGE_SESSION_PROBE")]
    [Conditional("STARBRIDGE_MEMBER_READ_PROBE")]
    internal static void Checkpoint(MemberReadCheckpoint checkpoint) { }
    [Conditional("STARBRIDGE_SESSION_PROBE")]
    [Conditional("STARBRIDGE_MEMBER_READ_PROBE")]
    internal static void G1Failure(Exception error) { }
    [Conditional("STARBRIDGE_SESSION_PROBE")]
    [Conditional("STARBRIDGE_MEMBER_READ_PROBE")]
    internal static void Response(string? name, string? status, string? code) { }
    internal static Measurement? Measure(AccountReadPhase phase) => null;
    public void Dispose() { }
    internal sealed class Measurement : IDisposable
    {
        internal void Returned() { }
        public void Dispose() { }
    }
}
#endif
