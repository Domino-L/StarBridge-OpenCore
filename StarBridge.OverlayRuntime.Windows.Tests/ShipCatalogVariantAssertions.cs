using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

internal static class ShipCatalogVariantAssertions
{
    internal static string ExpectedChinese(string raw, string english, string chinese, ShipDisplayName? actual, List<string> failures)
    {
        // Runtime aliases are judged against the independent bundled canonical
        // variant, never against the display-table row's bare-name label.
        var canonical = ShipNameIndex.Bundled.Find(raw);
        if (canonical is not null)
        {
            if (actual?.RuntimeId != canonical.RuntimeId || actual?.EnglishName != canonical.EnglishName)
                failures.Add("Exact canonical variant identity changed: " + raw);
            return canonical.ChineseName;
        }
        if (actual?.RuntimeId is not null)
        {
            // Existing table aliases may join an exact English/Chinese model;
            // this cannot grant an unrelated edition or manufacturer identity.
            var joined = ShipNameIndex.Bundled.Find(english) ?? ShipNameIndex.Bundled.Find(chinese);
            if (joined is null || actual.RuntimeId != joined.RuntimeId || actual.EnglishName != joined.EnglishName)
                failures.Add("Display table invented or changed a runtime identity: " + raw);
            return joined?.ChineseName ?? chinese;
        }
        if (actual is null) failures.Add("Unresolved display form: " + raw);
        else if (actual.RuntimeId is not null || actual.EnglishName != english)
            failures.Add("Display-only form changed model identity or label: " + raw);
        // A display-only qualified label follows the source table, with no ID.
        return chinese;
    }

    internal static void CheckVariantPolicy(List<string> failures)
    {
        foreach (var model in new[] { "Blade", "Stinger", "Glaive" })
        {
            if (ShipNameIndex.Bundled.Find(model) is not null || GameShipNames.Find(model)?.RuntimeId is not null)
                failures.Add("An ambiguous bare model acquired a runtime identity: " + model);
            var replica = ShipNameIndex.Bundled.Find("ESPR_" + model);
            var qualified = GameShipNames.Find("Esperia " + model);
            if (replica is null || qualified?.RuntimeId != replica.RuntimeId || qualified?.ChineseName != replica.ChineseName)
                failures.Add("Qualified replica must retain its exact canonical variant: " + model);
            foreach (var prefix in new[] { "ESPR_", "VNCL_" })
            {
                var canonical = ShipNameIndex.Bundled.Find(prefix + model);
                if (canonical is not null && GameShipNames.Find(prefix + model) != canonical)
                    failures.Add("Original runtime spelling changed: " + prefix + model);
            }
        }
        if (GameShipNames.Find("Scythe")?.RuntimeId != "VNCL_Scythe" ||
            GameShipNames.Find("Esperia Scythe") is not { RuntimeId: null })
            failures.Add("Selected manufacturer display must not reassign Scythe runtime identity");
        foreach (var unknown in new[] { "Esperia Blade Unreviewed", "VNCL_Blade_Unreviewed", "ESPR_Stinger_Unreviewed" })
            if (GameShipNames.Find(unknown) is not null) failures.Add("Unknown variant inherited an identity: " + unknown);
    }
}
