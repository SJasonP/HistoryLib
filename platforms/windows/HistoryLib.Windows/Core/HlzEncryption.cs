using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Modes;
using Org.BouncyCastle.Crypto.Parameters;

namespace HistoryLib.Windows.Core;

internal static class HlzEncryption
{
    private static readonly byte[] Magic = [ (byte)'H', (byte)'L', (byte)'Z', (byte)'E', (byte)'N', (byte)'C', 0, 1 ];
    private const int HeaderSize = 66, ChunkSize = 1_048_576, TagBytes = 16;
    public static byte[] Encrypt(byte[] zip, string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16); var nonce = RandomNumberGenerator.GetBytes(24); var header = BuildHeader(salt, nonce); var key = Derive(password, salt); using var output = new MemoryStream(); output.Write(header);
        var offset = 0; do { var size = Math.Min(ChunkSize, zip.Length - offset); var plain = zip.AsSpan(offset, size).ToArray(); offset += size; var final = offset >= zip.Length; var frame = Seal(key, nonce, header, plain, final ? (byte)3 : (byte)0); WriteU32(output, frame.Length); output.Write(frame); Increment(nonce); } while (offset < zip.Length || zip.Length == 0 && output.Length == HeaderSize);
        return output.ToArray();
    }
    public static byte[] Decrypt(byte[] input, string password)
    {
        if (input.Length < HeaderSize || !input.AsSpan(0, 8).SequenceEqual(Magic)) throw new InvalidDataException("Invalid HLZENC header."); var header = input.AsSpan(0, HeaderSize).ToArray(); ValidateHeader(header); var key = Derive(password, header.AsSpan(26, 16).ToArray()); var nonce = header.AsSpan(42, 24).ToArray(); using var output = new MemoryStream(); var offset = HeaderSize; var finalSeen = false;
        while (offset < input.Length) { if (offset + 4 > input.Length) throw new InvalidDataException("Truncated HLZENC frame."); var length = BinaryPrimitives.ReadInt32BigEndian(input.AsSpan(offset, 4)); offset += 4; if (length < 1 + TagBytes || length > 1 + ChunkSize + TagBytes) throw new InvalidDataException("Invalid HLZENC frame."); if (offset + length > input.Length) throw new InvalidDataException("Truncated HLZENC frame."); var frame = input.AsSpan(offset, length).ToArray(); offset += length; var tag = frame[0]; if (tag != 0 && tag != 3) throw new InvalidDataException("Unsupported HLZENC frame tag."); output.Write(Open(key, nonce, header, frame.AsSpan(1).ToArray())); if (tag == 3) { finalSeen = true; if (offset != input.Length) throw new InvalidDataException("Trailing HLZENC bytes."); } else Increment(nonce); }
        if (!finalSeen) throw new InvalidDataException("Missing HLZENC final frame."); return output.ToArray();
    }
    private static byte[] Derive(string password, byte[] salt) { var p = new Argon2Parameters.Builder(Argon2Parameters.Argon2id).WithSalt(salt).WithIterations(2).WithMemoryAsKB(64 * 1024).WithParallelism(1).Build(); var g = new Argon2BytesGenerator(); g.Init(p); var key = new byte[32]; g.GenerateBytes(Encoding.UTF8.GetBytes(password.Normalize(NormalizationForm.FormC)), key); return key; }
    private static byte[] Seal(byte[] key, byte[] nonce, byte[] aad, byte[] plain, byte tag) { var c = new Org.BouncyCastle.Crypto.Modes.ChaCha20Poly1305(); c.Init(true, new AeadParameters(new KeyParameter(HChaCha(key, nonce)), 128, ShortNonce(nonce), aad)); var encrypted = Run(c, plain); var frame = new byte[encrypted.Length + 1]; frame[0] = tag; encrypted.CopyTo(frame, 1); return frame; }
    private static byte[] Open(byte[] key, byte[] nonce, byte[] aad, byte[] cipher) { var c = new Org.BouncyCastle.Crypto.Modes.ChaCha20Poly1305(); c.Init(false, new AeadParameters(new KeyParameter(HChaCha(key, nonce)), 128, ShortNonce(nonce), aad)); try { return Run(c, cipher); } catch (CryptoException ex) { throw new InvalidDataException("HLZENC authentication failed.", ex); } }
    private static byte[] Run(Org.BouncyCastle.Crypto.Modes.ChaCha20Poly1305 c, byte[] input) { var output = new byte[c.GetOutputSize(input.Length)]; var count = c.ProcessBytes(input, 0, input.Length, output, 0); count += c.DoFinal(output, count); return output[..count]; }
    private static byte[] ShortNonce(byte[] nonce) { var n = new byte[12]; Array.Copy(nonce, 16, n, 4, 8); return n; }
    private static byte[] HChaCha(byte[] key, byte[] nonce)
    {
        var s = new uint[16]; s[0] = 0x61707865; s[1] = 0x3320646e; s[2] = 0x79622d32; s[3] = 0x6b206574; for (var i = 0; i < 8; i++) s[4 + i] = BinaryPrimitives.ReadUInt32LittleEndian(key.AsSpan(i * 4, 4)); for (var i = 0; i < 4; i++) s[12 + i] = BinaryPrimitives.ReadUInt32LittleEndian(nonce.AsSpan(i * 4, 4));
        static uint R(uint v, int c) => (v << c) | (v >> (32 - c)); static void Q(uint[] x, int a, int b, int c, int d) { x[a] += x[b]; x[d] = R(x[d] ^ x[a], 16); x[c] += x[d]; x[b] = R(x[b] ^ x[c], 12); x[a] += x[b]; x[d] = R(x[d] ^ x[a], 8); x[c] += x[d]; x[b] = R(x[b] ^ x[c], 7); }
        for (var i = 0; i < 10; i++) { Q(s, 0, 4, 8, 12); Q(s, 1, 5, 9, 13); Q(s, 2, 6, 10, 14); Q(s, 3, 7, 11, 15); Q(s, 0, 5, 10, 15); Q(s, 1, 6, 11, 12); Q(s, 2, 7, 8, 13); Q(s, 3, 4, 9, 14); }
        var output = new byte[32]; for (var i = 0; i < 4; i++) BinaryPrimitives.WriteUInt32LittleEndian(output.AsSpan(i * 4, 4), s[i]); for (var i = 0; i < 4; i++) BinaryPrimitives.WriteUInt32LittleEndian(output.AsSpan((i + 4) * 4, 4), s[12 + i]); return output;
    }
    private static byte[] BuildHeader(byte[] salt, byte[] nonce) { var h = new byte[HeaderSize]; Magic.CopyTo(h, 0); h[8] = 2; h[9] = 3; BinaryPrimitives.WriteInt32BigEndian(h.AsSpan(10, 4), 2); BinaryPrimitives.WriteInt64BigEndian(h.AsSpan(14, 8), 64L * 1024 * 1024); BinaryPrimitives.WriteInt32BigEndian(h.AsSpan(22, 4), ChunkSize); salt.CopyTo(h, 26); nonce.CopyTo(h, 42); return h; }
    private static void ValidateHeader(byte[] h) { if (h[8] != 2 || h[9] != 3 || BinaryPrimitives.ReadInt32BigEndian(h.AsSpan(10, 4)) != 2 || BinaryPrimitives.ReadInt64BigEndian(h.AsSpan(14, 8)) != 64L * 1024 * 1024 || BinaryPrimitives.ReadInt32BigEndian(h.AsSpan(22, 4)) != ChunkSize) throw new InvalidDataException("Unsupported HLZENC parameters."); }
    private static void WriteU32(Stream s, int value) { Span<byte> b = stackalloc byte[4]; BinaryPrimitives.WriteInt32BigEndian(b, value); s.Write(b); }
    private static void Increment(byte[] n) { for (var i = n.Length - 1; i >= 0; i--) { if (++n[i] != 0) break; } }
}
