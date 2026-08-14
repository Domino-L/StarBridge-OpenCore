namespace StarBridge.Desktop;

internal enum FleetExternalContactPublicationMode
{
    Empty,
    Public,
    LegacyPrivate
}

internal static class FleetExternalContactPublication
{
    internal static bool ShouldPublish(IEnumerable<FleetExternalContactRow> contacts)
    {
        ArgumentNullException.ThrowIfNull(contacts);
        return contacts.Any(contact => !string.IsNullOrWhiteSpace(contact.Value));
    }

    internal static FleetExternalContactPublicationMode ResolveLoadedMode(
        bool isCurrentlyPublished,
        IEnumerable<FleetExternalContactRow> contacts)
    {
        if (!ShouldPublish(contacts))
        {
            return FleetExternalContactPublicationMode.Empty;
        }

        return isCurrentlyPublished
            ? FleetExternalContactPublicationMode.Public
            : FleetExternalContactPublicationMode.LegacyPrivate;
    }

    internal static bool ResolveOnSave(
        FleetExternalContactPublicationMode loadedMode,
        bool legacyPublicationConfirmed,
        IEnumerable<FleetExternalContactRow> contacts)
    {
        if (!ShouldPublish(contacts))
        {
            return false;
        }

        return loadedMode != FleetExternalContactPublicationMode.LegacyPrivate ||
               legacyPublicationConfirmed;
    }
}
