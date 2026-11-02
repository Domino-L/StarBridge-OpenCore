/// Read-only bytes for a previously published cached directory version.
/// These updates never invalidate account state or confer a workspace lease.
final class CommunityCachedLogo {
  const CommunityCachedLogo(
    this.directoryVersion,
    this.organizationKey,
    this.imageData,
  );
  final String directoryVersion, organizationKey, imageData;
}

enum CommunityCachedSelectionChange { renew, replace }

abstract interface class CommunityCachedPresentationPort {
  Stream<CommunityCachedLogo> get cachedLogoChanges;

  /// Old operations are retired. Only an exact Native predecessor proof may
  /// renew existing presentation; a replacement clears it before preparation.
  Stream<CommunityCachedSelectionChange> get cachedSelectionChanges;
}
