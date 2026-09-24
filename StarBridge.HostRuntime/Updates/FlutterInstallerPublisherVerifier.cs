using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Read-only Windows Authenticode check, matching the established online
/// installer publisher/timestamp policy. Never runs the downloaded executable.</summary>
internal static class FlutterInstallerPublisherVerifier
{
    internal static Task VerifyAsync(string file, string version, CancellationToken cancellation) =>
        VerifyCoreAsync(file, version, false, cancellation);

    internal static Task VerifyInstalledBinaryAsync(string file, string version, CancellationToken cancellation) =>
        VerifyCoreAsync(file, version, true, cancellation);

    private static async Task VerifyCoreAsync(string file, string version, bool installedBinary, CancellationToken cancellation)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var expected = ApplicationUpdateVersion.Parse(version);
        if (!Path.IsPathFullyQualified(file)) throw new InvalidDataException();
        var powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe");
        // File and version are input data, never interpolated shell expressions.
        const string script = """
            $ErrorActionPreference = 'Stop'
            $ProgressPreference = 'SilentlyContinue'
            try {
                Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
                $request = [Console]::In.ReadToEnd() | ConvertFrom-Json
                $signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $request.file
                if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate -or
                    $signature.SignerCertificate.Subject -cne 'CN=ruiyang lyu, O=ruiyang lyu, L=Saskatoon, S=sk, C=CA') { exit 10 }
                [Console]::Out.Write('verified')
                exit 0
            } catch { exit 12 }
            """;
        var start = new ProcessStartInfo(powershell)
        {
            UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        foreach (var argument in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand",
            Convert.ToBase64String(Encoding.Unicode.GetBytes(script)) }) start.ArgumentList.Add(argument);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(45));
        cancellation.ThrowIfCancellationRequested();
        using var process = Process.Start(start) ?? throw new IOException("Publisher verification unavailable.");
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        try
        {
            await process.StandardInput.WriteAsync(JsonSerializer.Serialize(new { file }).AsMemory(), timeout.Token);
            process.StandardInput.Close();
            await process.WaitForExitAsync(timeout.Token);
            if (process.ExitCode != 0 || await output != "verified" || !string.IsNullOrWhiteSpace(await error))
                throw new InvalidDataException("Installer publisher, timestamp or version verification failed.");
            // Inno's PE string resource may be space-padded. The signed JSON
            // release version remains strict; normalize only OS resource text.
            var actual = FileVersionInfo.GetVersionInfo(file).ProductVersion;
            if (ResourceVersion(actual, installedBinary) != expected ||
                installedBinary && ApplicationUpdateVersion.ParseInstalled(FileVersionInfo.GetVersionInfo(file).FileVersion?.Trim()) != expected)
                throw new InvalidDataException("Installer version differs from the signed offer.");
        }
        finally
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true); // Only this verifier process we created.
                await process.WaitForExitAsync(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(5));
            }
            await Task.WhenAll(output, error).WaitAsync(TimeSpan.FromSeconds(5));
        }
    }

    internal static Version ResourceVersion(string? value, bool installedBinary) =>
        installedBinary ? InstalledBinaryVersion(value?.Trim()) : ApplicationUpdateVersion.Parse(value?.Trim());

    // .NET's signed helper/Host adds a source revision to ProductVersion, whereas
    // Flutter uses numeric build metadata. Neither changes the release version.
    internal static Version InstalledBinaryVersion(string? value)
    {
        if (value is null || value.Length > 96) throw new InvalidDataException();
        var parts = value.Split('+');
        if (parts.Length > 2 || parts.Length == 2 && (parts[1].Length == 0 ||
            !parts[1].All(char.IsAsciiDigit) && !(parts[1].Length == 40 && parts[1].All(Uri.IsHexDigit))))
            throw new InvalidDataException("Invalid binary version metadata.");
        return ApplicationUpdateVersion.Parse(parts[0]);
    }
}
