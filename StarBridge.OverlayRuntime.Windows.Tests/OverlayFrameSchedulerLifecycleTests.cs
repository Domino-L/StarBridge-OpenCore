using System.Reflection;
using System.Windows.Threading;
namespace StarBridge.Desktop.Tests;
internal static class OverlayFrameSchedulerLifecycleTests
{
    internal static async Task Run()
    {
        using var ready=new ManualResetEventSlim();using var blocked=new ManualResetEventSlim();using var release=new ManualResetEventSlim();
        Dispatcher? dispatcher=null;var count=0;
        var thread=new Thread(()=>{dispatcher=Dispatcher.CurrentDispatcher;ready.Set();Dispatcher.Run();}){IsBackground=true,Name="Overlay scheduler regression"};
        thread.SetApartmentState(ApartmentState.STA);thread.Start();
        Check(ready.Wait(TimeSpan.FromSeconds(3)),"Dispatcher startup did not settle");
        using var scheduler=new OverlayFrameScheduler(dispatcher!,()=>Interlocked.Increment(ref count));
        var pending=typeof(OverlayFrameScheduler).GetField("_dispatchPending",BindingFlags.NonPublic|BindingFlags.Instance)!;
        try
        {
            _ = dispatcher!.BeginInvoke(()=>{blocked.Set();release.Wait(TimeSpan.FromSeconds(3));},DispatcherPriority.Send);
            Check(blocked.Wait(TimeSpan.FromSeconds(3)),"Dispatcher block did not start");
            scheduler.Start(60);
            Check(SpinWait.SpinUntil(()=>(int)pending.GetValue(scheduler)! == 1,2000),"No actual frame was queued");
            scheduler.Stop();release.Set();
            await dispatcher.InvokeAsync(()=>{},DispatcherPriority.Background).Task;
            Check(Volatile.Read(ref count)==0,"A queued frame rendered after scheduler stop");
            scheduler.Start(60);
            Check(SpinWait.SpinUntil(()=>Volatile.Read(ref count)>=2,2000),"Stopped scheduler did not restart");
            scheduler.Stop();await dispatcher.InvokeAsync(()=>{},DispatcherPriority.Background).Task;
            var stopped=Volatile.Read(ref count);await Task.Delay(150);
            Check(Volatile.Read(ref count)==stopped,"Stopped scheduler kept dispatching frames");
            scheduler.Start(120);scheduler.UpdateFrameRate(120,200);
            await Task.Delay(450);var quietStart=Volatile.Read(ref count);await Task.Delay(650);
            var quietFrames=Volatile.Read(ref count)-quietStart;
            Check(quietFrames is >=2 and <=6,"Quiet bounded deadline did not reduce actual dispatcher wakeups");
            scheduler.Start(120);var activeStart=Volatile.Read(ref count);
            Check(SpinWait.SpinUntil(()=>Volatile.Read(ref count)-activeStart>=10,500),"Fresh native start did not promptly clear the quiet deadline");
            scheduler.Stop();await dispatcher.InvokeAsync(()=>{},DispatcherPriority.Background).Task;
            scheduler.Dispose();scheduler.Dispose();
            var timerThread=(Thread)typeof(OverlayFrameScheduler).GetField("_thread",BindingFlags.NonPublic|BindingFlags.Instance)!.GetValue(scheduler)!;
            Check(!timerThread.IsAlive,"Disposed timer thread survived");
        }
        finally{release.Set();scheduler.Dispose();dispatcher!.BeginInvokeShutdown(DispatcherPriority.Send);Check(thread.Join(TimeSpan.FromSeconds(3)),"Dispatcher thread leaked");}
        Console.WriteLine("PASS actual waitable frame scheduler: queued stop, restart, bounded quiet deadline, prompt native restart, stopped idle and idempotent disposal");
    }
    private static void Check(bool value,string text){if(!value)throw new InvalidOperationException(text);}
}
