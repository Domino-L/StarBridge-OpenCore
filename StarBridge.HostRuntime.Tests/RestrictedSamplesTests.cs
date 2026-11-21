using System.Text.Json;

internal static class RestrictedSamplesTests
{
    internal static Task MalformedSampleFails()
    {
        var directory = Directory.CreateTempSubdirectory("sb-restricted-sample-");
        try
        {
            const string name = "synthetic.json";
            var path = Path.Combine(directory.FullName, name);
            File.WriteAllText(path, "{");
            try
            {
                using var document = JsonDocument.Parse(RestrictedSamples.ReadFile(path, name));
            }
            catch (JsonException)
            {
                return Task.CompletedTask;
            }
            catch (RestrictedSampleAbsentException error)
            {
                // The outer Host runner treats this exception as a skip.
                throw new InvalidOperationException("A present malformed sample must fail, not skip.", error);
            }

            throw new InvalidOperationException("The malformed sample unexpectedly parsed.");
        }
        finally
        {
            directory.Delete(recursive: true);
        }
    }
}
