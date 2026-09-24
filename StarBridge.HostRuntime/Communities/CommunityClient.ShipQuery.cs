using System.Text.Json;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record ShipQuery(string Text, string Filter, string Sort, bool Descending, string Culture)
    {
        internal object View => new { text = Text, filter = Filter, sort = Sort, descending = Descending, culture = Culture };
        internal string Url => "&view=library&q=" + Uri.EscapeDataString(Text) + "&filter=" + Filter + "&sort=" + Sort
            + "&descending=" + (Descending ? "true" : "false") + "&culture=" + Culture;
    }
    private static ShipQuery ParseShipQuery(JsonElement value)
    {
        ShipObject(value);
        if (value.EnumerateObject().Any(p => p.Name is not ("text" or "filter" or "sort" or "descending" or "culture"))) throw Invalid();
        var text = Text(value, "text", 128).Trim();
        var filter = Text(value, "filter", 16);
        var sort = Text(value, "sort", 16);
        var culture = Text(value, "culture", 16);
        if (filter is not ("all" or "capital" or "large" or "medium" or "small" or "flyable" or "concept" or "unknown") ||
            sort is not ("name" or "spec" or "status" or "price" or "role" or "owner") || culture is not ("zh-CN" or "zh-TW" or "en-US")) throw Invalid();
        return new(text, filter, sort, value.GetProperty("descending").GetBoolean(), culture);
    }
}
