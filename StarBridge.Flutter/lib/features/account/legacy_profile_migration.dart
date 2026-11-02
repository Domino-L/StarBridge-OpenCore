import 'dart:convert';
import 'dart:typed_data';

import 'account_port.dart';

/// Account-scoped migration port. User-entered credentials are transient request data only.
abstract interface class LegacyProfileMigrationPort {
  Future<LegacyProfileMigrationView> migrationStatus();
  Future<LegacyProfileMigrationView> previewMigration({
    LegacyAccountCredential? credential,
    LegacyProfileImportSelection? selection,
  });
  Future<LegacyProfileMigrationView> confirmMigration(
    String previewId, {
    required bool replaceExisting,
  });
}

final class LegacyProfileImportSelection {
  LegacyProfileImportSelection({
    required List<String> modules,
    List<String> replaceModules = const [],
    this.useLegacyCallSign = false,
    this.useLegacyAvatar = false,
    this.previousCompletedPreviewId,
    this.replaceAllDisplayContent = false,
  }) : modules = List.unmodifiable(modules),
       replaceModules = List.unmodifiable(replaceModules) {
    const allowed = {'favorite-ships', 'hangar-summary', 'skilled-roles'};
    if (previousCompletedPreviewId != null &&
        (previousCompletedPreviewId!.trim().isEmpty ||
            previousCompletedPreviewId!.length > 64 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(previousCompletedPreviewId!))) {
      throw ArgumentError('Invalid previous import receipt.');
    }
    if (this.modules.toSet().length != this.modules.length ||
        this.replaceModules.toSet().length != this.replaceModules.length ||
        this.modules.any((id) => !allowed.contains(id)) ||
        this.replaceModules.any((id) => !this.modules.contains(id)) ||
        (replaceAllDisplayContent
            ? this.modules.isNotEmpty ||
                  this.replaceModules.isNotEmpty ||
                  useLegacyCallSign ||
                  useLegacyAvatar
            : this.modules.isEmpty && !useLegacyCallSign && !useLegacyAvatar)) {
      throw ArgumentError('Invalid module import selection.');
    }
  }
  final List<String> modules;
  final List<String> replaceModules;
  final bool useLegacyCallSign;
  final bool useLegacyAvatar;
  final String? previousCompletedPreviewId;
  final bool replaceAllDisplayContent;
  Map<String, Object?> toJson() => {
    'modules': modules,
    'replaceModules': replaceModules,
    'useLegacyCallSign': useLegacyCallSign,
    'useLegacyAvatar': useLegacyAvatar,
    if (replaceAllDisplayContent) 'replaceAllDisplayContent': true,
    if (previousCompletedPreviewId != null)
      'previousCompletedPreviewId': previousCompletedPreviewId,
  };
}

