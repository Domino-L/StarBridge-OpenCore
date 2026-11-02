using System.Text;

namespace StarBridge.HostRuntime.Support;

/// <summary>The Desktop and Native Host share one device statistics identifier.</summary>
public static class AppStatsClientId
{
    public static string LoadOrCreate(string dataRoot)
    {
        Directory.CreateDirectory(dataRoot);
        var path = Path.Combine(dataRoot, "app-client-id.txt");
        // OpenOrCreate never truncates existing content. Every participant rereads
        // under the same cross-process exclusive handle before deciding to write.
        for (var attempt = 0; ; attempt++)
        {
            FileStream file;
            try { file = new(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) when (attempt < 20)
            {
                Thread.Sleep(25);
                continue;
            }
            using (file)
            {
                using var reader = new StreamReader(file, Encoding.UTF8, true, 1024, leaveOpen: true);
                var existing = reader.ReadToEnd().Trim();
                if (existing.Length == 32 && existing.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f'))
                    return existing;
                var created = Guid.NewGuid().ToString("N");
                file.Position = 0;
                file.SetLength(0);
                file.Write(Encoding.UTF8.GetBytes(created));
                file.Flush(flushToDisk: true);
                return created;
            }
        }
    }
}
