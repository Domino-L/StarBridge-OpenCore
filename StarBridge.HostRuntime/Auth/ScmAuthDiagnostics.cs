using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;

namespace StarBridge.HostRuntime.Auth;

internal static class ScmAuthDiagnostics
{
    internal const string CorrelationHeader = "X-StarBridge-Correlation-Id";

    private static readonly object WriteLock = new();

    internal static string NewCorrelationId() => Guid.NewGuid().ToString("N")[..12];

    internal static Stopwatch Start(
        string correlationId,
        string step,
        string detail = "")
    {
        Write(correlationId, step, "started", detail);
        return Stopwatch.StartNew();
    }

    internal static void Completed(
        string correlationId,
        string step,
        Stopwatch stopwatch,
        string detail = "") =>
        Write(correlationId, step, "completed", WithElapsed(stopwatch, detail));

    internal static void Failed(
        string correlationId,
        string step,
        Stopwatch stopwatch,
        Exception exception,
        string detail = "")
    {
        var statusCode = exception is HttpRequestException requestException
            ? requestException.StatusCode
            : null;
        var safeDetail = $"{WithElapsed(stopwatch, detail)} exceptionType={exception.GetType().Name}";
        if (statusCode is not null)
        {
            safeDetail += $" status={(int)statusCode.Value}";
        }
        Write(correlationId, step, "failed", safeDetail);
    }

    internal static void Write(
        string correlationId,
        string step,
        string outcome,
        string detail = "")
    {
        try
        {
            var directory = StarBridge.HostRuntime.HostDataRoot.CurrentRoot;
            Directory.CreateDirectory(directory);
            var line = $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff zzz}] " +
                       $"correlationId={correlationId} step={step} outcome={outcome}";
            if (!string.IsNullOrWhiteSpace(detail))
            {
                line += " " + detail.Replace('\r', ' ').Replace('\n', ' ');
            }
            lock (WriteLock)
            {
                File.AppendAllText(
                    Path.Combine(directory, "scm-auth-diagnostics.log"),
                    line + Environment.NewLine);
            }
        }
        catch
        {
            // Authentication diagnostics must never alter the login result.
        }
    }

    internal static string Endpoint(Uri endpoint) =>
        $"{endpoint.Scheme}://{endpoint.Authority}{endpoint.AbsolutePath}";

    private static string WithElapsed(Stopwatch stopwatch, string detail)
    {
        var elapsed = $"elapsedMs={stopwatch.ElapsedMilliseconds}";
        return string.IsNullOrWhiteSpace(detail) ? elapsed : $"{elapsed} {detail}";
    }
}
