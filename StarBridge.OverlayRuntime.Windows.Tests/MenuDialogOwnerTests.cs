using StarBridge.NativeHost;

internal static class MenuDialogOwnerTests
{
    internal static void Run()
    {
        var checks = 0;
        void Check(nint expected, int pid, nint foreground, nint fallback,
            Func<nint, uint> processOf)
        {
            var actual = WindowsStorageFolderPicker.SelectOwner(pid, foreground, fallback, processOf);
            if (actual != expected) throw new InvalidOperationException("Unexpected picker owner");
            checks++;
        }
        uint ProcessOf(nint handle) => handle switch { 10 => 42, 20 => 42, 30 => 91, _ => 0 };
        Check(20, 42, 20, 10, ProcessOf); // Foreground auxiliary menu, not hidden client.
        Check(10, 42, 10, 20, ProcessOf); // Foreground normal settings page.
        Check(0, 42, 30, 10, ProcessOf); // Another app became foreground: no focus stealing.
        Check(0, 42, 99, 10, ProcessOf); // Stale foreground HWND.
        Check(10, 42, 0, 10, ProcessOf); // Trusted fallback only without a foreground root.
        Check(0, 42, 0, 30, ProcessOf); // Unrelated fallback rejected.
        Check(0, 42, 0, 0, ProcessOf);
        Check(0, 0, 20, 10, ProcessOf);
        Check(0, -1, 20, 10, ProcessOf);
        Console.WriteLine($"PASS menu native dialog ownership: {checks} assertions");
    }
}
