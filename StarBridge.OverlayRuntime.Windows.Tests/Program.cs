using System.Reflection;
using StarBridge.Desktop.Tests;
using StarBridge.OverlayRuntime.Windows;

var rendering = typeof(WindowsInformationOverlayRuntimeFactory).Assembly;
foreach (var name in new[] { "App", "MainWindow", "OverlayWindow", "InGameMenuWindow", "DesktopAppConfig", "AccountSessionCoordinator" })
    if (rendering.GetType("StarBridge.Desktop." + name) is not null)
        throw new InvalidOperationException("Retired application type entered standalone renderer: " + name);
foreach (var reference in rendering.GetReferencedAssemblies())
    if (reference.Name is "Star Bridge" or "StarBridge.Desktop" or "StarBridge.Server")
        throw new InvalidOperationException("Forbidden application/service dependency: " + reference.Name);
if (!typeof(StarBridge.HostRuntime.Overlay.IInformationOverlayRuntime)
    .IsAssignableFrom(rendering.GetType("StarBridge.Desktop.NativeInformationOverlayRuntime")))
    throw new InvalidOperationException("Native information overlay contract is missing.");
Console.WriteLine("PASS independent renderer contains native overlay and excludes retired application/service types");

RoomOverlayProjectionTests.RunAll();
Console.WriteLine("PASS room projection, live reminders and revoked-content clearing");
CommunityOverlayProjectionTests.RunAll();
Console.WriteLine("PASS community projection, room priority and source isolation");
OverlayStartupFocusPolicyTests.RunAll();
Console.WriteLine("PASS startup focus policy");
DesktopNotificationCardTests.RunAll();
Console.WriteLine("PASS notification resources and offscreen multi-DPI rendering");
