namespace StarBridge.HostRuntime.Ships;

// Parameter-source choices only. Does not merge inventory, runtime identities, media or ownership.
internal sealed record ScmShipSpecificationMapping(string SourceRuntime, string? PaintBaseModel = null,
    string? RequiredRole = null, string? ParameterModel = null, string? RequiredOriginalName = null,
    string? BundleBaseModel = null);

internal static class ScmShipSpecificationMappings
{
    private static readonly IReadOnlyDictionary<string, ScmShipSpecificationMapping> Rules = Build();
    internal static ScmShipSpecificationMapping? Find(string original, string? runtime, string english)
    {
        // A deliberately selected functional module outranks an older catalogue alias.
        foreach (var alias in new[] { original, runtime })
            if (alias is not null && Rules.TryGetValue(Key(alias), out var rule)) return rule;
        // An explicit runtime already selects a variant. Its generic display
        // name must not silently opt into a default-loadout policy.
        if (runtime is not null && Key(original) == Key(runtime)) return null;
        return Rules.TryGetValue(Key(english), out var displayRule) ? displayRule : null;
    }

    private static string Key(string value) => string.Concat(value.Where(char.IsLetterOrDigit)).ToUpperInvariant();
    private static IReadOnlyDictionary<string, ScmShipSpecificationMapping> Build()
    {
        var rules = new Dictionary<string, ScmShipSpecificationMapping>(StringComparer.Ordinal);
        void Add(ScmShipSpecificationMapping rule, params string[] aliases)
        {
            foreach (var alias in aliases) rules.Add(Key(alias), rule);
        }
        // Maintainer confirmed unspecified F7A is Mk I; Mk II and PYAM remain independent.
        Add(new("ANVL_Hornet_F7A_Mk1", ParameterModel: "F7A Hornet Mk I"), "ANVL_Hornet_F7A", "F7A", "F7A Hornet", "F7A Hornet Mk I", "F7A Hornet Mk1", "Hornet F7A");
        // Exact current public records, including extendedAttrs.originalName. No generic GS stripping.
        foreach (var variant in new[] { "CL", "ES", "LN", "LX", "MR", "SE" })
            Add(new("RSI_Aurora_GS_" + variant), "RSI_Aurora_" + variant,
                "Aurora " + variant, "Aurora Mk I " + variant, "RSI Aurora Mk I " + variant);
        Add(new("GAMA_Tyilui"), "Tyilui", "Gatac Tyilui", "GAMA_Tyilui", "盖塔克 缇伦");
        Add(new("GAMA_Railen"), "Railen", "Gatac Railen", "GAMA_Railen", "XIAN_Railen", "盖塔克 锐伦");

        // Explicitly verified cosmetic-only editions. All other editions keep their exact model.
        Add(new("ARGO_MOLE", "MOLE"), "ARGO_Mole_Carbon", "Mole Carbon", "Argo Mole Carbon Edition", "MOLE Carbon Edition");
        Add(new("ARGO_MOLE", "MOLE"), "ARGO_Mole_Talus", "Mole Talus", "Argo Mole Talus Edition", "MOLE Talus Edition");
        Add(new("ANVL_Valkyrie", "Valkyrie"), "ANVL_Valkyrie_CitizenCon", "Valkyrie CitizenCon", "Valkyrie Liberator Edition", "Valkyrie Liberator");
        Add(new("CNOU_Mustang_Alpha", "Mustang Alpha"), "CNOU_Mustang_Alpha_CitizenCon2018", "Mustang Alpha CitizenCon2018", "Mustang Alpha Vindicator");

        // SCM abbreviates Explorer as Origin 600i. Verified role and 44 SCU against
        // the separate 20-SCU Touring record and the RSI matrix. Never fall back across modules.
        Add(new("ORIG_600i", RequiredRole: "Expedition", ParameterModel: "600i Explorer"), "600i Explorer", "Origin 600i Explorer", "600i Exploration");
        Add(new("ORIG_600i_Touring", RequiredRole: "Luxury Touring", ParameterModel: "600i Touring"), "600i Touring", "Origin 600i Touring", "ORIG_600i_Touring");

        // Maintainer selected the Esperia reproductions. SCM retains VNCL keywords,
        // but extendedAttrs.originalName identifies the actual Esperia parameter record.
        foreach (var model in new[] { "Blade", "Glaive", "Stinger" })
            Add(new("VNCL_" + model, ParameterModel: "Esperia " + model,
                RequiredOriginalName: "Esperia " + model), model, "Esperia " + model, "ESPR_" + model);
        // Bundles use their respective carrier's default parameters; C8X remains
        // bundle information, not a second vessel merged into carrier statistics.
        Add(new("ANVL_Carrack", ParameterModel: "Carrack w/C8X", BundleBaseModel: "Carrack"),
            "Carrack w/C8X", "Anvil Carrack w/C8X");
        Add(new("ANVL_Carrack_Expedition", ParameterModel: "Carrack Expedition w/C8X", BundleBaseModel: "Carrack Expedition"),
            "Carrack Expedition w/C8X", "Anvil Carrack Expedition w/C8X");
        Add(new("RSI_Skylark"), "Skylark", "RSI Skylark");
        Add(new("KRIG_S65_Stingray"), "S-65 Stingray", "Kruger S-65 Stingray", "KRIG_S65_Stingray");
        return rules;
    }
}
