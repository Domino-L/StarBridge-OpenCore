using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // A request-local pending projection, never a reusable permission or identity cache.
    // BridgePayload.From invokes this converter after the caller's extra Host IO and
    // freezes the result as JsonElement. Later Encode/socket work is outside this seam.
    [JsonConverter(typeof(OfficialAuthorProjectionConverter))]
    private sealed class OfficialAuthorProjection(
        IReadOnlyDictionary<string, OfficialAuthorObservation> observations, TimeProvider clock,
        Func<IReadOnlySet<string>, JsonNode> build, Action current, CancellationToken token, long operationStarted, Func<bool> enabled, bool preserveLapsedVisible)
    {
        internal readonly IReadOnlyDictionary<string, OfficialAuthorObservation> Observations = observations;
        internal readonly TimeProvider Clock = clock;
        internal readonly Func<bool> Enabled = enabled;
        internal readonly bool PreserveLapsedVisible = preserveLapsedVisible;
        internal readonly Func<IReadOnlySet<string>, JsonNode> Build = build;
        internal void ValidatePublication()
        {
            token.ThrowIfCancellationRequested();
            // The IO CTS may already be disposed by the async caller. Never rely on
            // its CancelAfter timer still running to enforce this original deadline.
            if (System.Diagnostics.Stopwatch.GetElapsedTime(operationStarted) >= TimeSpan.FromSeconds(12)) throw new OperationCanceledException("Official communication read budget expired", token);
            current();
        }
    }
    private sealed class OfficialAuthorProjectionConverter : JsonConverter<OfficialAuthorProjection>
    {
        public OfficialAuthorProjectionConverter() { }
        public override OfficialAuthorProjection Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => throw new NotSupportedException();
        public override void Write(Utf8JsonWriter writer, OfficialAuthorProjection value, JsonSerializerOptions options)
        {
            var retired = new HashSet<string>(StringComparer.Ordinal);
            for (int pass = 0; pass <= value.Observations.Count; pass++)
            {
                value.ValidatePublication();
                if (!value.Enabled()) foreach (var id in value.Observations.Keys) retired.Add(id);
                var bytes = JsonSerializer.SerializeToUtf8Bytes(value.Build(retired), options);
                value.ValidatePublication();
                var now = value.Clock.GetUtcNow();
                var expired = value.Observations.Where(pair => (!value.Enabled() || !value.PreserveLapsedVisible && pair.Value.State == "visible" && !pair.Value.Current(now)) && !retired.Contains(pair.Key)).Select(pair => pair.Key).ToArray();
                if (expired.Length == 0) { writer.WriteRawValue(bytes); return; }
                foreach (var id in expired) retired.Add(id); // Each repeat retires at least one row; no new IO or global atomic retry.
            }
            throw new AccountBridgeHostException("communities.unavailable");
        }
    }
    private object OfficialAuthorProjectionResult(IReadOnlyDictionary<string, OfficialAuthorObservation> observations,
        Func<IReadOnlySet<string>, JsonNode> build, Action current, CancellationToken token, long operationStarted, string targetRef, bool preview = false, bool preserveLapsedVisible = false) =>
        new OfficialAuthorProjection(observations, _targetClock, build, current, token, operationStarted,
            () => _targets.TryGetValue(targetRef, out var target) && target.OfficialFleet &&
                (target.AuthorIdentitySchemaVersion == 1 || preview && target.PreviewAuthorsAvailable), preserveLapsedVisible);
}
