using System.Text;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class ClientLicenseTests
{
    internal static async Task PreservesDocumentAndDoesNotWrite()
    {
        await WithRoot(async root =>
        {
            var path = Path.Combine(root, ClientLicenseReader.FileName);
            const string terms = "Synthetic license\r\n\r\nEnglish and 中文\tEnd\r\n";
            var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(terms)).ToArray();
            await File.WriteAllBytesAsync(path, bytes);
            var result = await new ClientLicenseReader(root).ReadAsync();
            Require(result.State == "ready" && result.Text == terms);
            Require(bytes.SequenceEqual(await File.ReadAllBytesAsync(path)));
            Require(Directory.GetFiles(root).Length == 1);
        });
    }

    internal static async Task MissingNeverSearchesParent()
    {
        await WithRoot(async root =>
        {
            await File.WriteAllTextAsync(Path.Combine(root, ClientLicenseReader.FileName), "Parent must not be read");
            var child = Directory.CreateDirectory(Path.Combine(root, "child")).FullName;
            Require((await new ClientLicenseReader(child).ReadAsync()).State == "missing");
            var missing = Path.Combine(root, "not-created");
            Require((await new ClientLicenseReader(missing).ReadAsync()).State == "missing");
            Require(!Directory.Exists(missing));
        });
    }

    internal static async Task RejectsInvalidOversizeAndLockedFiles()
    {
        await WithRoot(async root =>
        {
            var path = Path.Combine(root, ClientLicenseReader.FileName);
            foreach (var bytes in new[] { Array.Empty<byte>(), new byte[] { 0xFF, 0xFE, 0xFF },
                Encoding.UTF8.GetBytes(" \r\n "), Encoding.UTF8.GetBytes("text\0control"),
                new byte[ClientLicenseReader.MaximumBytes + 1] })
            {
                await File.WriteAllBytesAsync(path, bytes);
                var result = await new ClientLicenseReader(root).ReadAsync();
                Require(result.State == "unreadable" && result.Text is null);
            }
            await File.WriteAllTextAsync(path, "Synthetic valid terms");
            using var locked = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            Require((await new ClientLicenseReader(root).ReadAsync()).State == "unreadable");
        });
    }

    internal static async Task FixedFileOnlyAndReadOnlySharing()
    {
        await WithRoot(async root =>
        {
            var path = Path.Combine(root, ClientLicenseReader.FileName);
            Directory.CreateDirectory(path);
            Require((await new ClientLicenseReader(root).ReadAsync()).State == "unreadable");
            Directory.Delete(path);
            var bytes = Encoding.UTF8.GetBytes(new string('a', ClientLicenseReader.MaximumBytes));
            await File.WriteAllBytesAsync(path, bytes);
            using var shared = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            Require((await new ClientLicenseReader(root).ReadAsync()).Text?.Length == bytes.Length);
        });
    }

    internal static async Task StrictDeviceProtocol()
    {
        await WithRoot(async root =>
        {
            await File.WriteAllTextAsync(Path.Combine(root, ClientLicenseReader.FileName), "Synthetic full terms");
            using var dispatcher = new ClientLicenseBridgeDispatcher(new(root), () => 4);
            Require(!BridgeRequestPolicy.RequiresAccountContext(ClientLicenseBridgeDispatcher.RequestName));
            var response = (await dispatcher.DispatchAsync(Request())).Response;
            Require(response.Status == "ok" && response.AccountContext is null);
            Require(response.Payload.EnumerateObject().Count() == 3);
            Require(response.Payload.GetProperty("text").GetString() == "Synthetic full terms");
            foreach (var invalid in new[] { Request(new { schemaVersion = 2 }), Request(new { schemaVersion = "1" }),
                Request(new { schemaVersion = 1, path = root }), Request() with { AccountContext = new("test", "scm", "synthetic") },
                Request() with { Name = "legal.accept" } })
                Require((await dispatcher.DispatchAsync(invalid)).Response.Status == "error");
            File.Delete(Path.Combine(root, ClientLicenseReader.FileName));
            response = (await dispatcher.DispatchAsync(Request())).Response;
            Require(response.Payload.GetProperty("state").GetString() == "missing");
            Require(response.Payload.GetProperty("text").ValueKind == System.Text.Json.JsonValueKind.Null);
            Require(!response.Payload.GetRawText().Contains(root));
        });
    }

    internal static async Task CancellationGenerationAndLifetime()
    {
        await WithRoot(async root =>
        {
            await File.WriteAllTextAsync(Path.Combine(root, ClientLicenseReader.FileName), "Synthetic full terms");
            var calls = 0;
            using var dispatcher = new ClientLicenseBridgeDispatcher(new(root), () => ++calls == 1 ? 4 : 5);
            Require((await dispatcher.DispatchAsync(Request())).Response.Status == "error");
            using var current = new ClientLicenseBridgeDispatcher(new(root), () => 4);
            using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
            Require((await current.DispatchAsync(Request(), cancelled.Token)).Response.Status == "cancelled");
            current.Dispose();
            Require((await current.DispatchAsync(Request())).Response.Status == "error");
            Require(Directory.GetFiles(root).Length == 1);
        });
    }

    private static BridgeEnvelope Request(object? payload = null) => BridgeEnvelope.Request(
        ClientLicenseBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 4, payload ?? new { schemaVersion = 1 });
    private static void Require(bool condition) { if (!condition) throw new Exception("Client license contract failed."); }
    private static async Task WithRoot(Func<string, Task> test)
    {
        var root = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "starbridge-license-test-" + Guid.NewGuid().ToString("N"))).FullName;
        try { await test(root); } finally { Directory.Delete(root, true); }
    }
}
