using System.ComponentModel;
using System.IO;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace StarBridge.Desktop;

internal static class UserFacingError
{
    public static string Describe(
        Exception exception,
        string fallback = "操作未完成，请稍后重试。",
        [CallerMemberName] string operation = "")
    {
        ArgumentNullException.ThrowIfNull(exception);

        App.WriteDiagnosticLog(
            $"user-operation-failed operation={operation} exception={exception}");

        var cause = GetRelevantException(exception);
        return cause switch
        {
            TaskCanceledException or TimeoutException =>
                "请求超时，请稍后重试。",
            HttpRequestException =>
                "无法连接星海舰桥服务，请检查网络后重试。",
            UnauthorizedAccessException =>
                "没有访问所需文件的权限，请检查文件或文件夹权限后重试。",
            IOException =>
                "无法读写本地文件，请确认文件未被其他程序占用后重试。",
            JsonException =>
                "本地数据无法读取，请运行一键诊断后重试。",
            FormatException or ArgumentException =>
                "数据格式不正确，请重新检查后重试。",
            Win32Exception =>
                "Windows 未能完成此操作，请稍后重试。",
            _ => fallback
        };
    }

    private static Exception GetRelevantException(Exception exception)
    {
        var current = exception;
        while (current is AggregateException { InnerExceptions.Count: 1 } aggregate)
        {
            current = aggregate.InnerExceptions[0];
        }

        return current;
    }
}
