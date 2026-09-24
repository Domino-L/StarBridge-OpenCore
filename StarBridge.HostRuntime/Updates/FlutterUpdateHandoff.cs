using System.Diagnostics;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Private exit-handoff handshake. A started helper is not enough:
/// the signed candidate and durable journal must be ready before the app exits.
/// Installed-product handoff is separately gated by the Host release configuration.</summary>
internal static class FlutterUpdateHandoff
{
    private const string PipeVariable = "STARBRIDGE_UPDATE_HANDOFF_PIPE";
    private const string NonceVariable = "STARBRIDGE_UPDATE_HANDOFF_NONCE";
    private const string Prefix = "starbridge-update-handoff-";
    private sealed record Receipt(int SchemaVersion, string Nonce, int HelperPid);

    internal static Task<Process> StartIsolatedAsync(string helper, string plan, CancellationToken cancellation = default) =>
        StartAsync(helper, plan, "--isolated-plan", cancellation);

    internal static Task<Process> StartInstalledAsync(string helper, string plan, CancellationToken cancellation = default) =>
        StartAsync(helper, plan, "--installed-plan", cancellation);

    private static async Task<Process> StartAsync(string helper, string plan, string command, CancellationToken cancellation)
    {
        if (!Path.IsPathFullyQualified(helper) || !Path.IsPathFullyQualified(plan))
            throw new InvalidDataException("Handoff requires Host-owned absolute paths.");
        cancellation.ThrowIfCancellationRequested();
        var name = Prefix + Guid.NewGuid().ToString("N");
        var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        using var pipe = new NamedPipeServerStream(name, PipeDirection.In, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var start = new ProcessStartInfo(helper) { UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(helper)!, WindowStyle = ProcessWindowStyle.Hidden };
        start.ArgumentList.Add(command);
        start.ArgumentList.Add(plan);
        start.Environment[PipeVariable] = name;
        start.Environment[NonceVariable] = nonce;
        var process = Process.Start(start) ?? throw new IOException("Update helper did not start.");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            var receive = ReceiveAsync(pipe, timeout.Token);
            var exited = process.WaitForExitAsync(timeout.Token);
            if (await Task.WhenAny(receive, exited) == exited)
                throw new IOException("Helper exited before accepting the update.");
            var receipt = await receive;
            cancellation.ThrowIfCancellationRequested();
            if (process.HasExited || receipt.SchemaVersion != 1 || receipt.Nonce != nonce || receipt.HelperPid != process.Id)
                throw new InvalidDataException("Update handoff was not confirmed.");
            return process; // Caller owns handle; success permits the existing guarded exit flow.
        }
        catch
        {
            // Only this exact newly launched helper, never the original app or Host.
            if (!process.HasExited) process.Kill();
            using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await process.WaitForExitAsync(stop.Token);
            process.Dispose();
            throw;
        }
        finally { timeout.Cancel(); }
    }

    // Called while the transaction lease is held, after the journal has been
    // flushed and before waiting for the original owners or changing directories.
    internal static Task ReportPreparedAsync(CancellationToken cancellation) => ReportPreparedAsync(cancellation, false);

    internal static async Task ReportPreparedAsync(CancellationToken cancellation, bool required)
    {
        var name = Environment.GetEnvironmentVariable(PipeVariable);
        var nonce = Environment.GetEnvironmentVariable(NonceVariable);
        if (name is null && nonce is null && !required) return; // Existing isolated CLI tests only.
        if (name is null || !name.StartsWith(Prefix, StringComparison.Ordinal) ||
            !Guid.TryParseExact(name[Prefix.Length..], "N", out _) || nonce is null ||
            nonce.Length != 64 || nonce.Any(value => !Uri.IsHexDigit(value)))
            throw new InvalidDataException("Invalid handoff context.");
        using var pipe = new NamedPipeClientStream(".", name, PipeDirection.Out, PipeOptions.Asynchronous);
        await pipe.ConnectAsync(cancellation);
        await pipe.WriteAsync(JsonSerializer.SerializeToUtf8Bytes(new Receipt(1, nonce, Environment.ProcessId)), cancellation);
        await pipe.FlushAsync(cancellation);
    }

    private static async Task<Receipt> ReceiveAsync(NamedPipeServerStream pipe, CancellationToken cancellation)
    {
        await pipe.WaitForConnectionAsync(cancellation);
        using var buffer = new MemoryStream();
        var bytes = new byte[256];
        int count;
        while ((count = await pipe.ReadAsync(bytes, cancellation)) != 0)
        {
            if (buffer.Length + count > 1024) throw new InvalidDataException("Oversized handoff receipt.");
            buffer.Write(bytes, 0, count);
        }
        return JsonSerializer.Deserialize<Receipt>(buffer.ToArray()) ?? throw new InvalidDataException("Missing handoff receipt.");
    }
}
