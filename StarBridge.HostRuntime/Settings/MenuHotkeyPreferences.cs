namespace StarBridge.HostRuntime.Settings;

// Device-local options only. Keyboard policy remains owned by the native
// runtime's shared WPF validator; no account or renderer window data is stored.
public sealed record MenuHotkeyOptions(string Binding = "Alt+M", bool Enabled = true, bool CloseWithHotkey = true)
{
    internal void Validate()
    {
        if (string.IsNullOrWhiteSpace(Binding) || Binding.Length > 64 || Binding.Any(char.IsControl))
            throw new ArgumentException("Invalid menu shortcut");
    }
}

public sealed record MenuHotkeyPreferences(long Revision, MenuHotkeyOptions Options);

public interface IMenuHotkeyPreferences
{
    MenuHotkeyPreferences ReadHotkey();
    MenuHotkeyPreferences SaveHotkey(long expectedRevision, MenuHotkeyOptions options);
}
