/// What a visitor's server said about the organization slot (2026-10-29):
/// shown, none, hidden or unavailable. Anything else, including servers that
/// predate it, is null and keeps the older wording.
String? parseAffiliationStatus(Object? value) =>
    value is String &&
        const {'shown', 'none', 'hidden', 'unavailable'}.contains(value)
    ? value
    : null;

/// An organization logo URL is shown only when it is a plain https address.
String? validatedAffiliationLogoUrl(String? value) {
  if (value == null || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? value
      : null;
}
