using System.Text;

namespace StarBridge.HostRuntime.HealthReading;

// One template: a small grayscale/edge image used for normalized matching.
internal sealed class HudTemplate
{
    public int W, H;
    public float[] Data = Array.Empty<float>();
    public float Scale = 1f;
}

// The health-reading model: plus-sign edge templates (three sizes), optional edge templates of the
// icon that replaces the plus sign while suffocating (same three sizes), percent-sign templates and
// the digit CNN weights. It is cut from game HUD images, so it ships as a private resource
// (.private-ops/hud-health/hud-health-v1.bin), never in the public source tree. Without it the
// feature stays unavailable.
//
// File layout (little endian): "SBHH", int32 version (1), int32 block count; each block is
// int32 name length, UTF-8 name, int32 rank, int32[rank] shape, float32[] data.
internal sealed class HudHealthModel
{
    public const string FileName = "hud-health-v1.bin";
    public readonly List<HudTemplate> Plus = new();
    // Optional: the icon that replaces the plus sign while suffocating, in the same three sizes.
    public readonly List<HudTemplate> Alt = new();
    public readonly List<HudTemplate> Pct = new();
    public readonly Dictionary<string, (int[] Shape, float[] Data)> Cnn = new(StringComparer.Ordinal);
    public float R0 = 30f, Thr = 0.45f;

    // The digit network is fixed (HudDigitCnn): 1→16→32→48 channels of 3x3 convolutions, then 144→64→11.
    static readonly (string Key, int[] Shape)[] CnnShapes =
    {
        ("f.0.weight", new[] { 16, 1, 3, 3 }), ("f.0.bias", new[] { 16 }),
        ("f.3.weight", new[] { 32, 16, 3, 3 }), ("f.3.bias", new[] { 32 }),
        ("f.6.weight", new[] { 48, 32, 3, 3 }), ("f.6.bias", new[] { 48 }),
        ("f.10.weight", new[] { 64, 144 }), ("f.10.bias", new[] { 64 }),
        ("f.13.weight", new[] { 11, 64 }), ("f.13.bias", new[] { 11 }),
    };

    public static HudHealthModel Load(string path)
    {
        using var s = File.OpenRead(path);
        return Load(s);
    }

    public static HudHealthModel Load(Stream stream)
    {
        using var r = new BinaryReader(stream, Encoding.UTF8, leaveOpen: true);
        if (Encoding.ASCII.GetString(r.ReadBytes(4)) != "SBHH") throw new InvalidDataException("not a health model");
        int version = r.ReadInt32();
        if (version != 1) throw new InvalidDataException($"unsupported health model version {version}");
        int count = r.ReadInt32();
        if (count is <= 0 or > 4096) throw new InvalidDataException("bad block count");
        var blocks = new Dictionary<string, (int[] Shape, float[] Data)>(StringComparer.Ordinal);
        for (int b = 0; b < count; b++)
        {
            int nameLen = r.ReadInt32();
            if (nameLen is <= 0 or > 256) throw new InvalidDataException("bad block name");
            string name = Encoding.UTF8.GetString(r.ReadBytes(nameLen));
            int rank = r.ReadInt32();
            if (rank is <= 0 or > 4) throw new InvalidDataException("bad block rank");
            var shape = new int[rank]; long n = 1;
            for (int i = 0; i < rank; i++) { shape[i] = r.ReadInt32(); if (shape[i] <= 0 || shape[i] > 4096) throw new InvalidDataException("bad block shape"); n *= shape[i]; }
            if (n > 1_000_000) throw new InvalidDataException("block too large");
            var data = new float[n];
            var bytes = r.ReadBytes((int)n * 4);
            if (bytes.Length != n * 4) throw new InvalidDataException("truncated block");
            Buffer.BlockCopy(bytes, 0, data, 0, bytes.Length);
            foreach (var v in data) if (!float.IsFinite(v)) throw new InvalidDataException($"non-finite value in {name}");
            blocks[name] = (shape, data);
        }
        var m = new HudHealthModel();
        if (!blocks.TryGetValue("plus.scales", out var scales)) throw new InvalidDataException("missing plus scales");
        for (int i = 0; i < scales.Data.Length; i++)
        {
            if (!blocks.TryGetValue($"plus.{i}", out var p) || !Template2D(p.Shape, 8, 96)) throw new InvalidDataException("missing or bad plus template");
            m.Plus.Add(new HudTemplate { H = p.Shape[0], W = p.Shape[1], Data = p.Data, Scale = scales.Data[i] });
        }
        // Any alternate block present means all three must be there and valid (review R8).
        if (blocks.Keys.Any(k => k.StartsWith("alt.", StringComparison.Ordinal)))
            for (int i = 0; i < scales.Data.Length; i++)
            {
                if (!blocks.TryGetValue($"alt.{i}", out var p) || !Template2D(p.Shape, 8, 96)) throw new InvalidDataException("missing or bad alternate template");
                m.Alt.Add(new HudTemplate { H = p.Shape[0], W = p.Shape[1], Data = p.Data, Scale = scales.Data[i] });
            }
        for (int i = 0; blocks.TryGetValue($"pct.{i}", out var p); i++)
        {
            // The percent sign is searched in a 36x92 digit band.
            if (!Template2D(p.Shape, 4, 36) || p.Shape[1] > 92) throw new InvalidDataException("bad percent template");
            m.Pct.Add(new HudTemplate { H = p.Shape[0], W = p.Shape[1], Data = p.Data });
        }
        foreach (var (k, shape) in CnnShapes)
        {
            if (!blocks.TryGetValue("cnn." + k, out var w)) throw new InvalidDataException($"missing {k}");
            if (!w.Shape.SequenceEqual(shape)) throw new InvalidDataException($"{k} has shape [{string.Join(',', w.Shape)}], expected [{string.Join(',', shape)}]");
            m.Cnn[k] = w;
        }
        if (scales.Data.Length != 3 || scales.Data.Any(v => v is < 0.5f or > 2f)) throw new InvalidDataException("bad plus scales");
        if (blocks.TryGetValue("const.r0_thr", out var c) && c.Data.Length >= 2) { m.R0 = c.Data[0]; m.Thr = c.Data[1]; }
        if (m.Plus.Count != 3 || m.Pct.Count == 0) throw new InvalidDataException("incomplete health model");
        if (m.R0 is < 10 or > 80 || m.Thr is <= 0 or >= 1) throw new InvalidDataException("bad model constants");
        return m;
    }

    static bool Template2D(int[] shape, int min, int max) =>
        shape.Length == 2 && shape[0] >= min && shape[0] <= max && shape[1] >= min && shape[1] <= max;
}
