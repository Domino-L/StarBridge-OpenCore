namespace StarBridge.HostRuntime.Storage;

public sealed class StorageMigrationWpfRunningException : IOException
{
    public StorageMigrationWpfRunningException() : base("The WPF client is still running.") { }
}

internal static class StorageMigrationWpfGuard
{
    internal const string MutexName = @"Local\StarBridge.Desktop.SingleInstance.9D5E2B18";

    internal static void RequireStopped(string mutexName = MutexName)
    {
        Mutex mutex;
        try { mutex = Mutex.OpenExisting(mutexName); }
        catch (WaitHandleCannotBeOpenedException) { return; }
        using (mutex)
        {
            var acquired = false;
            try
            {
                try { acquired = mutex.WaitOne(0); }
                catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new StorageMigrationWpfRunningException();
            }
            finally { if (acquired) mutex.ReleaseMutex(); }
        }
    }
}
