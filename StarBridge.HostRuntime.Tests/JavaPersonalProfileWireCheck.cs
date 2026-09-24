using System.Net;
using System.Text;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;

// Opt-in, offline check of the synthetic fixture emitted by the Java runtime
// serializer test. No session owner, vault, network call or user profile writes.
internal static class JavaPersonalProfileWireCheck
{
    internal static async Task<int> RunAsync(string path)
    {
        using var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(await File.ReadAllTextAsync(path),
                Encoding.UTF8, "application/json")
        };
        var profile = await new ScmHttpClient().ReadJsonAsync<PersonalProfileDocumentContract>(
            response, "synthetic wire check");
        if (profile.SchemaVersion != 3 ||
            profile.Identity?.Callsign != "Synthetic Citizen" ||
            profile.Identity.GameId != "Synthetic-Handle" ||
            profile.UpdatedAt != DateTimeOffset.UnixEpoch ||
            profile.Revision != 0 ||
            PersonalProfileContractPolicy.Normalize(profile.Content).Modules.Length != 0)
        {
            // Never print file content, arbitrary exception text or field values.
            Console.WriteLine("FAIL|Java runtime JSON -> Native Host profile contract");
            return 1;
        }
        Console.WriteLine("PASS|Java runtime JSON -> Native Host profile contract");
        return 0;
    }
}
