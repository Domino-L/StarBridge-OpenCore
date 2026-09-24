namespace StarBridge.HostRuntime.Support;

/// <summary>Independent from the retired WPF installer. Never reuse its AppId.</summary>
internal static class FlutterInstallationIdentity
{
    internal const string AppId = "6E9A218B-6149-4F61-8C90-B34567DECA02";
    internal const string Product = "StarBridge.Flutter";
    internal const string Executable = "starbridge_flutter.exe";
    internal const string KeyName = "{" + AppId + "}_is1";
    internal const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + KeyName;
}
