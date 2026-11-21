using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

/// <summary>Relay r49 SCM display settings (section=callsign / section=game-id):
/// one shared revision and identity stamp; 409 on stale drafts.</summary>
internal sealed class ScmDisplayRelayFake
{
    internal long Revision;
    // Decision 乙: an SCM account that never set anything shows everywhere.
    internal int Locations = 15;
    internal int Imports;
    internal string? Callsign;
    // Decision 乙 refusals (hiding without a callsign, clearing while hidden), as r49 does.
    internal bool EnforceRuleB = true;
    // Simulates an import that keeps conflicting while the Relay still has no row.
    internal bool ImportConflict;
    // Like r49, the identity stamp covers the callsign: a rename yields a new stamp.
    internal string Stamp => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
        System.Text.Encoding.UTF8.GetBytes("fixture-owner|" + (Callsign ?? "")))).ToLowerInvariant();
    internal string Mode = "ok"; // ok | conflict | down | lost
    internal int Reads, Writes;
    internal bool HoldRead;
    internal TaskCompletionSource ReadEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
    internal TaskCompletionSource ReleaseRead = new(TaskCreationOptions.RunContinuationsAsynchronously);

    internal static bool Handles(HttpRequestMessage request) =>
        request.RequestUri!.AbsolutePath is "/api/auth/session" or "/api/auth/profile";

    internal async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        var query = request.RequestUri!.Query;
        if (request.Method == HttpMethod.Get)
        {
            Check(request.RequestUri.AbsolutePath == "/api/auth/session" && query == "?section=callsign", "display read uses section=callsign");
            Reads++;
            if (HoldRead)
            {
                ReadEntered.TrySetResult();
                await ReleaseRead.Task.WaitAsync(token);
            }
            if (Mode == "down") return new(HttpStatusCode.ServiceUnavailable);
            return Snapshot();
        }
        Check(request.Method == HttpMethod.Post && request.RequestUri.AbsolutePath == "/api/auth/profile" &&
            query is "?section=callsign" or "?section=game-id", "display write uses an exact section");
        Writes++;
        if (Mode == "down") return new(HttpStatusCode.ServiceUnavailable);
        using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
        var root = body.RootElement;
        var import = root.TryGetProperty("importExplicit", out var flag) && flag.ValueKind == JsonValueKind.True;
        Check(root.EnumerateObject().Count() == (import ? 5 : 4) && root.GetProperty("schemaVersion").GetInt32() == 1, "compact display body");
        // The one-time import of an explicit Hong Kong hide is accepted only before any Relay row.
        if (import && (ImportConflict || Revision != 0 || query != "?section=game-id")) return new(HttpStatusCode.Conflict);
        if (import) Imports++;
        if (Mode == "conflict" || root.GetProperty("expectedRevision").GetInt64() != Revision ||
            root.GetProperty("identityStamp").GetString() != Stamp) return new(HttpStatusCode.Conflict);
        if (query == "?section=callsign")
        {
            var next = root.GetProperty("callsign").ValueKind == JsonValueKind.Null ? null : root.GetProperty("callsign").GetString();
            // Like r49 (decision 乙): no clearing the callsign while some place hides the game ID.
            if (EnforceRuleB && next is null && Locations != 15)
                return new(HttpStatusCode.Conflict) { Content = JsonContent.Create(new { error = "callsign.hidden_requires_callsign" }) };
            Callsign = next;
        }
        else
        {
            var next = root.GetProperty("locations").GetInt32();
            // Like r49 (decision 乙): without a callsign nothing new may be hidden (the import is exempt).
            if (EnforceRuleB && !import && Callsign is null && (next & Locations) != Locations)
                return new(HttpStatusCode.Conflict) { Content = JsonContent.Create(new { error = "gameId.callsign_required" }) };
            Locations = next;
        }
        Revision++;
        if (Mode == "lost") throw new HttpRequestException("synthetic lost relay reply");
        return Snapshot();
    }

    private HttpResponseMessage Snapshot() => new(HttpStatusCode.OK)
    {
        Content = JsonContent.Create(new
        {
            schemaVersion = 1, revision = Revision, callsign = Callsign, locations = Locations,
            // Like r49 (decision 乙): configurable only with a callsign (this fake treats any as independent).
            canConfigure = !EnforceRuleB || Callsign is not null, identityStamp = Stamp
        })
    };

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
