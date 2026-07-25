using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace StarBridge.Desktop;

public static class UpdateManifestSecurity
{
    public const string PayloadVersion = "starbridge-update-manifest-v1";
    public const string TrustedKeyId = "73bfc5146228b248";

    private const string TrustedPublicKeyXml = "<RSAKeyValue><Modulus>3skt8qG3F//HJ1K25byWanhMjVCWP0m/CZYyc5pLoL+aF/HxiK/R/3ZEHn48aWePMLhiwWwBRE19hTYIvPLmjoBSSo1Yt+/gjIJgSrPH21hI0kZ0ogDGGfGYF2XcNoY9eahR/QeIZ8mb3lIkZL5U5a44ykWUWdqUk7i/rVbdAxtOMqVg4tDVJniUbbsDGQNBnVGMW639YdUFepDUqguRQ8bvBMR+L4c9F8i7rFv20ubGxlsxtPSGwhqi5iXgpbYovn9t5qRV9UUblyP+DmgJMd/B8FaWhwR/dipD2oBUaCfP+dbHxYXcrpy4u0vhK4UntTE0iqM7tq5+5R28onn00+5Ump+WocoKKCzflTYTAeCC+XspbjW3cmjuN+AXR/LeUbJaIS4pUj64Njv9F9XjT1tAwU5gwsVCtiNxxz6qvfYipzZFehuGMtzgtbCV1/CrQFzbdeuHkVH45jBBIOanYfpClbNPh6Cm7HvZmgc3hGBtQ3aVMk+R4L4tQ6f3fiTF</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>";

    public static void ValidateAndVerify(UpdateManifest manifest)
    {
        ValidateAndVerify(manifest, TrustedPublicKeyXml, TrustedKeyId);
    }

    public static void ValidateAndVerify(UpdateManifest manifest, string publicKeyXml, string expectedKeyId)
    {
        ValidateRequiredFields(manifest, expectedKeyId);

        byte[] signature;
        try
        {
            signature = Convert.FromBase64String(manifest.Signature!);
        }
        catch (FormatException ex)
        {
            throw new InvalidOperationException("更新清单签名格式无效，已停止更新。", ex);
        }

        using var rsa = RSA.Create();
        rsa.FromXmlString(publicKeyXml);
        if (!rsa.VerifyData(
                Encoding.UTF8.GetBytes(BuildPayload(manifest)),
                signature,
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1))
        {
            throw new InvalidOperationException("更新清单签名验证失败，清单可能已被篡改，已停止更新。");
        }
    }

    public static string BuildPayload(UpdateManifest manifest)
    {
        var notesHash = Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(manifest.Notes ?? string.Empty)))
            .ToLowerInvariant();

        return string.Join('\n',
            PayloadVersion,
            manifest.Version.Trim(),
            manifest.DownloadUrl?.Trim() ?? string.Empty,
            manifest.PackageUrl?.Trim() ?? string.Empty,
            manifest.Required ? "true" : "false",
            manifest.PublishedAt?.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture) ?? string.Empty,
            NormalizeSha256(manifest.DownloadSha256),
            NormalizeSha256(manifest.PackageSha256),
            notesHash);
    }

    public static string NormalizeSha256(string? value)
    {
        return (value ?? string.Empty)
            .Trim()
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .Replace("-", string.Empty, StringComparison.Ordinal)
            .ToLowerInvariant();
    }

    private static void ValidateRequiredFields(UpdateManifest manifest, string expectedKeyId)
    {
        if (string.IsNullOrWhiteSpace(manifest.Version) || manifest.PublishedAt is null)
        {
            throw new InvalidOperationException("更新清单缺少版本或发布时间，已停止更新。");
        }

        ValidateArtifact(manifest.DownloadUrl, manifest.DownloadSha256, "完整安装包");
        ValidateArtifact(manifest.PackageUrl, manifest.PackageSha256, "应用内更新包");
        if (string.IsNullOrWhiteSpace(manifest.DownloadUrl) && string.IsNullOrWhiteSpace(manifest.PackageUrl))
        {
            throw new InvalidOperationException("更新清单没有提供可用的更新包，已停止更新。");
        }

        if (!string.Equals(manifest.SignatureKeyId, expectedKeyId, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("更新清单使用了不受信任的签名密钥，已停止更新。");
        }

        if (string.IsNullOrWhiteSpace(manifest.Signature))
        {
            throw new InvalidOperationException("更新清单缺少数字签名，已停止更新。");
        }
    }

    private static void ValidateArtifact(string? url, string? sha256, string label)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            if (!string.IsNullOrWhiteSpace(sha256))
            {
                throw new InvalidOperationException($"{label}没有下载地址，但清单包含散列值，已停止更新。");
            }

            return;
        }

        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"{label}下载地址不是安全的 HTTPS 地址，已停止更新。");
        }

        var normalized = NormalizeSha256(sha256);
        if (normalized.Length != 64 || normalized.Any(character => !Uri.IsHexDigit(character)))
        {
            throw new InvalidOperationException($"{label}缺少有效的 SHA-256，已停止更新。");
        }
    }
}
