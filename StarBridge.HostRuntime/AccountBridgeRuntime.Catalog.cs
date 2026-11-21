using System.Text.Json;
using StarBridge.HostRuntime.Catalog;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private ScmCatalogReader? _catalog;
    internal static bool IsCatalogRequest(string name) => ScmCatalogReader.Operations.Contains(name) || name == "catalog.openScm";
    internal Action<Uri> OpenCatalogWebsite { get; set; } = Support.HelpSupportBridgeDispatcher.OpenBrowser;

    // Production composition and its regression share this one installer. The gate is read
    // per request because CreateWithFirstUseModeAsync installs it after construction.
    internal void InstallCatalogReader(Uri baseUri, HttpMessageHandler? handler = null, TimeProvider? time = null)
    {
        _catalog?.Dispose();
        _catalog = new(baseUri, handler, time, network: () => DeviceNetwork);
    }

    private async ValueTask<BridgeDispatchBatch> DispatchCatalogAsync(BridgeEnvelope request, CancellationToken token)
    {
        BridgeDispatchBatch Error(string code) => new(BridgeEnvelope.ErrorResponse(request,
            new(code, "Catalogue read unavailable.", true)), []);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var generation = Generation;
            var owner = _host.CurrentContext;
            bool Current() => !_disposed && Generation == generation && _host.CurrentContext == owner && !token.IsCancellationRequested;
            if (!Current() || request.SessionGeneration != generation || request.MessageType != BridgeMessageTypes.Request ||
                request.AccountContext is not null && request.AccountContext != owner) return Error("catalog.context_changed");
            var input = request.Payload;
            if (input.ValueKind != JsonValueKind.Object || CatalogProjection.At(input, "schemaVersion").ValueKind != JsonValueKind.Number ||
                CatalogProjection.At(input, "schemaVersion").GetInt32() != 1) return Error("catalog.invalid_request");
            if (request.Name == "catalog.openScm")
            {
                var uri = CatalogWebsite(input);
                using var work = DeviceNetwork.Enter(token);
                if (work is null) return Error("catalog.unavailable");
                work.RequireCurrent();
                if (!Current()) return Error("catalog.context_changed");
                OpenCatalogWebsite(uri);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, opened = true }), []);
            }
            if (_catalog is null) return Error("catalog.unavailable");
            var result = await _catalog.ReadAsync(request.Name, input, token);
            return Current() ? new(BridgeEnvelope.Response(request, result), []) : Error("catalog.context_changed");
        }
        catch (CatalogReadException e) { return Error(e.Code); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception e) when (e is ArgumentException or JsonException or InvalidOperationException or
            FormatException or OverflowException or BridgeProtocolException or System.ComponentModel.Win32Exception)
        { return Error("catalog.unavailable"); }
    }

    internal static Uri CatalogWebsite(JsonElement input)
    {
        if (input.GetRawText().Length > 4096 || input.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "kind" or "id" or "title")) ||
            input.EnumerateObject().Select(p => p.Name).Distinct().Count() != input.EnumerateObject().Count()) throw new ArgumentException();
        var kind = CatalogProjection.At(input, "kind").GetString();
        string path;
        if (kind == "blueprints")
        {
            var id = CatalogProjection.At(input, "id").GetInt64();
            if (id <= 0) throw new ArgumentException();
            path = "search/blueprint?blueprintId=" + id.ToString(System.Globalization.CultureInfo.InvariantCulture);
        }
        else if (kind == "missions")
        {
            var title = CatalogProjection.At(input, "title").GetString();
            if (string.IsNullOrWhiteSpace(title) || title.Length > 1000 || title.Any(char.IsControl)) throw new ArgumentException();
            path = "search/missions?keyword=" + Uri.EscapeDataString(title);
        }
        else throw new ArgumentException();
        return new(Support.HelpSupportBridgeDispatcher.ScmWebsiteRoot, path);
    }
}
