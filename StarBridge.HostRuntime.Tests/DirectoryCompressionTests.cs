using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Text;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.PartyRooms;

internal static class DirectoryCompressionTests
{
    private const DecompressionMethods Methods = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli;
    private const string Bearer = "synthetic-compression-test";
    private const string FriendsJson = "{\"friends\":[],\"incomingRequests\":[],\"outgoingRequests\":[],\"blockedUsers\":[],\"refreshedAt\":\"2026-10-17T00:00:00Z\"}";
    private const string CommunitiesJson = "{\"schemaVersion\":1,\"membershipModelVersion\":2,\"directoryVersion\":2,\"totalCount\":0,\"view\":\"discover\",\"query\":\"\",\"next\":null,\"items\":[]}";
    private const string RoomsJson = "{\"serverTime\":\"2026-10-17T00:00:00Z\",\"currentRoomId\":null,\"rooms\":[]}";

    internal static Task Friends() => Verify("friends", FriendsJson, 2 * 1024 * 1024, "friends.data_invalid", "friends.forbidden",
        async (origin, token) => {
            using var reader = new FriendsReader(origin);
            if ((await reader.ReadAsync(Bearer, null, token)).Friends.Length != 0) throw new Exception("Unexpected friends");
        });

    internal static Task Communities() => Verify("communities", CommunitiesJson, 3 * 1024 * 1024, "communities.dataInvalid", "communities.notAllowed",
        async (origin, token) => {
            using var reader = new CommunityClient(origin);
            if ((await reader.ReadAsync(Bearer, new("discover", "", null, null), "synthetic-scope", token)).Items.Length != 0)
                throw new Exception("Unexpected communities");
        });

    internal static Task Rooms() => Verify("rooms", RoomsJson, 2 * 1024 * 1024, "party_rooms.data_invalid", "party_rooms.forbidden",
        async (origin, token) => {
            using var reader = new PartyRoomReader(origin);
            if ((await reader.ReadAsync(Bearer, token)).Rooms.Length != 0) throw new Exception("Unexpected rooms");
        });

    internal static async Task FixtureControl()
    {
        var body = Encoding.UTF8.GetBytes(FriendsJson + new string(' ', 65536));
        foreach (var encoding in new[] { "gzip", "deflate", "br" })
        {
            await using var wire = new Wire(body, encoding);
            using var http = new HttpClient(new HttpClientHandler { AutomaticDecompression = Methods, AllowAutoRedirect = false });
            if (!(await http.GetByteArrayAsync(wire.Origin)).SequenceEqual(body)) throw new Exception("Invalid compressed fixture");
            await wire.Serving;
            if (wire.EncodingSent != encoding || wire.WireBytes >= body.Length) throw new Exception("Fixture did not compress actual HTTP body");
        }
    }

    private static async Task Verify(string scope, string json, int maximum, string invalid, string forbidden, Func<Uri, CancellationToken, Task> read)
    {
        var body = Encoding.UTF8.GetBytes(json + new string(' ', 65536));
        foreach (var encoding in new string?[] { "gzip", "deflate", "br", null })
        {
            await using var wire = new Wire(body, encoding);
            await read(wire.Origin, default);
            await wire.Serving;
            if (wire.Headers.GetValueOrDefault("Authorization") != "Bearer " + Bearer) throw new Exception("Bearer routing changed");
            foreach (var expected in new[] { "gzip", "deflate", "br" })
                if (!wire.Offers(expected)) throw new Exception("Directory did not negotiate " + expected);
            if (wire.EncodingSent != encoding || encoding is not null && wire.WireBytes >= body.Length)
                throw new Exception("Directory did not use the actual smaller encoded response");
            Console.WriteLine($"MEASURE directory={scope} encoding={encoding ?? "identity"} decodedBytes={body.Length} responseBodyBytes={wire.WireBytes}");
        }
        // A tiny wire body must not bypass the pre-existing decoded byte ceiling.
        await using (var oversized = new Wire(Encoding.UTF8.GetBytes(json + new string(' ', maximum + 1)), "gzip"))
            await Reject(() => read(oversized.Origin, default), invalid);
        await using (var denied = new Wire(body, "gzip", 403))
            await Reject(() => read(denied.Origin, default), forbidden);
        await using (var redirected = new Wire(body, "gzip", 302))
        {
            await Reject(() => read(redirected.Origin, default), null);
            if (redirected.RequestCount != 1) throw new Exception("Unexpected redirect follow");
        }
        await using (var held = new Wire(body, "gzip", holdBody: true))
        {
            using var cancellation = new CancellationTokenSource();
            var pending = read(held.Origin, cancellation.Token);
            await held.ResponseStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
            await cancellation.CancelAsync();
            try { await pending.WaitAsync(TimeSpan.FromSeconds(5)); }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { return; }
            throw new Exception("Cancelled compressed body still completed");
        }
    }

