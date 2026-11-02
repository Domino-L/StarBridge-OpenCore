/// Negotiated protocol hints. Owner/editor action permissions remain separate.
final class OrganizationShipImageFeatures {
  const OrganizationShipImageFeatures({
    required this.read,
    required this.upload,
    required this.report,
    required this.reduce,
  });
  const OrganizationShipImageFeatures.none()
    : read = false,
      upload = false,
      report = false,
      reduce = false;
  final bool read, upload, report, reduce;
  bool get complete => read && upload && report && reduce;

  factory OrganizationShipImageFeatures.parse(Object? value) {
    if (value is! Map ||
        value.length != 5 ||
        value['protocolVersion'] != 1 ||
        const [
          'read',
          'upload',
          'report',
          'reduce',
        ].any((key) => value[key] is! bool)) {
      throw const FormatException('Invalid image features.');
    }
    return OrganizationShipImageFeatures(
      read: value['read'] as bool,
      upload: value['upload'] as bool,
      report: value['report'] as bool,
      reduce: value['reduce'] as bool,
    );
  }

  static const callableNames = {
    'officialFleet.shipImage',
    'officialFleet.reportShipImage',
    'officialFleet.shipImageReportStatus',
  };
}
