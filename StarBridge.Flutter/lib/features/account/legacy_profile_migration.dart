import 'account_port.dart';

/// Account-scoped migration port. User-entered credentials are transient request data only.
abstract interface class LegacyProfileMigrationPort {
  Future<LegacyProfileMigrationView> migrationStatus();
  Future<LegacyProfileMigrationView> previewMigration({
    LegacyAccountCredential? credential,
  });
  Future<LegacyProfileMigrationView> confirmMigration(
    String previewId, {
    required bool replaceExisting,
  });
}

final class LegacyProfileMigrationView {
  const LegacyProfileMigrationView(
    this.state, {
    this.previewId,
    this.sourceGameId,
    this.expiresAt,
    this.conflict = false,
    this.source,
    this.target,
  });
  final String state;
  final String? previewId;
  final String? sourceGameId;
  final DateTime? expiresAt;
  final bool conflict;
  final LegacyProfileMigrationSummary? source;
  final LegacyProfileMigrationSummary? target;

  factory LegacyProfileMigrationView.fromJson(Map<String, Object?> json) {
    final state = json['state'];
    if (state is! String || !_states.contains(state)) {
      throw const FormatException('Unknown migration state.');
    }
    final source = json['source'];
    final target = json['target'];
    final id = json['previewId'];
    final expires = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (state == 'previewed' &&
        (id is! String ||
            id.isEmpty ||
            id.length > 64 ||
            source is! Map<String, Object?> ||
            target is! Map<String, Object?> ||
            expires == null)) {
      throw const FormatException('Incomplete migration preview.');
    }
    return LegacyProfileMigrationView(
      state,
      previewId: id as String?,
      sourceGameId: json['sourceGameId'] as String?,
      expiresAt: expires,
      conflict: json['conflict'] == true,
      source: source is Map<String, Object?>
          ? LegacyProfileMigrationSummary.fromJson(source)
          : null,
      target: target is Map<String, Object?>
          ? LegacyProfileMigrationSummary.fromJson(target)
          : null,
    );
  }
}

const _states = {
  'credentialRequired',
  'credentialRejected',
  'verificationRateLimited',
  'sourceNotConfigured',
  'profileNotFound',
  'notStarted',
  'previewed',
  'completed',
  'sourceUnavailable',
  'linkRequired',
  'accountMismatch',
  'authorizationRequired',
  'unsupportedData',
  'previewRequired',
  'previewExpired',
  'replacementRequired',
  'targetChanged',
};

final class LegacyProfileMigrationSummary {
  const LegacyProfileMigrationSummary({
    required this.callSign,
    required this.introduction,
    required this.modules,
    required this.favorites,
    required this.playTimeSeconds,
  });
  final String callSign;
  final String introduction;
  final int modules;
  final int favorites;
  final int? playTimeSeconds;
  factory LegacyProfileMigrationSummary.fromJson(Map<String, Object?> json) =>
      LegacyProfileMigrationSummary(
        callSign: json['callSign'] as String,
        introduction: json['introduction'] as String,
        modules: json['modules'] as int,
        favorites: json['favorites'] as int,
        playTimeSeconds: json['playTimeSeconds'] as int?,
      );
}
