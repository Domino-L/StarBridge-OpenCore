using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace StarBridge.Desktop;

internal sealed class OverlayFrameScheduler : IDisposable
{
    private const uint CreateWaitableTimerHighResolution = 0x00000002;
    private const uint TimerAllAccess = 0x001F0003;
    private const uint Infinite = 0xFFFFFFFF;
    private const uint WaitObject0 = 0x00000000;

    private readonly Dispatcher _dispatcher;
    private readonly Action _renderFrame;
    private readonly IntPtr _wakeEvent;
    private readonly IntPtr _waitableTimer;
    private readonly IntPtr[] _waitHandles;
    private readonly Thread _thread;
    private int _active;
    private int _framesPerSecond = 120;
    private int _dispatchPending;
    private int _disposed;

    public OverlayFrameScheduler(Dispatcher dispatcher, Action renderFrame)
    {
        _dispatcher = dispatcher;
        _renderFrame = renderFrame;
        _wakeEvent = CreateEvent(IntPtr.Zero, false, false, null);
        if (_wakeEvent == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create the overlay frame scheduler wake event.");
        }

        _waitableTimer = CreateWaitableTimerEx(
            IntPtr.Zero,
            null,
            CreateWaitableTimerHighResolution,
            TimerAllAccess);
        if (_waitableTimer == IntPtr.Zero)
        {
            _waitableTimer = CreateWaitableTimerEx(IntPtr.Zero, null, 0, TimerAllAccess);
        }

        if (_waitableTimer == IntPtr.Zero)
        {
            var error = Marshal.GetLastWin32Error();
            CloseHandle(_wakeEvent);
            throw new Win32Exception(error, "Could not create the overlay frame scheduler timer.");
        }

        _waitHandles = [_wakeEvent, _waitableTimer];
        _thread = new Thread(Run)
        {
            IsBackground = true,
            Name = "StarBridge Overlay Frame Pacer",
            Priority = ThreadPriority.AboveNormal
        };
        _thread.Start();
    }

    public void Start(int framesPerSecond)
    {
        UpdateFrameRate(framesPerSecond);
        Volatile.Write(ref _active, 1);
        SetEvent(_wakeEvent);
    }

    public void UpdateFrameRate(int framesPerSecond)
    {
        var normalized = Math.Clamp(framesPerSecond, 1, 240);
        if (Interlocked.Exchange(ref _framesPerSecond, normalized) != normalized)
        {
            SetEvent(_wakeEvent);
        }
    }

    public void Stop()
    {
        Volatile.Write(ref _active, 0);
        SetEvent(_wakeEvent);
    }

    internal static long AdvanceDeadline(long previousDeadline, long now, long intervalTicks)
    {
        var normalizedInterval = Math.Max(1, intervalTicks);
        var next = previousDeadline + normalizedInterval;
        if (next > now)
        {
            return next;
        }

        var missedIntervals = ((now - next) / normalizedInterval) + 1;
        return next + missedIntervals * normalizedInterval;
    }

    private void Run()
    {
        var nextDeadline = Stopwatch.GetTimestamp();
        while (Volatile.Read(ref _disposed) == 0)
        {
            if (Volatile.Read(ref _active) == 0)
            {
                WaitForSingleObject(_wakeEvent, Infinite);
                nextDeadline = Stopwatch.GetTimestamp();
                continue;
            }

            var framesPerSecond = Math.Max(1, Volatile.Read(ref _framesPerSecond));
            var intervalTicks = Math.Max(1, Stopwatch.Frequency / framesPerSecond);
            nextDeadline = AdvanceDeadline(nextDeadline, Stopwatch.GetTimestamp(), intervalTicks);
            if (!WaitUntil(nextDeadline))
            {
                nextDeadline = Stopwatch.GetTimestamp();
                continue;
            }

            QueueFrame();
        }
    }

    private bool WaitUntil(long deadline)
    {
        var remainingTicks = deadline - Stopwatch.GetTimestamp();
        if (remainingTicks <= 0)
        {
            return true;
        }

        var dueTime100Nanoseconds = -Math.Max(
            1,
            (long)Math.Ceiling(remainingTicks * 10_000_000.0 / Stopwatch.Frequency));
        if (!SetWaitableTimer(_waitableTimer, ref dueTime100Nanoseconds, 0, IntPtr.Zero, IntPtr.Zero, false))
        {
            return true;
        }

        var result = WaitForMultipleObjects((uint)_waitHandles.Length, _waitHandles, false, Infinite);
        return result == WaitObject0 + 1;
    }

    private void QueueFrame()
    {
        if (Interlocked.CompareExchange(ref _dispatchPending, 1, 0) != 0)
        {
            return;
        }

        try
        {
            _dispatcher.BeginInvoke(() =>
            {
                try
                {
                    if (Volatile.Read(ref _disposed) == 0)
                    {
                        _renderFrame();
                    }
                }
                finally
                {
                    Volatile.Write(ref _dispatchPending, 0);
                }
            }, DispatcherPriority.Render);
        }
        catch (InvalidOperationException)
        {
            Volatile.Write(ref _dispatchPending, 0);
        }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        SetEvent(_wakeEvent);
        if (_thread.IsAlive && Thread.CurrentThread != _thread)
        {
            _thread.Join(TimeSpan.FromSeconds(1));
        }

        CloseHandle(_waitableTimer);
        CloseHandle(_wakeEvent);
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWaitableTimerEx(
        IntPtr timerAttributes,
        string? timerName,
        uint flags,
        uint desiredAccess);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWaitableTimer(
        IntPtr timer,
        ref long dueTime,
        int period,
        IntPtr completionRoutine,
        IntPtr argument,
        [MarshalAs(UnmanagedType.Bool)] bool resume);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateEvent(
        IntPtr eventAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool manualReset,
        [MarshalAs(UnmanagedType.Bool)] bool initialState,
        string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetEvent(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForMultipleObjects(
        uint count,
        IntPtr[] handles,
        [MarshalAs(UnmanagedType.Bool)] bool waitAll,
        uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}
