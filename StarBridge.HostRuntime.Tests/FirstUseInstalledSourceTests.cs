using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Updates;
using StarBridge.HostRuntime.Support;

internal static class FirstUseInstalledSourceTests
{
    internal static void Run()
    {
        var root=Path.Combine(Path.GetTempPath(),"starbridge-installed-source-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var install=Path.Combine(root,"installation");
            Directory.CreateDirectory(Path.Combine(install,"native_host","maintenance"));
            var client=Path.Combine(install,"starbridge_flutter.exe");
            // A real PE version is read by the production installation validator.
            var fixtureSource=Path.Combine(root,"Fixture.cs");
            File.WriteAllText(fixtureSource,"[assembly: System.Reflection.AssemblyInformationalVersion(\"0.7.2\")] class Fixture { static void Main() {} }");
            var compiler=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"Microsoft.NET","Framework64","v4.0.30319","csc.exe");
            var start=new System.Diagnostics.ProcessStartInfo(compiler) { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true };
            foreach(var argument in new[]{"/nologo","/target:exe","/out:"+client,fixtureSource})start.ArgumentList.Add(argument);
            using(var process=System.Diagnostics.Process.Start(start)!)
            {
                if(!process.WaitForExit(10000)){process.Kill(true);process.WaitForExit();throw new InvalidOperationException("Inert PE fixture compilation timed out.");}
                Check(process.ExitCode==0,"Inert PE fixture compiles without executing it.");
            }
            foreach(var path in new[]{"flutter_windows.dll","unins000.exe","unins000.dat","native_host/StarBridge.NativeHost.exe","native_host/maintenance/StarBridge.UpdateHelper.exe"})
                File.WriteAllBytes(Path.Combine(install,path),[0]);
            var version=System.Diagnostics.FileVersionInfo.GetVersionInfo(client).ProductVersion!.Split('+')[0];
            var registration=new InstalledUpdateRegistration(install,version,FlutterInstallationIdentity.Product,"\""+Path.Combine(install,"unins000.exe")+"\"");
            var host=Path.Combine(install,"native_host","StarBridge.NativeHost.exe");
            var data=Path.Combine(root,"data");
            registration.Require(client,host,data);
            var fresh=new FirstUseInstalledObservation(registration,new("fresh",version));
            var update=fresh with { Source=new("update",version) };
            FirstUseInstallSource? Read(FirstUseInstalledObservation before,FirstUseInstalledObservation after)
            {var calls=0;return FirstUseStartupReader.ReadInstalledSource(client,host,data,()=>++calls==1?before:after);}
            Check(Read(fresh,fresh)?.Kind=="fresh","Stable bound fresh registration is accepted.");
            Check(Read(update,update)?.Kind=="update","Stable bound update registration is accepted.");
            Check(Read(fresh,update) is null,"Same-version replacement changing only source must not offer stale fresh setup.");
            Check(Read(fresh,fresh with { Source=null }) is null,"Disappearing source stamp is unknown.");
            Check(Read(fresh,fresh with { Registration=registration with { Version="0.0.0" } }) is null,"Changed registration is unknown.");
            Check(Read(fresh with { Source=new("fresh","0.0.0") },fresh) is null,"Source version must match actual installed client.");
            Check(FirstUseStartupReader.ReadInstalledSource(Path.Combine(root,"other.exe"),host,data,()=>fresh) is null,"Another client cannot borrow this registration.");
            Check(FirstUseStartupReader.ReadInstalledSource(client,host,install,()=>fresh) is null,"Data root cannot overlap installation.");
            Console.WriteLine("PASS installed first-use source binding, fresh/update, source-only replacement race, missing stamp, version and path mismatch");
        }
        finally{Directory.Delete(root,true);} // Unique synthetic fixture only; no registry writes.
    }
    private static void Check(bool value,string message){if(!value)throw new InvalidOperationException(message);}
}
