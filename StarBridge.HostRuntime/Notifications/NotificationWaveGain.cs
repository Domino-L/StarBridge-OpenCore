namespace StarBridge.HostRuntime.Notifications;

using System.Buffers.Binary;

// Gain is applied to a private playback copy, never to a device's global volume.
internal static class NotificationWaveGain
{
    internal static byte[] Apply(byte[] source, double gain)
    {
        if (!double.IsFinite(gain) || gain is < 0 or > 1 || source.Length < 44 || source.Length > 8 * 1024 * 1024 ||
            !source.AsSpan(0, 4).SequenceEqual("RIFF"u8) || !source.AsSpan(8, 4).SequenceEqual("WAVE"u8) ||
            BinaryPrimitives.ReadUInt32LittleEndian(source.AsSpan(4)) != source.Length - 8) throw new InvalidDataException();
        var copy = (byte[])source.Clone();
        int bits = 0, channels = 0, dataOffset = 0, dataLength = 0;
        for (var offset = 12; offset < copy.Length;) {
            if (copy.Length - offset < 8) throw new InvalidDataException();
            var length = BinaryPrimitives.ReadUInt32LittleEndian(copy.AsSpan(offset + 4));
            if (length > copy.Length - offset - 8) throw new InvalidDataException();
            var payload = copy.AsSpan(offset + 8, (int)length);
            if (copy.AsSpan(offset, 4).SequenceEqual("fmt "u8)) {
                if (bits != 0 || length < 16) throw new InvalidDataException();
                var format = BinaryPrimitives.ReadUInt16LittleEndian(payload);
                channels = BinaryPrimitives.ReadUInt16LittleEndian(payload[2..]);
                bits = BinaryPrimitives.ReadUInt16LittleEndian(payload[14..]);
                if (channels is not (1 or 2) || bits is not (16 or 24) ||
                    BinaryPrimitives.ReadUInt16LittleEndian(payload[12..]) != channels * bits / 8) throw new InvalidDataException();
                if (format == 0xfffe) {
                    // Released 24-bit cues use WAVE_FORMAT_EXTENSIBLE. Accept only
                    // integer PCM with full-width samples; never reinterpret float/compressed audio.
                    if (length < 40 || BinaryPrimitives.ReadUInt16LittleEndian(payload[16..]) < 22 ||
                        BinaryPrimitives.ReadUInt16LittleEndian(payload[16..]) > length - 18 ||
                        BinaryPrimitives.ReadUInt16LittleEndian(payload[18..]) != bits ||
                        new Guid(payload.Slice(24, 16)) != new Guid("00000001-0000-0010-8000-00aa00389b71"))
                        throw new InvalidDataException();
                } else if (format != 1) throw new InvalidDataException();
            } else if (copy.AsSpan(offset, 4).SequenceEqual("data"u8)) {
                if (dataOffset != 0) throw new InvalidDataException();
                dataOffset = offset + 8; dataLength = (int)length;
            }
            offset = checked(offset + 8 + (int)length + ((int)length & 1));
        }
        if (bits == 0 || dataOffset == 0 || dataLength == 0 || dataLength % (channels * bits / 8) != 0) throw new InvalidDataException();
        for (int offset = dataOffset; offset < dataOffset + dataLength; offset += bits / 8) {
            if (bits == 16) {
                var sample = BinaryPrimitives.ReadInt16LittleEndian(copy.AsSpan(offset));
                BinaryPrimitives.WriteInt16LittleEndian(copy.AsSpan(offset), (short)Math.Round(sample * gain));
            } else {
                var sample = copy[offset] | copy[offset + 1] << 8 | copy[offset + 2] << 16;
                if ((sample & 0x800000) != 0) sample |= unchecked((int)0xff000000);
                var scaled = (int)Math.Round(sample * gain);
                copy[offset] = (byte)scaled; copy[offset + 1] = (byte)(scaled >> 8); copy[offset + 2] = (byte)(scaled >> 16);
            }
        }
        return copy;
    }
}
