namespace StarBridge.Core.State;

internal static class ImmediateVehicleExitCatalog
{
    private static readonly HashSet<string> ConfirmedVehicleCodes = new(StringComparer.OrdinalIgnoreCase)
    {
        // Aegis
        "AEGSEclipse",
        "AEGSGladius",
        "AEGSGladiusDunlevy",
        "AEGSGladiusPIR",
        "AEGSGladiusValiant",
        "AEGSSabre",
        "AEGSSabreComet",
        "AEGSSabreFirebird",
        "AEGSSabrePeregrine",
        "AEGSSabrePeregrineCollectorCompetition",
        "AEGSSabreRaven",

        // Anvil
        "ANVLArrow",
        "ANVLGladiator",
        "ANVLHawk",
        "ANVLHornetF7A",
        "ANVLHornetF7AMk2",
        "ANVLHornetF7AMk2PYAMExec",
        "ANVLHornetF7C",
        "ANVLHornetF7CM",
        "ANVLHornetF7CMHeartseeker",
        "ANVLHornetF7CMHeartseekerMk2",
        "ANVLHornetF7CMMk2",
        "ANVLHornetF7CR",
        "ANVLHornetF7CRMk2",
        "ANVLHornetF7CS",
        "ANVLHornetF7CSMk2",
        "ANVLHornetF7CMk2",
        "ANVLHornetF7CWildfire",
        "ANVLHurricane",
        "ANVLLightningF8C",
        "ANVLLightningF8CCollectorMilitary",
        "ANVLLightningF8CCollectorStealth",
        "ANVLLightningF8CExec",
        "ANVLLightningF8CPYAMExec",

        // Argo
        "ARGOATLS",
        "ARGOATLSGEO",
        "ARGOATLSGEOIKTI",
        "ARGOATLSIKTI",
        "ARGOATLSIKTIRad",

        // Consolidated Outland
        "CNOUHoverQuad",
        "CNOUMustangAlpha",
        "CNOUMustangAlphaCitizenCon2018",
        "CNOUMustangDelta",
        "CNOUMustangGamma",
        "CNOUMustangOmega",

        // Crusader
        "CRUSStarfighterInferno",
        "CRUSStarfighterInfernoCollectorMilitary",
        "CRUSStarfighterIon",
        "CRUSStarfighterIonCollectorStealth",

        // Drake
        "DRAKBuccaneer",
        "DRAKDragonfly",
        "DRAKDragonflyPink",
        "DRAKDragonflyYellow",
        "DRAKPitbull",

        // Esperia and Vanduul
        "ESPRGlaive",
        "ESPRTalon",
        "ESPRTalonShrike",
        "VNCLGlaive",
        "VNCLScythe",

        // Greycat and Grey's Market
        "GLSNBasher",
        "GRINROC",
        "GRINROCDS",

        // Kruger
        "KRIGL21Wolf",
        "KRIGL21WolfCollectorMilitary",
        "KRIGL21WolfCollectorStealth",
        "KRIGL22AlphaWolf",
        "KRIGL22AlphaWolfCollectorMilitary",
        "KRIGP52Merlin",
        "KRIGP72Archimedes",
        "KRIGP72ArchimedesEmerald",

        // Mirai and MISC
        "MISCRazor",
        "MISCRazorEX",
        "MISCRazorLX",
        "MRAIPulse",
        "MRAIPulseLX",
        "MiscFury",
        "MiscFuryLX",
        "MiscFuryMiru",

        // Origin
        "ORIG85X",
        "ORIGm50",
        "ORIGX1",
        "ORIGX1Force",
        "ORIGX1Velocity",

        // RSI
        "RSIAuroraCL",
        "RSIAuroraES",
        "RSIAuroraLN",
        "RSIAuroraLX",
        "RSIAuroraMR",
        "RSIAuroraSE",
        "RSISalvation",
        "RSIScorpius",
        "RSIScorpiusAntares",
        "RSIScorpiusCollectorStealth",
        "RSIScorpiusInterdiction",

        // Tumbril
        "TMBLCyclone",
        "TMBLCycloneAA",
        "TMBLCycloneMT",
        "TMBLCycloneRC",
        "TMBLCycloneRN",
        "TMBLCycloneTR",

        // Aopoa
        "XIANNox",
        "XIANNoxKue",
        "XIANScout",
        "XNAASantokYai"
    };

    public static bool Contains(string? vehicleCode)
    {
        if (string.IsNullOrWhiteSpace(vehicleCode))
        {
            return false;
        }

        var normalized = new string(vehicleCode
            .Where(char.IsLetterOrDigit)
            .ToArray());

        return ConfirmedVehicleCodes.Contains(normalized);
    }
}
