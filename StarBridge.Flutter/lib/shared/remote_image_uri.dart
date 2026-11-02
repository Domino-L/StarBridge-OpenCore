import 'dart:io';

Uri? remoteImageUri(String source) {
  if (source.length > 2048) return null;
  final uri = Uri.tryParse(source);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasFragment) {
    return null;
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (!host.contains('.') ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local')) {
    return null;
  }
  final address = InternetAddress.tryParse(host);
  if (address != null) {
    final b = address.rawAddress;
    if (address.type != InternetAddressType.IPv4 ||
        b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        b[0] == 169 && b[1] == 254 ||
        b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
        b[0] == 192 && b[1] == 168) {
      return null;
    }
  }
  return uri;
}
