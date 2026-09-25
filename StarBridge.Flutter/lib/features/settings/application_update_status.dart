/// The verified Host projection, shared by automatic and explicit checks.
final class ApplicationUpdateStatus {
  ApplicationUpdateStatus._(this.payload);
  final Map<String, dynamic> payload;
  String get state => payload['state'] as String;
  String? get version => payload['availableVersion'] as String?;

  factory ApplicationUpdateStatus.parse(Map<String, dynamic> value) {
    const keys = {
      'schemaVersion',
      'state',
      'currentVersion',
      'availableVersion',
      'notes',
    };
    const states = {
      'channel-unconfigured',
      'up-to-date',
      'available',
      'configuration-invalid',
      'channel-unavailable',
      'verification-failed',
    };
    if (value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['schemaVersion'] != 1 ||
        !states.contains(value['state']) ||
        ![
          'currentVersion',
          'availableVersion',
          'notes',
        ].every((k) => value[k] == null || value[k] is String) ||
        (value['currentVersion'] as String? ?? '').length > 96 ||
        (value['availableVersion'] as String? ?? '').length > 96 ||
        (value['notes'] as String? ?? '').length > 16384 ||
        (value['state'] == 'available' &&
            (value['availableVersion'] == null ||
                !RegExp(r'^\d+\.\d+\.\d+(?:\.\d+)?$')
                    .hasMatch(value['availableVersion'] as String))) ||
        (value['state'] != 'available' &&
            (value['availableVersion'] != null || value['notes'] != null))) {
      throw const FormatException('Incompatible update status');
    }
    return ApplicationUpdateStatus._(Map.unmodifiable(value));
  }
}
