using System.Diagnostics;
using System.IO.Pipes;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

public sealed record FlutterUpdateStartupReceipt(string Nonce, string Version, int BridgeProtocol,
    int ClientProcessId, int HostProcessId, bool FirstFrameRendered, bool HostReady);

/// <summary>Only enabled for a helper-launched client. No file paths or version claims
/// come from Flutter; the Host reads the actual parent executable's version.</summary>
public sealed class FlutterUpdateStartupReporter
{
    public const string PipeVariable = "STARBRIDGE_UPDATE_READY_PIPE";
    public const string NonceVariable = "STARBRIDGE_UPDATE_READY_NONCE";
    private readonly string _pipe, _nonce, _executable;
    private readonly int _parent;
    private int _reported;
    private FlutterUpdateStartupReporter(string pipe, string nonce, int parent, string executable)
    { _pipe = pipe; _nonce = nonce; _parent = parent; _executable = executable; }

    public static FlutterUpdateStartupReporter? FromEnvironment(int parent, string? executable)
    {
        var pipe = Environment.GetEnvironmentVariable(PipeVariable);
        var nonce = Environment.GetEnvironmentVariable(NonceVariable);
        if (pipe is null || !pipe.StartsWith("starbridge-update-ready-", StringComparison.Ordinal) ||
            !Guid.TryParseExact(pipe["starbridge-update-ready-".Length..], "N", out _) ||
            nonce is null || nonce.Length != 64 || nonce.Any(character => !Uri.IsHexDigit(character)) ||
            executable is null || !Path.IsPathFullyQualified(executable) || parent <= 0) return null;
        return new(pipe, nonce, parent, executable);
    }

    public async Task ReportFirstFrameAsync(CancellationToken cancellation)
    {
        if (Interlocked.CompareExchange(ref _reported, 1, 0) != 0) return;
        try
        {
            using var parent = Process.GetProcessById(_parent);
            if (parent.HasExited || !string.Equals(parent.MainModule?.FileName, _executable, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Update parent is no longer active.");
            var raw = FileVersionInfo.GetVersionInfo(_executable).ProductVersion?.Split('+')[0];
            if (!Version.TryParse(raw, out var version)) throw new InvalidDataException("Unknown client version.");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));
            using var pipe = new NamedPipeClientStream(".", _pipe, PipeDirection.Out, PipeOptions.Asynchronous);
            await pipe.ConnectAsync(timeout.Token);
            var receipt = new FlutterUpdateStartupReceipt(_nonce, version.ToString(), 1, _parent,
                Environment.ProcessId, FirstFrameRendered: true, HostReady: true);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(receipt);
            await pipe.WriteAsync(bytes, timeout.Token);
            await pipe.FlushAsync(timeout.Token);
        }
        catch { Interlocked.Exchange(ref _reported, 0); throw; }
    }
}
