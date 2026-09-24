namespace StarBridge.HostRuntime.Updates;

/// <summary>Validates startup evidence before an external coordinator accepts it.
/// This is not permission to uninstall WPF: consent, installation ownership and
/// data compatibility must be checked separately by the migration coordinator.</summary>
internal static class FlutterStartupReceiptValidator
{
    internal static void RequireMatch(FlutterUpdateStartupReceipt receipt,
        string expectedNonce, string expectedVersion, int expectedClientProcessId)
    {
        if (expectedNonce.Length != 64 || expectedNonce.Any(c => !Uri.IsHexDigit(c)) ||
            expectedClientProcessId <= 0 || !Version.TryParse(expectedVersion, out var expected) ||
            !Version.TryParse(receipt.Version, out var actual) || actual != expected ||
            !string.Equals(receipt.Nonce, expectedNonce, StringComparison.Ordinal) ||
            receipt.ClientProcessId != expectedClientProcessId ||
            receipt.HostProcessId <= 0 || receipt.HostProcessId == expectedClientProcessId ||
            receipt.BridgeProtocol != 1 || !receipt.FirstFrameRendered || !receipt.HostReady)
            throw new InvalidDataException("Startup receipt does not confirm the expected client.");
    }
}
