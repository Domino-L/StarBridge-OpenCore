using StarBridge.Core.ShipMedia;

namespace StarBridge.Core.Tests;

internal static class ShipImageVersionTests
{
    internal static void RunAll()
    {
        var id = new string('b', 32); var hash = new string('c', 64);
        var golden = ShipImageVersion.Compute(id, hash, .25, .75, 1.25);
        Check(golden == "700c35d9d8ab828e40d701350eb360a1244aeec01f0ffbc6b3043673c606a8e6", "Exact original community JSON bytes preserve fixed image version");
        Check(ShipImageVersion.Compute(new string('d', 32), hash, .25, .75, 1.25) != golden &&
            ShipImageVersion.Compute(id, new string('d', 64), .25, .75, 1.25) != golden &&
            ShipImageVersion.Compute(id, hash, .26, .75, 1.25) != golden &&
            ShipImageVersion.Compute(id, hash, .25, .76, 1.25) != golden &&
            ShipImageVersion.Compute(id, hash, .25, .75, 1.26) != golden,
            "Media, content and each exact crop component participate in the version");
        var negativeZero = BitConverter.Int64BitsToDouble(long.MinValue);
        Check(ShipImageVersion.Compute(id, hash, negativeZero, 0, 1) != ShipImageVersion.Compute(id, hash, 0, 0, 1) &&
            ShipImageVersion.Compute(id, hash, 0, negativeZero, 1) != ShipImageVersion.Compute(id, hash, 0, 0, 1),
            "Pure legacy-compatible version function preserves negative-zero bytes; only new grant validation rejects them");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); Console.WriteLine("PASS " + message); }
}