final class LegacyProfileImportChoices {
  const LegacyProfileImportChoices(
    this.selection,
    this.needsReselection, {
    this.version = 1,
  });
  final int version;
  final LegacyProfileImportSelection selection;
  final List<String> needsReselection;
  factory LegacyProfileImportChoices.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 && json['version'] != 2 ||
        json['useLegacyCallSign'] is! bool) {
      throw const FormatException('Invalid import choices.');
    }
    final full = json['version'] == 2;
    final modules = (json['modules'] as List).cast<String>();
    final replaced = (json['replaceModules'] as List).cast<String>();
    if (full &&
        (json['useLegacyCallSign'] != true ||
            modules.length != replaced.length ||
            List.generate(
              modules.length,
              (i) => modules[i] == replaced[i],
            ).any((same) => !same) ||
            modules.toSet().length != modules.length ||
            modules.any(
              (id) => !const {
                'favorite-ships',
                'hangar-summary',
                'skilled-roles',
              }.contains(id),
            ))) {
      throw const FormatException('Invalid full display replacement.');
    }
    final selection = LegacyProfileImportSelection(
      modules: full ? const [] : modules,
      replaceModules: full ? const [] : replaced,
      useLegacyCallSign: !full && json['useLegacyCallSign'] as bool,
      useLegacyAvatar: !full && (json['useLegacyAvatar'] as bool? ?? false),
      replaceAllDisplayContent: full,
    );
    final reselection = (json['needsReselection'] as List).cast<String>();
    if (reselection.any((id) => !selection.modules.contains(id)) ||
        reselection.toSet().length != reselection.length) {
      throw const FormatException('Invalid module references.');
    }
    return LegacyProfileImportChoices(
      selection,
      List.unmodifiable(reselection),
      version: json['version'] as int,
    );
  }
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
    this.choices,
    this.avatarPreview,
    this.selectedContent,
    this.presentation,
  });
  final String state;
  final String? previewId;
  final String? sourceGameId;
  final DateTime? expiresAt;
  final bool conflict;
  final LegacyProfileMigrationSummary? source;
  final LegacyProfileMigrationSummary? target;
  final LegacyProfileImportChoices? choices;
  final Uint8List? avatarPreview;
  final LegacyProfileSelectedContent? selectedContent;
  final Map<String, Object?>? presentation;

  factory LegacyProfileMigrationView.fromJson(Map<String, Object?> json) {
    final state = json['state'];
    if (state is! String || !_states.contains(state)) {
      throw const FormatException('Unknown migration state.');
    }
    final source = json['source'];
    final target = json['target'];
    final id = json['previewId'];
    final expires = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    Uint8List? avatar;
    if (json['avatarPreview'] case final String data) {
      const prefix = 'data:image/png;base64,';
      if (data.length > 100000 || !data.startsWith(prefix)) {
        throw const FormatException('Invalid avatar preview.');
      }
      avatar = base64Decode(data.substring(prefix.length));
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (avatar.length < 24 ||
          !List.generate(
            8,
            (i) => avatar![i] == signature[i],
          ).every((v) => v)) {
        throw const FormatException('Invalid avatar image.');
      }
      final header = ByteData.sublistView(avatar);
      if (header.getUint32(16) < 1 ||
          header.getUint32(16) > 128 ||
          header.getUint32(20) < 1 ||
          header.getUint32(20) > 128) {
        throw const FormatException('Invalid avatar dimensions.');
      }
    } else if (json['avatarPreview'] != null) {
      throw const FormatException('Invalid avatar preview.');
    }
    if ((state == 'previewed' || state == 'localApplyRequired') &&
        (id is! String ||
            id.isEmpty ||
            id.length > 64 ||
            source is! Map<String, Object?> ||
            target is! Map<String, Object?> ||
            expires == null)) {
      throw const FormatException('Incomplete migration preview.');
    }
    final choices = json['choices'] is Map<String, Object?>
        ? LegacyProfileImportChoices.fromJson(
            json['choices'] as Map<String, Object?>,
          )
        : null;
    if ((state == 'previewed' || state == 'localApplyRequired') &&
        (choices?.selection.useLegacyAvatar == true ||
            (json['choices'] is Map &&
                (json['choices'] as Map)['useLegacyAvatar'] == true)) &&
        avatar == null) {
      throw const FormatException('Avatar preview is required.');
    }
    final rawContent = json['selectedContent'];
    final full = choices?.version == 2;
    final rawPresentation = json['presentation'];
    if (full &&
        (rawPresentation is! Map<String, Object?> ||
            rawPresentation['callSign'] is! String ||
            rawPresentation['avatarStyle'] is! int ||
            rawPresentation['wallpaperId'] is! String ||
            rawPresentation['content'] is! Map<String, Object?> ||
            rawContent != null ||
            (state == 'previewed' || state == 'localApplyRequired') &&
                json['conflict'] != true)) {
      throw const FormatException('Incomplete full display replacement.');
    }
    final selectedContent = rawContent == null
        ? null
        : choices != null && rawContent is Map<String, Object?>
        ? LegacyProfileSelectedContent.fromJson(rawContent, choices.selection)
        : throw const FormatException('Unexpected selected content.');
    if ((state == 'previewed' || state == 'localApplyRequired') &&
        choices != null &&
        !full &&
        selectedContent == null) {
      throw const FormatException('Selected content is required.');
    }
    return LegacyProfileMigrationView(
      state,
      previewId: id as String?,
      sourceGameId: json['sourceGameId'] as String?,
      expiresAt: expires,
      avatarPreview: avatar,
      selectedContent: selectedContent,
      presentation: full
          ? Map.unmodifiable(rawPresentation as Map<String, Object?>)
          : null,
      conflict: json['conflict'] == true,
      choices: choices,
      source: source is Map<String, Object?>
          ? LegacyProfileMigrationSummary.fromJson(source)
          : null,
      target: target is Map<String, Object?>
          ? LegacyProfileMigrationSummary.fromJson(target)
          : null,
    );
  }
}

