namespace StarBridge.HostRuntime.Hangar;

/// <summary>
/// Where the explicit local hangar sandbox lives. Two switches are needed:
/// <see cref="SwitchVariable"/>=1 asks for the sandbox and <see cref="RootVariable"/>
/// names the prepared folder holding <c>client-data</c> and <c>client.dpapi</c>.
/// No folder is built in, so release packages and open core carry no developer
/// path. A request without a usable folder leaves the sandbox off and says why.
/// </summary>
public sealed record HangarSandboxLocation
{
    public const string SwitchVariable = "STARBRIDGE_HANGAR_SANDBOX";
    public const string RootVariable = "STARBRIDGE_HANGAR_SANDBOX_ROOT";
    internal const string DiagnosticsFileName = "hangar-sandbox-diagnostics.log";

    private HangarSandboxLocation(string root) => Root = root;

    public string Root { get; }
    public string DataRoot => Path.Combine(Root, "client-data");
    public string Manifest => Path.Combine(Root, "client.dpapi");

    /// <summary>
    /// Null when the sandbox is not requested, or when it is requested without a
    /// usable folder; <paramref name="refusal"/> is set only in the second case and
    /// never contains the folder itself.
    /// </summary>
    public static HangarSandboxLocation? Resolve(Func<string, string?> read, out string? refusal)
    {
        refusal = null;
        if (read(SwitchVariable) != "1") return null;
        var raw = read(RootVariable)?.Trim();
        if (string.IsNullOrEmpty(raw))
        {
            refusal = RootVariable + " is not set";
            return null;
        }
        if (!Path.IsPathFullyQualified(raw))
        {
            refusal = RootVariable + " is not an absolute path";
            return null;
        }
        // HostDataRoot.UsePreparedRoot expands %VARIABLES%; the checked folder and
        // the data root must be the same folder, so refuse anything it could expand.
        if (raw.Contains('%'))
        {
            refusal = RootVariable + " must not contain %";
            return null;
        }
        HangarSandboxLocation location;
        try
        {
            location = new(Path.TrimEndingDirectorySeparator(Path.GetFullPath(raw)));
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or PathTooLongException)
        {
            refusal = RootVariable + " is not a valid path";
            return null;
        }
        if (!Directory.Exists(location.DataRoot))
        {
            refusal = "client-data is missing under " + RootVariable;
            return null;
        }
        if (!File.Exists(location.Manifest))
        {
            refusal = "client.dpapi is missing under " + RootVariable;
            return null;
        }
        return location;
    }

    /// <summary>One line to stderr and to the bootstrap folder; never throws.</summary>
    public static void ReportRefusal(string bootstrapDirectory, string refusal)
    {
        var line = DateTimeOffset.UtcNow.ToString("O") + " hangar sandbox off: " + refusal;
        // Diagnostics must never stop the Host from starting.
        try { Console.Error.WriteLine(line); } catch (Exception) { }
        try
        {
            Directory.CreateDirectory(bootstrapDirectory);
            File.AppendAllText(Path.Combine(bootstrapDirectory, DiagnosticsFileName), line + Environment.NewLine);
        }
        catch (Exception) { }
    }
}
