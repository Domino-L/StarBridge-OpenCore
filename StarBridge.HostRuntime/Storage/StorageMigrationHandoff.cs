using System.Diagnostics;
using System.IO.Pipes;
using System.Text.Json;

namespace StarBridge.HostRuntime.Storage;

internal static class StorageMigrationHandoff
{
    internal const string PipeVariable = "STARBRIDGE_STORAGE_HANDOFF_PIPE";
    internal const string NonceVariable = "STARBRIDGE_STORAGE_HANDOFF_NONCE";
    private const string Prefix = "starbridge-storage-handoff-";
    private sealed record Receipt(int SchemaVersion, string Nonce, int HelperPid);

    internal static async Task<Process> StartAsync(string helper, string planPath, string nonce,
        CancellationToken cancellation)
    {
        if (!Path.IsPathFullyQualified(helper) || !Path.IsPathFullyQualified(planPath) ||
            !Guid.TryParseExact(nonce, "N", out _)) throw new InvalidDataException("Invalid storage handoff.");
        var name = Prefix + Guid.NewGuid().ToString("N");
        using var pipe = new NamedPipeServerStream(name, PipeDirection.In, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var start = new ProcessStartInfo(helper) { UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(helper)!, WindowStyle = ProcessWindowStyle.Hidden };
        start.ArgumentList.Add("--storage-plan"); start.ArgumentList.Add(planPath);
        start.Environment[PipeVariable] = name; start.Environment[NonceVariable] = nonce;
        var process = Process.Start(start) ?? throw new IOException("Storage helper did not start.");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            var receive = ReceiveAsync(pipe, timeout.Token);
            var exited = process.WaitForExitAsync(timeout.Token);
            if (await Task.WhenAny(receive, exited) == exited) throw new IOException("Storage helper exited before preparation.");
            var receipt = await receive;
            cancellation.ThrowIfCancellationRequested();
            if (process.HasExited || receipt is not { SchemaVersion: 1 } || receipt.Nonce != nonce || receipt.HelperPid != process.Id)
                throw new InvalidDataException("Storage handoff was not confirmed.");
            return process;
        }
        catch
        {
            if (!process.HasExited) process.Kill();
            using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await process.WaitForExitAsync(stop.Token);
            process.Dispose();
            throw;
        }
        finally { timeout.Cancel(); }
    }

    internal static async Task ReportPreparedAsync(string nonce, CancellationToken cancellation)
    {
        var name = Environment.GetEnvironmentVariable(PipeVariable);
        var environmentNonce = Environment.GetEnvironmentVariable(NonceVariable);
        if (name is null || environmentNonce != nonce || !name.StartsWith(Prefix, StringComparison.Ordinal) ||
            !Guid.TryParseExact(name[Prefix.Length..], "N", out _)) throw new InvalidDataException("Invalid storage handoff context.");
        using var pipe = new NamedPipeClientStream(".", name, PipeDirection.Out, PipeOptions.Asynchronous);
        await pipe.ConnectAsync(cancellation);
        await pipe.WriteAsync(JsonSerializer.SerializeToUtf8Bytes(new Receipt(1, nonce, Environment.ProcessId)), cancellation);
        await pipe.FlushAsync(cancellation);
    }

    private static async Task<Receipt> ReceiveAsync(NamedPipeServerStream pipe, CancellationToken cancellation)
    {
        await pipe.WaitForConnectionAsync(cancellation);
        using var buffer = new MemoryStream();
        var bytes = new byte[256]; int count;
        while ((count = await pipe.ReadAsync(bytes, cancellation)) != 0)
        { if (buffer.Length + count > 1024) throw new InvalidDataException(); buffer.Write(bytes, 0, count); }
        return JsonSerializer.Deserialize<Receipt>(buffer.ToArray()) ?? throw new InvalidDataException();
    }
}
