using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.Ships;

// Public model facts only. Never an inventory, ownership, loadout editor or image source.
internal sealed record ShipSpecificationField(string Key, string Value, string Unit = "");
internal sealed record ShipSpecificationGroup(string Key, IReadOnlyList<ShipSpecificationField> Fields);
internal sealed record ShipSpecificationComponent(string Group, string Name, string? ChineseName,
    string? Size, string? Grade, bool? Editable);
internal sealed record ShipSpecifications(string State, string ModelName, string? DataVersion = null,
    DateTimeOffset? FetchedAt = null, bool Stale = false,
    IReadOnlyList<ShipSpecificationGroup>? Groups = null,
    IReadOnlyList<ShipSpecificationComponent>? Components = null,
    string? PaintBaseModel = null, string? BundleBaseModel = null);

internal static class ShipSpecificationProjection
{
    // Units are explicit; absent/null is not zero. Unrecognised schema fields remain outside the wire.
    private static readonly (string Group, string Path, string Unit)[] Metrics = [
        ("overview", "crew", ""), ("overview", "seats", ""), ("overview", "weaponCrew", ""),
        ("overview", "mass", "kg"), ("overview", "cargo", "SCU"),
        ("overview", "length", "m"), ("overview", "width", "m"), ("overview", "height", "m"),
        ("flight", "flight.speed.scm", "m/s"), ("flight", "flight.speed.max", "m/s"),
        ("flight", "flight.speed.boostForward", "m/s"), ("flight", "flight.speed.boostBackward", "m/s"),
        ("flight", "flight.maneuvering.pitch", "°/s"), ("flight", "flight.maneuvering.yaw", "°/s"),
        ("flight", "flight.maneuvering.roll", "°/s"), ("flight", "flight.maneuvering.pitchBoosted", "°/s"),
        ("flight", "flight.maneuvering.yawBoosted", "°/s"), ("flight", "flight.maneuvering.rollBoosted", "°/s"),
        ("flight", "flight.timing.zeroToScm", "s"), ("flight", "flight.timing.zeroToMax", "s"),
        ("flight", "flight.timing.scmToZero", "s"), ("flight", "flight.timing.maxToZero", "s"),
        ("flight", "flight.acceleration.forward", "m/s²"), ("flight", "flight.acceleration.backward", "m/s²"),
        ("flight", "flight.acceleration.up", "m/s²"), ("flight", "flight.acceleration.down", "m/s²"),
        ("flight", "flight.acceleration.strafe", "m/s²"),
        ("defense", "hullHealth", "HP"), ("defense", "shield.hp", "HP"),
        ("defense", "shield.regen", "HP/s"), ("defense", "armor.health", "HP"),
        ("defense", "armor.damageMultipliers.energy", "×"), ("defense", "armor.damageMultipliers.physical", "×"),
        ("defense", "distortionPool", ""),
        ("weapons", "dps.pilotDps", "DPS"), ("weapons", "dps.turretDps", "DPS"),
        ("weapons", "missiles", ""), ("weapons", "torpedoes", ""),
        ("weapons", "countermeasures.decoy.ammo", ""), ("weapons", "countermeasures.noise.ammo", ""),
        ("propulsion", "hydrogenFuel", ""), ("propulsion", "propulsion.fuelIntakeRate", ""),
        ("propulsion", "propulsion.maneuveringTimeTillEmpty", "s"),
        ("quantum", "quantum.fuelCapacity", ""), ("quantum", "quantum.speed", "m/s"),
        ("quantum", "quantum.range", "m"),
        ("quantum", "quantum.spoolTime", "s"), ("quantum", "quantum.cooldown", "s"),
        ("signal", "signal.emission.emQuantum", ""), ("signal", "signal.emission.emShields", ""),
        ("signal", "signal.emission.irQuantum", ""), ("signal", "signal.emission.irShields", ""),
        ("signal", "signal.crossSection.x", ""), ("signal", "signal.crossSection.y", ""),
        ("signal", "signal.crossSection.z", ""),
        ("radar", "radar.size", ""), ("radar", "radar.count", ""), ("radar", "radar.cooldown", "s"),
        ("insurance", "insurance.expeditedCost", "aUEC")
    ];
    private static readonly HashSet<string> ComponentGroups = new(StringComparer.Ordinal) {
        "weapons", "turrets", "missiles", "missileRacks", "shields", "shieldGenerators", "coolers",
        "powerPlants", "powerplants", "quantumDrives", "quantumDrive", "radars", "radar", "thrusters",
        "flightControllers", "lifeSupportGenerators"
    };

    internal static ShipSpecifications Project(JsonElement item, string model, DateTimeOffset now)
    {
        var attrs = At(item, "extendedAttrs");
        if (At(item, "itemType").ValueKind != JsonValueKind.Number ||
            At(item, "itemType").GetInt32() != 1 || attrs.ValueKind != JsonValueKind.Object)
            throw new JsonException("Not a vehicle specification.");
        var groups = new List<ShipSpecificationGroup>();
        foreach (var group in Metrics.GroupBy(x => x.Group))
        {
            var fields = new List<ShipSpecificationField>();
            foreach (var metric in group)
            {
                var value = At(attrs, metric.Path);
                if (value.ValueKind == JsonValueKind.Undefined && metric.Path is "length" or "width" or "height")
                    value = At(attrs, "dimensions." + metric.Path);
                if (Number(value) is { } text) fields.Add(new(metric.Path, text, metric.Unit));
            }
            if (fields.Count > 0) groups.Add(new(group.Key, fields));
        }
        var components = new List<ShipSpecificationComponent>();
        void AddPart(string group, JsonElement part, int depth)
        {
            if (depth > 4 || components.Count >= 240 || part.ValueKind != JsonValueKind.Object) return;
            var name = Text(part, "equipped");
            if (name is not null)
            {
                var editable = At(part, "editable");
                var kind = Text(part, "type");
                components.Add(new(kind?.StartsWith("WeaponGun.", StringComparison.Ordinal) == true ? "weapons" : group,
                    name, Text(part, "equipped_cn"), Number(At(part, "size")), Text(part, "grade"),
                    editable.ValueKind is JsonValueKind.True or JsonValueKind.False ? editable.GetBoolean() : null));
            }
            var children = At(part, "children");
            if (children.ValueKind == JsonValueKind.Array)
                foreach (var child in children.EnumerateArray().Take(80)) AddPart(group, child, depth + 1);
        }
        var hardpoints = At(attrs, "hardpoints");
        if (hardpoints.ValueKind == JsonValueKind.Object)
            foreach (var group in hardpoints.EnumerateObject().Where(p => ComponentGroups.Contains(p.Name)))
            {
                if (group.Value.ValueKind != JsonValueKind.Array) continue;
                foreach (var part in group.Value.EnumerateArray().Take(80))
                {
                    AddPart(group.Name, part, 0);
                }
            }
        return new("ready", model, Text(item, "dataVersion"), now, false, groups, components);
    }

    internal static JsonElement At(JsonElement value, string path)
    {
        foreach (var key in path.Split('.'))
            if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty(key, out value)) return default;
        return value;
    }
    internal static string? Text(JsonElement value, string path) => At(value, path) is var field &&
        field.ValueKind == JsonValueKind.String && field.GetString()?.Trim() is { Length: > 0 and <= 240 } text &&
        !text.Any(char.IsControl) ? text : null;
    private static string? Number(JsonElement value) => value.ValueKind == JsonValueKind.Number &&
        value.TryGetDecimal(out var number) && number >= 0 ? number.ToString("0.####", CultureInfo.InvariantCulture) : null;
}
