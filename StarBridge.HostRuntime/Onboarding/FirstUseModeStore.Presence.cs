using System.Text;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeStore
{
    // Negative evidence only: this marker never supplies a phase, identity,
    // original owner exit or permission to install anything. Keep it outside
    // the mode tree so losing that tree cannot look like an untouched install.
    private string PresencePath => Path.Combine(Path.GetDirectoryName(_directory)!, "first-use-mode-present.v1.bin");

    private FirstUseModeChoice AbsentTree(bool originalWriter)
    {
        Safe(PresencePath);
        if (!originalWriter && PresenceExists()) throw new InvalidDataException();
        return FirstUseModeChoice.Unchosen;
    }

    private bool PresenceExists()
    {
        try
        {
            var attributes = File.GetAttributes(PresencePath);
            if (attributes.HasFlag(FileAttributes.Directory)) throw new InvalidDataException();
            return true; // Do not interpret or overwrite even an unreadable marker.
        }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }

    private void EnsurePresence()
    {
        Safe(PresencePath);
        if (PresenceExists()) return;
        using var file = new FileStream(PresencePath, FileMode.CreateNew, FileAccess.Write,
            FileShare.None, 4096, FileOptions.WriteThrough);
        file.Write(Encoding.UTF8.GetBytes("StarBridge.first-use-mode.presence.v1"));
        file.Flush(true);
    }
}
