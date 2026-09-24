using System.IO;

namespace StarBridge.HostRuntime.Auth;

internal static class ScmDeviceId
{
    private const string FileName = "scm-device.id";

    internal static string LoadOrCreate()
    {
        var path = Path.Combine(StarBridge.HostRuntime.HostDataRoot.CurrentRoot, FileName);
        try
        {
            if (File.Exists(path))
            {
                var stored = File.ReadAllText(path).Trim();
                if (Guid.TryParse(stored, out var parsed))
                {
                    return parsed.ToString("D");
                }
            }

            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var deviceId = Guid.NewGuid().ToString("D");
            var temporaryPath = path + ".tmp";
            File.WriteAllText(temporaryPath, deviceId);
            File.Move(temporaryPath, path, overwrite: true);
            return deviceId;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new InvalidOperationException("无法创建 SCM 实时连接设备标识。", exception);
        }
    }
}