    private static async Task Reject(Func<Task> read, string? expected)
    {
        try { await read(); }
        catch (AccountBridgeHostException error) when (expected is null || error.Code == expected) { return; }
        throw new Exception("Expected bounded or denied directory failure: " + expected);
    }

    private sealed class Wire : IAsyncDisposable
    {
        private readonly TcpListener _listener = new(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource _exit = new(TimeSpan.FromSeconds(15));
        internal readonly Dictionary<string, string> Headers = new(StringComparer.OrdinalIgnoreCase);
        internal Uri Origin { get; }
        internal Task Serving { get; }
        internal TaskCompletionSource ResponseStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal string? EncodingSent { get; private set; }
        internal int WireBytes { get; private set; }
        internal int RequestCount { get; private set; }
        internal bool Offers(string encoding) => Headers.GetValueOrDefault("Accept-Encoding", "").Split(',')
            .Any(part => part.Trim().Equals(encoding, StringComparison.OrdinalIgnoreCase));

        internal Wire(byte[] body, string? encoding, int status = 200, bool holdBody = false)
        {
            _listener.Start();
            Origin = new("http://127.0.0.1:" + ((IPEndPoint)_listener.LocalEndpoint).Port);
            Serving = Serve(body, encoding, status, holdBody);
        }

        private async Task Serve(byte[] body, string? encoding, int status, bool holdBody)
        {
            // A second connection, if followed, gets valid data and is observable.
            do
            {
                using var client = await _listener.AcceptTcpClientAsync(_exit.Token);
                using var stream = client.GetStream();
                using var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, leaveOpen: true);
                var first = await reader.ReadLineAsync(_exit.Token) ?? throw new Exception("Missing HTTP request");
                if (!first.StartsWith("GET ", StringComparison.Ordinal)) throw new Exception("Read fixture received a write");
                Headers.Clear();
                var bytes = first.Length;
                while (await reader.ReadLineAsync(_exit.Token) is { Length: > 0 } line)
                {
                    bytes += line.Length;
                    if (bytes > 32768) throw new Exception("Unbounded request headers");
                    var separator = line.IndexOf(':');
                    if (separator < 1) throw new Exception("Invalid request header");
                    Headers[line[..separator]] = line[(separator + 1)..].Trim();
                }
                RequestCount++;
                EncodingSent = encoding is not null && Offers(encoding) ? encoding : null;
                var payload = body;
                if (EncodingSent is not null)
                {
                    using var buffer = new MemoryStream();
                    using (Stream compressor = EncodingSent switch {
                        "gzip" => new GZipStream(buffer, CompressionLevel.Fastest, true),
                        "deflate" => new ZLibStream(buffer, CompressionLevel.Fastest, true),
                        _ => new BrotliStream(buffer, CompressionLevel.Fastest, true)
                    }) await compressor.WriteAsync(body, _exit.Token);
                    payload = buffer.ToArray();
                }
                WireBytes = payload.Length;
                var code = RequestCount == 1 ? status : 200;
                var header = $"HTTP/1.1 {code} Fixture\r\nContent-Type: application/json\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n" +
                    (EncodingSent is null ? "" : $"Content-Encoding: {EncodingSent}\r\n") +
                    (code == 302 ? "Location: /redirect-target\r\n" : "") + "\r\n";
                await stream.WriteAsync(Encoding.ASCII.GetBytes(header), _exit.Token);
                ResponseStarted.TrySetResult();
                if (holdBody) await Task.Delay(Timeout.InfiniteTimeSpan, _exit.Token);
                await stream.WriteAsync(payload, _exit.Token);
            } while (status == 302 && RequestCount < 2);
        }

        public async ValueTask DisposeAsync()
        {
            try { await _exit.CancelAsync(); await Serving; }
            catch (Exception e) when (_exit.IsCancellationRequested && e is OperationCanceledException or SocketException or IOException) { }
            finally { _listener.Stop(); _exit.Dispose(); }
        }
    }
}
