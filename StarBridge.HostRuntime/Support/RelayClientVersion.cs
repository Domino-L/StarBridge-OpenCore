using System.Net.Http;
using System.Net.WebSockets;

namespace StarBridge.HostRuntime.Support;

/// <summary>
/// The product version the Japan relay reads on every request (MIGRATION-INTERFACE-073 §1).
/// Missing or malformed means "older than 0.7.3": the relay answers a migrated
/// person with 426 instead of 409 legacy_account_migrated, and never starts an
/// automatic migration. Every HttpClient that talks to the relay applies it once
/// at construction, so no single request can forget it.
/// </summary>
internal static class RelayClientVersion
{
    internal const string HeaderName = "X-StarBridge-Client-Version";

    /// <summary>Four numeric parts from Directory.Build.props, e.g. 0.7.3.0.</summary>
    internal static string Value { get; } = Format(typeof(RelayClientVersion).Assembly.GetName().Version);

    internal static string Format(Version? version) => version is null
        ? "0.0.0.0"
        : string.Join('.', Math.Max(version.Major, 0), Math.Max(version.Minor, 0),
            Math.Max(version.Build, 0), Math.Max(version.Revision, 0));

    internal static HttpClient Apply(HttpClient client)
    {
        ArgumentNullException.ThrowIfNull(client);
        client.DefaultRequestHeaders.Remove(HeaderName);
        client.DefaultRequestHeaders.TryAddWithoutValidation(HeaderName, Value);
        return client;
    }

    /// <summary>
    /// A relay client that never follows redirects (CX-OWNER-ALIAS-073-R #4): a 3xx to
    /// another host must not carry this header, a bearer or a password body there.
    /// Every other relay client already builds its handler this way.
    /// </summary>
    internal static HttpClient NewClient(TimeSpan timeout) =>
        Apply(new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = timeout });

    internal static ClientWebSocket Apply(ClientWebSocket socket)
    {
        ArgumentNullException.ThrowIfNull(socket);
        socket.Options.SetRequestHeader(HeaderName, Value);
        return socket;
    }
}
