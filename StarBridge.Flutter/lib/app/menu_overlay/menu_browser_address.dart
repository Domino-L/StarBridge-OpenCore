/// Resolve explicit web addresses and ordinary searches without dispatching
/// external protocols. This does not navigate or retain browsing history.
Uri menuBrowserHome({String provider = 'bing-global'}) =>
    Uri.https(switch (provider) {
      'bing-cn' => 'cn.bing.com',
      'baidu' => 'www.baidu.com',
      'google' => 'www.google.com',
      'duckduckgo' => 'duckduckgo.com',
      _ => 'www.bing.com',
    }, '/');

Uri? menuBrowserAddress(String value, {String provider = 'bing-global'}) {
  final input = value.trim();
  if (input.isEmpty) return null;
  Uri search() => switch (provider) {
    'bing-cn' => Uri.https('cn.bing.com', '/search', {'q': input}),
    'baidu' => Uri.https('www.baidu.com', '/s', {'wd': input}),
    'google' => Uri.https('www.google.com', '/search', {'q': input}),
    'duckduckgo' => Uri.https('duckduckgo.com', '/', {'q': input}),
    _ => Uri.https('www.bing.com', '/search', {'q': input}),
  };
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