final class LegacyProfileSelectedContent {
  LegacyProfileSelectedContent({
    this.callSign,
    required Map<String, int> modules,
    List<String>? skilledRoles,
    List<String>? supportCapabilities,
    List<String>? participationInterests,
  }) : modules = Map.unmodifiable(modules),
       skilledRoles = skilledRoles == null
           ? null
           : List.unmodifiable(skilledRoles),
       supportCapabilities = supportCapabilities == null
           ? null
           : List.unmodifiable(supportCapabilities),
       participationInterests = participationInterests == null
           ? null
           : List.unmodifiable(participationInterests);
  final String? callSign;
  final Map<String, int> modules;
  final List<String>? skilledRoles;
  final List<String>? supportCapabilities;
  final List<String>? participationInterests;

  factory LegacyProfileSelectedContent.fromJson(
    Map<String, Object?> json,
    LegacyProfileImportSelection selection,
  ) {
    const keys = {
      'callSign',
      'modules',
      'skilledRoles',
      'supportCapabilities',
      'participationInterests',
    };
    if (json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unexpected import field.');
    }
    final name = json['callSign'];
    if (selection.useLegacyCallSign
        ? name is! String ||
              name.trim().isEmpty ||
              name.length > 32 ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)
        : name != null) {
      throw const FormatException('Unexpected import name.');
    }
    final rawModules = json['modules'];
    if (rawModules is! List || rawModules.length != selection.modules.length) {
      throw const FormatException('Invalid import modules.');
    }
    final modules = <String, int>{};
    for (var i = 0; i < rawModules.length; i++) {
      final module = rawModules[i];
      if (module is! Map<String, Object?> ||
          module.keys.any((k) => k != 'id' && k != 'span') ||
          module['id'] != selection.modules[i] ||
          module['span'] is! int ||
          (module['span'] as int) < 1 ||
          (module['span'] as int) > 3) {
        throw const FormatException('Invalid import module.');
      }
      modules[module['id'] as String] = module['span'] as int;
    }
    List<String>? tags(String key) {
      final value = json[key];
      if (!selection.modules.contains('skilled-roles')) {
        if (value != null) {
          throw const FormatException('Unselected collaboration data.');
        }
        return null;
      }
      if (value is! List ||
          value.length > 8 ||
          value.toSet().length != value.length ||
          value.any(
            (v) =>
                v is! String ||
                v.trim().isEmpty ||
                v.length > 80 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(v),
          )) {
        throw const FormatException('Invalid collaboration data.');
      }
      return value.cast<String>();
    }

    return LegacyProfileSelectedContent(
      callSign: name as String?,
      modules: modules,
      skilledRoles: tags('skilledRoles'),
      supportCapabilities: tags('supportCapabilities'),
      participationInterests: tags('participationInterests'),
    );
  }
}

const _states = {
  'localApplyRequired',
  'localPreviewRequired',
  'localTargetChanged',
  'localSaveUnavailable',
  'localReselectionRequired',
  'selectionAlreadyCompleted',
  'sourceAvatarUnavailable',
  'selectionRequired',
  'moduleReplacementRequired',
  'sourceModuleMissing',
  'invalidModuleSelection',
  'replacementNotSelected',
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
