using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.OfficialFleet;
using Roster = StarBridge.HostRuntime.OfficialFleet.OfficialFleetPublicRosterDecoder;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // Internal source-fact reader only. No Dispatcher registration, identity joins or Bridge row references.
    internal async Task<Roster.Response> ReadOfficialFleetPublicRosterAsync(
        BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        Roster.Query query = ParsePublicRosterQuery(payload); // Reject malformed input before bootstrap or public IO.
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        long started = Stopwatch.GetTimestamp();
        budget.CancelAfter(TimeSpan.FromSeconds(12));
        long generation = Generation;
        FleetPublicSource? descriptor = Volatile.Read(ref _fleetPublicSource);
        void Owner()
        {
            RequireFleetReadOwner(context, generation);
            if (descriptor != Volatile.Read(ref _fleetPublicSource)) throw OfficialFleetReadModel.Invalid();
        }
        void Current()
        {
            token.ThrowIfCancellationRequested();
            budget.Token.ThrowIfCancellationRequested();
            if (Stopwatch.GetElapsedTime(started) >= TimeSpan.FromSeconds(12))
                throw new OperationCanceledException(budget.Token);
            Owner();
        }
        try {
            Current();
            var session = RequireSession(context);
            var bootstrap = await _oauth.LoadBootstrapAsync(session, budget.Token).ConfigureAwait(false);
            Roster.Request request;
            lock (_realtimeGate) {
                Current();
                RequireSameSession(session, bootstrap.ActiveSession);
                var fleet = ProjectOfficialFleet(bootstrap.Snapshot, DateTimeOffset.UtcNow).Fleet;
                if (fleet is null) {
                    _session = bootstrap.ActiveSession;
                    Volatile.Write(ref _fleetPublicSource, null); // Retire other in-flight pages after observed departure.
                    throw OfficialFleetReadModel.Invalid();
                }
                // ProjectOfficialFleet's legacy trimming must not silently repair the new strict source contract.
                var raw = bootstrap.Snapshot.PrimaryFleet ?? bootstrap.Snapshot.Fleets.SingleOrDefault();
                if (raw is null || raw.Sid != fleet.Sid) throw OfficialFleetReadModel.Invalid();
                request = Roster.Bind(query with { SourceRef = fleet.SourceRef }, raw.Sid);
                _session = bootstrap.ActiveSession;
                descriptor = new(context, generation, fleet.SourceRef, raw.Sid);
                Volatile.Write(ref _fleetPublicSource, descriptor);
                if (fleet.SourceRef != query.SourceRef) throw OfficialFleetReadModel.Invalid();
                Current();
            }
            using var data = await _oauth.ReadPublicOrganizationAsync(PublicRosterUrl(request), budget.Token)
                .ConfigureAwait(false);
            Current();
            Roster.Response response = Roster.Decode(data.RootElement, request);
            Current();
            return response;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (AccountBridgeHostException) { throw; }
        catch (Auth.ScmApiAuthenticationException) {
            token.ThrowIfCancellationRequested(); Owner();
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or
            JsonException or InvalidDataException or KeyNotFoundException or FormatException or
            OperationCanceledException or OverflowException or TimeoutException or ArgumentException) {
            token.ThrowIfCancellationRequested(); Owner();
            throw OfficialFleetReadFailures.FromException(error, token);
        }
    }

    private static string PublicRosterUrl(Roster.Request request)
    {
        string url = "roster/page?sid=" + Uri.EscapeDataString(request.Sid)
            + "&query=" + Uri.EscapeDataString(request.Search)
            + "&page=" + request.PageNumber.ToString(CultureInfo.InvariantCulture)
            + "&pageSize=" + request.PageSize.ToString(CultureInfo.InvariantCulture);
        if (request.SnapshotPin is { } pin)
            url += "&generation=" + Uri.EscapeDataString(pin.Generation) + "&revision=" + Uri.EscapeDataString(pin.Revision);
        return url;
    }

    private static Roster.Query ParsePublicRosterQuery(JsonElement payload)
    {
        try {
            if (payload.ValueKind != JsonValueKind.Object) throw OfficialFleetReadModel.Invalid();
            var names = new HashSet<string>(StringComparer.Ordinal);
            string[] required = ["schemaVersion", "sourceRef", "search", "filter", "pageNumber", "pageSize"];
            foreach (JsonProperty field in payload.EnumerateObject())
                if (!names.Add(field.Name) || !required.Contains(field.Name, StringComparer.Ordinal)
                    && field.Name is not ("generation" or "revision")) throw OfficialFleetReadModel.Invalid();
            if (required.Any(name => !names.Contains(name)) || payload.GetProperty("schemaVersion").GetInt32() != 1
                || payload.GetProperty("filter").GetString() != "all") throw OfficialFleetReadModel.Invalid();
            string? generation = OptionalRosterPin(payload, "generation"), revision = OptionalRosterPin(payload, "revision");
            if ((generation is null) != (revision is null)) throw OfficialFleetReadModel.Invalid();
            return Roster.ValidateQuery(new(payload.GetProperty("sourceRef").GetString()!,
                payload.GetProperty("search").GetString()!, payload.GetProperty("pageNumber").GetInt32(),
                payload.GetProperty("pageSize").GetInt32(), generation is null ? null : new(generation, revision!)));
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) {
            throw OfficialFleetReadModel.Invalid();
        }
    }

    private static string? OptionalRosterPin(JsonElement payload, string name) =>
        !payload.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null ? null : value.GetString();
}
