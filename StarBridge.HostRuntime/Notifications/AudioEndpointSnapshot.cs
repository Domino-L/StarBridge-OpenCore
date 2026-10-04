namespace StarBridge.HostRuntime.Notifications;

using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

// Read-only default multimedia render endpoint at call time. NOT a PlaySound stream route
// or proof of audibility. Process-salted fingerprint never persists the native device ID.
internal static class AudioEndpointSnapshot
{
    private static readonly byte[] Salt = RandomNumberGenerator.GetBytes(32);
    internal static string Fingerprint(string id) => Convert.ToHexString(
        HMACSHA256.HashData(Salt, Encoding.UTF8.GetBytes(id)))[..16];

    internal static string Read()
    {
        if (!OperatingSystem.IsWindows()) return "unavailable";
        object? instance = null;
        IDevice? device = null;
        try {
            var type = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), true)!;
            instance = Activator.CreateInstance(type);
            var enumerator = (IEnumerator)instance!;
            if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) < 0 || device is null) return "unavailable";
            if (device.GetId(out var id) < 0 || string.IsNullOrEmpty(id)) return "unavailable";
            return Fingerprint(id);
        } catch (Exception) { return "unavailable"; }
        finally {
            if (device is not null) { try { Marshal.ReleaseComObject(device); } catch { } }
            if (instance is not null) { try { Marshal.ReleaseComObject(instance); } catch { } }
        }
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int flow, uint mask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDevice
    {
        [PreserveSig] int Activate(ref Guid iid, uint context, IntPtr parameters, out IntPtr value);
        [PreserveSig] int OpenPropertyStore(uint access, out IntPtr store);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    }
}
