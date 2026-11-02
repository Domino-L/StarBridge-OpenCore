using System.Net;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;

internal static partial class SharingReviewRegressionTests
{
    private static async Task AllWriterAdmissions()
    {
        foreach (var route in new[] { "ordinary", "community", "official", "officialConsent" })
        foreach (var operation in new[] { "disable", "revoke", "stop", "invisible" })
        {
            using var f = new Fixture();
            using var handler = new AdmissionHandler(route);
            using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
            var settings = route == "ordinary" ? f.Settings : f.Settings with {
                Fleet = new(PlayerSharedStateFields.None, false, false, []),
                Communities = route == "community" ? [new("FIXTURE", AdmissionHandler.Joined,
                    PlayerSharedStateFields.Presence, false, true, [])] : [],
                OfficialFleet = route.StartsWith("official", StringComparison.Ordinal) ? handler.Choice : null
            };
            f.Store.Save(f.Owner, 1, Guid.NewGuid().ToString("N"), settings, () => true);
            f.Input = f.Input with { AppPresenceConfirmed = true };
            var visibility = PlayerPresenceVisibilityMode.Online;
            var admitted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            using var releaseCheck = new ManualResetEventSlim();
            var checks = 0;
            using var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
                writer.SendAsync("synthetic-only", body, ct, () => {
                    input.RequirePositiveAdmission?.Invoke();
                    if (body.GetProperty("online").GetBoolean() && Interlocked.Increment(ref checks) == 1)
                    { admitted.TrySetResult(); releaseCheck.Wait(ct); }
                }, allowOfficialPositive: true, admission: input.PositiveAdmission), startTimer: false, visibility: () => visibility);
            var sending = Task.Run(() => p.ApplyAsync(f.Owner, 1, 2, default));
            await admitted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var closing = Task.Run(async () => {
                started.TrySetResult();
                switch (operation)
                {
                    case "disable":
                        f.Store.Save(f.Owner, 2, Guid.NewGuid().ToString("N"), settings with { PublicationEnabled = false }, () => true);
                        await p.StopAsync(default, explicitRequest: true); break;
                    case "revoke":
                        f.Store.SetPublicationConsent(f.Owner, 2, false, () => true);
                        await p.StopAsync(default, explicitRequest: true); break;
                    case "stop": await p.StopAsync(default, explicitRequest: true); break;
                    case "invisible":
                        await p.ChangeVisibilityAsync(f.Owner, 1, _ => {
                            visibility = PlayerPresenceVisibilityMode.Invisible; return Task.CompletedTask;
                        }, default); break;
                }
            });
            bool waitedBeforeSend, waitedForResponse;
            try
            {
                await started.Task;
                waitedBeforeSend = await Task.WhenAny(closing, Task.Delay(80)) != closing;
                releaseCheck.Set();
                await handler.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
                waitedForResponse = await Task.WhenAny(closing, Task.Delay(80)) != closing;
            }
            finally { releaseCheck.Set(); handler.Release.TrySetResult(); }
            await Task.WhenAll(sending, closing).WaitAsync(TimeSpan.FromSeconds(4));
            Check(waitedBeforeSend && waitedForResponse, route + "/" + operation + " close escaped admission/HTTP boundary");
            Check(handler.Clears > 0, route + "/" + operation + " must immediately clear before close returns");
            var positives = handler.PositiveWrites;
            await p.TickAsync(); p.Invalidate(); await p.TickAsync();
            Check(handler.PositiveWrites == positives, route + "/" + operation + " published after close returned");
            Console.WriteLine("PASS M04c admission " + route + "/" + operation);
        }
    }

    private sealed class AdmissionHandler(string route) : HttpMessageHandler
    {
        internal static readonly DateTimeOffset Joined = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        internal readonly OfficialFleetRealtimeChoice Choice = new(
            new("fixture", 1, "FIXTURE", "scm-observed-membership-row-v1:1"),
            PlayerSharedStateFields.Presence, "initial", "11111111111111111111111111111111");
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int PositiveWrites, Clears;
        private OfficialRealtimeConsentWire? _consent;
        private bool _initialized;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (!_initialized)
            {
                _initialized = true;
                if (route == "official") _consent = Consent(Choice);
            }
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Get)
                return path switch {
                    "/api/fleets/membership" => Reply(new { fleetCode = (string?)null }),
                    "/api/privacy/community-scopes" => Reply(new { schemaVersion = 2, primaryFleetCode = "FIXTURE",
                        communities = new[] { new { code = "FIXTURE", name = "Fixture", joinedAt = Joined } } }),
                    "/api/official-fleets/realtime/consent" => Reply(new { schemaVersion = 4, consent = _consent }),
                    _ => throw new Exception("Unexpected in-memory GET")
                };
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
            var root = body.RootElement;
            if (request.Method == HttpMethod.Put)
            {
                await Hold(ct);
                _consent = Consent(root.GetProperty("choice").Deserialize<OfficialFleetRealtimeChoice>(LocalPrivacyStore.Json)!);
                return Reply(new { schemaVersion = 4, consent = _consent });
            }
            var state = root.TryGetProperty("state", out var scoped) ? scoped : root;
            if (state.GetProperty("online").GetBoolean()) await Hold(ct);
            else Clears++;
            if (route.StartsWith("official", StringComparison.Ordinal))
                return Reply(new { schemaVersion = 4, state, communities = root.GetProperty("communities"),
                    officialAudience = new { withdrawOnly = !state.GetProperty("online").GetBoolean(),
                        consentRevision = root.GetProperty("consentRevision").GetString(), target = Choice.Target } }, "4");
            return route == "community" ? Reply(root, "3") : Reply(root, "1");
        }
        private async Task Hold(CancellationToken ct)
        {
            Interlocked.Increment(ref PositiveWrites);
            Entered.TrySetResult();
            await Release.Task.WaitAsync(ct);
        }
        private static OfficialRealtimeConsentWire Consent(OfficialFleetRealtimeChoice choice) =>
            new("fixture", choice.Target, choice.Fields, "22222222222222222222222222222222", choice.OperationId);
        private static HttpResponseMessage Reply(object body, string? version = null)
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(JsonSerializer.Serialize(body, LocalPrivacyStore.Json)) };
            if (version is not null) response.Headers.Add("X-StarBridge-Realtime-Version", version);
            return response;
        }
    }
}
