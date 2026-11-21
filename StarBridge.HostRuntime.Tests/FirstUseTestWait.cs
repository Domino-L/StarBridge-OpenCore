// Upper bound for first-use tests that wait for something to finish.
// Passing runs never reach it, so it costs nothing when the machine is quiet;
// a busy machine (full suites in parallel) used to push 3-5 second bounds over.
// Waits that expect nothing to happen keep their own short bounds.
internal static class FirstUseTestWait
{
    public static readonly TimeSpan Bound = TimeSpan.FromSeconds(30);
}
