using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Account;

internal static class CommunityReadEfficiencyTests
{
    internal static async Task Verify()
    {
        await DirectoryOwnership();
        await ParallelMedia();
        await CancellationAndRetry();
        await IsolationAndDisposal();
        await FailureAndIdentity();
    }

    private static async Task ParallelMedia()
    {
        using var handler = new Fixture();
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var directory = await client.ReadWpfS2Async("fixture-token", new("mine", "", null, null), "owner:1", "self", default);
        var target = directory.Items[0].TargetRef;
        var page = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("fixture-token",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), "owner:1", default));
        var members = page.GetProperty("members").EnumerateArray().Select(row => row.GetProperty("memberRef").GetString()).ToArray();
        handler.Memberships = handler.Fleets = 0;
        handler.Gate = new(TaskCreationOptions.RunContinuationsAsynchronously);
        Task<object> Read(int i) => client.ReadMediaAsync("fixture-token", JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, targetRef = target, kind = "avatar", memberRef = members[i], offset = 0 }), "owner:1", default);
        var reads = Enumerable.Range(0, 3).Select(Read).ToArray();
        try { Check(handler.Memberships == 1, $"Three simultaneous media reads started {handler.Memberships} duplicate membership requests (expected 1)."); }
        finally { handler.Gate.SetResult(); await Task.WhenAll(reads); }
        Check(handler.Fleets == 1, "The same in-flight roster should be fetched once for the three images.");
        handler.Gate = null;
        await Read(0);
        Check(handler.Memberships == 2 && handler.Fleets == 2, "A later read must revalidate; completed authorization responses are not cached.");
        handler.Revoked = true;
        await Rejected(Read(0));
        Check(handler.Memberships == 3 && handler.Fleets == 2, "Revoked membership must deny subsequent media without reusing the previous roster.");
        Console.WriteLine("PASS simultaneous media: 6 HTTP reads -> 2; later read still revalidates");
    }

    private static async Task DirectoryOwnership()
    {
        using var handler = new Fixture { ResolveOwner = true };
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var page = await client.ReadWpfS2Async("fixture-token", new("mine", "", null, null), "owner:1", "self", default);
        Check(page.Items.Length == 3, "All existing memberships remain visible.");
        Check(handler.Sessions == 1, $"One organization listing repeated the same session identity lookup {handler.Sessions} times (expected 1).");
        Check(page.Items.All(item => item.Relationship == "owner"), "Ownership still uses the verified session identity.");
        Console.WriteLine("PASS directory ownership: 3 identity lookups -> 1");
    }

    private static Task<CommunityPage> Directory(CommunityClient client, string bearer = "fixture-token", string scope = "owner:1", CancellationToken token = default) =>
        client.ReadWpfS2Async(bearer, new("mine", "", null, null), scope, "self", token);

    private static async Task CancellationAndRetry()
    {
        using var handler = new Fixture { Gate = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        using var firstCancellation = new CancellationTokenSource();
        var first = Directory(client, token: firstCancellation.Token);
        var second = Directory(client);
        firstCancellation.Cancel();
        await Canceled(first);
        Check(!second.IsCompleted && handler.Memberships == 1, "Canceling one page must not cancel another reader of the same response.");
        handler.Gate.SetResult();
        Check((await second).Items.Length == 3, "The remaining reader must finish normally.");

        handler.Gate = new(TaskCreationOptions.RunContinuationsAsynchronously);
        using var bothCancellation = new CancellationTokenSource();
        var third = Directory(client, token: bothCancellation.Token);
        var fourth = Directory(client, token: bothCancellation.Token);
        bothCancellation.Cancel();
        await Canceled(third); await Canceled(fourth);
        await handler.TransportCanceled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        handler.Gate = null;
        Check((await Directory(client)).Items.Length == 3 && handler.Memberships == 3,
            "The last cancellation must stop the transport and a later read must start fresh.");
        Console.WriteLine("PASS independent cancellation, last-reader transport cancellation and retry");
    }

    private static async Task IsolationAndDisposal()
    {
        using var handler = new Fixture { Gate = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var reads = new[] { Directory(client), Directory(client, scope: "owner:2"), Directory(client, bearer: "changed-token") };
        try { Check(handler.Memberships == 3, "Account generations and changed credentials must never share responses."); }
        finally { handler.Gate.SetResult(); await Task.WhenAll(reads); }
        handler.Gate = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = Directory(client);
        client.Dispose();
        await Canceled(pending);
        Console.WriteLine("PASS generation/credential isolation and disposal cancellation");
    }

    private static async Task FailureAndIdentity()
    {
        using var handler = new Fixture { Gate = new(TaskCreationOptions.RunContinuationsAsynchronously), Denied = true };
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var first = Directory(client); var second = Directory(client);
        handler.Gate.SetResult();
        await Rejected(first); await Rejected(second);
        Check(handler.Memberships == 1, "An overlapping failure should not multiply requests.");
        handler.Gate = null; handler.Denied = false;
        Check((await Directory(client)).Items.Length == 3 && handler.Memberships == 2, "Failures must not poison subsequent reads.");
        handler.ResolveOwner = true; handler.MismatchedIdentity = true;
        var unknown = await Directory(client);
        Check(handler.Sessions == 1 && unknown.Items.All(item => item.Relationship != "owner" && item.Actions.Length == 0),
            "A mismatched session cannot grant ownership or leave permission through the reused lookup.");
        handler.MismatchedIdentity = false;
        var owner = await Directory(client);
        Check(handler.Sessions == 2 && owner.Items.All(item => item.Relationship == "owner"), "A later operation must read identity again.");
        Console.WriteLine("PASS failed-read retry, verified identity and operation-local identity lifetime");
    }

    private static async Task Canceled(Task task)
    {
        try { await task; } catch (OperationCanceledException) { return; }
        throw new InvalidOperationException("Expected cancellation.");
    }

    private static async Task Rejected(Task task)
    {
        try { await task; } catch (AccountBridgeHostException) { return; }
        throw new InvalidOperationException("Expected access rejection.");
    }

    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Fixture : HttpMessageHandler
    {
        internal int Memberships, Fleets, Sessions;
        internal bool ResolveOwner;
        internal bool Revoked, Denied, MismatchedIdentity;
        internal TaskCompletionSource? Gate;
        internal readonly TaskCompletionSource TransportCanceled = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            object body;
            switch (request.RequestUri!.AbsolutePath)
            {
                case "/api/fleets/membership":
                    Interlocked.Increment(ref Memberships);
                    if (Gate is { } gate)
                    {
                        try { await gate.Task.WaitAsync(token); }
                        catch (OperationCanceledException) { TransportCanceled.TrySetResult(); throw; }
                    }
                    if (Denied) return new(HttpStatusCode.Forbidden);
                    body = new { fleetCode = Revoked ? "" : "A", fleetCodes = Revoked ? Array.Empty<string>() : new[] { "A", "B", "C" } }; break;
                case "/api/fleets":
                    Interlocked.Increment(ref Fleets);
                    body = new[] { Fleet("A"), Fleet("B"), Fleet("C") }; break;
                case "/api/auth/session":
                    Interlocked.Increment(ref Sessions);
                    body = new { accountId = MismatchedIdentity ? "another-account" : "self", userName = "owner-name" }; break;
                default: return new(HttpStatusCode.NotFound);
            }
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
        }
        private object Fleet(string code) => new {
            code, name = code, totalMembers = 3, ownerAccount = ResolveOwner ? "owner-name" : "self",
            members = Enumerable.Range(0, 3).Select(i => new {
                accountId = i == 0 ? "self" : "member-" + i, gameName = "", callsign = "Member " + i,
                roleTitle = "", online = true, liveStatus = "AppOnline", avatarImageData = Pixel
            }).ToArray()
        };
        private const string Pixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=";
    }
}
