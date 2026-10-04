/// Resolve explicit web addresses and ordinary searches without dispatching
/// external protocols. This does not navigate or retain browsing history.
Uri? menuBrowserAddress(String value) {
  final input = value.trim();
  if (input.isEmpty) return null;
  Uri search() => Uri.https('www.bing.com', '/search', {'q': input});
  final explicit = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(input);
  final hostPort = RegExp(
    r'^(localhost|[a-zA-Z0-9.-]+\.[a-zA-Z0-9-]+):[0-9]+(?:[/\?#]|$)',
  ).hasMatch(input);
  if (explicit && !hostPort) {
    final uri = Uri.tryParse(input);
    return uri != null &&
            const ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            !uri.host.contains('%') &&
            !RegExp(r'\s').hasMatch(input) &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }
  if (RegExp(r'\s').hasMatch(input)) return search();
  final uri = Uri.tryParse('https://$input');
  if (uri == null ||
      uri.host.isEmpty ||
      uri.host.contains('%') ||
      uri.userInfo.isNotEmpty ||
      !(uri.host.contains('.') || uri.host == 'localhost')) {
    return search();
  }
  return uri;
}
