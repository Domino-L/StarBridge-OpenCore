using System.Security.Cryptography;
using System.Text;

namespace StarBridge.Core.Identity;

public sealed record OAuthPkceParameters(
    string CodeVerifier,
    string CodeChallenge,
    string State)
{
    public static OAuthPkceParameters Create()
    {
        var verifier = Base64UrlEncode(RandomNumberGenerator.GetBytes(64));
        return new OAuthPkceParameters(
            verifier,
            CreateChallenge(verifier),
            Base64UrlEncode(RandomNumberGenerator.GetBytes(32)));
    }

    public static bool Verify(string codeVerifier, string expectedChallenge)
    {
        if (string.IsNullOrWhiteSpace(codeVerifier) || string.IsNullOrWhiteSpace(expectedChallenge))
        {
            return false;
        }

        var actual = Encoding.ASCII.GetBytes(CreateChallenge(codeVerifier));
        var expected = Encoding.ASCII.GetBytes(expectedChallenge);
        return actual.Length == expected.Length &&
               CryptographicOperations.FixedTimeEquals(actual, expected);
    }

    private static string CreateChallenge(string verifier) =>
        Base64UrlEncode(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));

    private static string Base64UrlEncode(byte[] value) =>
        Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
}