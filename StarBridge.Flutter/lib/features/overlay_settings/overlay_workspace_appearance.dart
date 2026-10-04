import 'package:flutter/foundation.dart';

@immutable
final class OverlayWorkspaceAppearance {
  const OverlayWorkspaceAppearance({
    required this.id,
    required this.displayNameZh,
    required this.displayNameEn,
    required this.summaryZh,
    required this.summaryEn,
    required this.traitsZh,
    required this.traitsEn,
    required this.previewSurface,
    required this.previewPrimary,
    required this.previewSecondary,
    required this.locksTheme,
    required this.supportsBloom,
    required this.startupTransition,
    required this.requiresEntitlement,
    required this.isReleased,
    required this.isAvailable,
    bool? isPreviewAvailable,
  }) : _previewAvailable = isPreviewAvailable;

  final String id;
  final String displayNameZh;
  final String displayNameEn;
  final String summaryZh;
  final String summaryEn;
  final List<String> traitsZh;
  final List<String> traitsEn;
  final String previewSurface;
  final String previewPrimary;
  final String previewSecondary;
  final bool locksTheme;
  final bool supportsBloom;
  final String startupTransition;
  final bool requiresEntitlement;
  final bool isReleased;
  final bool isAvailable;
  final bool? _previewAvailable;

  bool get isPreviewAvailable => _previewAvailable ?? isReleased;

  factory OverlayWorkspaceAppearance.fromMap(Map<String, Object?> source) {
    const fields = <String>{
      'id',
      'displayNameZh',
      'displayNameEn',
      'summaryZh',
      'summaryEn',
      'traitsZh',
      'traitsEn',
      'previewSurface',
      'previewPrimary',
      'previewSecondary',
      'locksTheme',
      'supportsBloom',
      'startupTransition',
      'requiresEntitlement',
      'isReleased',
      'isAvailable',
    };
    if (!setEquals(source.keys.toSet(), fields) &&
        !setEquals(source.keys.toSet(), {...fields, 'isPreviewAvailable'})) {
      throw const FormatException('Invalid overlay appearance fields.');
    }
    final id = source['id'];
    final displayNameZh = source['displayNameZh'];
    final displayNameEn = source['displayNameEn'];
    final summaryZh = source['summaryZh'];
    final summaryEn = source['summaryEn'];
    final traitsZh = _appearanceStrings(source['traitsZh']);
    final traitsEn = _appearanceStrings(source['traitsEn']);
    final previewSurface = source['previewSurface'];
    final previewPrimary = source['previewPrimary'];
    final previewSecondary = source['previewSecondary'];
    final locksTheme = source['locksTheme'];
    final supportsBloom = source['supportsBloom'];
    final startupTransition = source['startupTransition'];
    final requiresEntitlement = source['requiresEntitlement'];
    final isReleased = source['isReleased'];
    final isAvailable = source['isAvailable'];
    final isPreviewAvailable = source['isPreviewAvailable'];
    final color = RegExp(r'^#[0-9A-Fa-f]{6}$');
    if (id is! String ||
        id.isEmpty ||
        displayNameZh is! String ||
        displayNameZh.isEmpty ||
        displayNameEn is! String ||
        displayNameEn.isEmpty ||
        summaryZh is! String ||
        summaryEn is! String ||
        traitsZh.isEmpty ||
        traitsEn.isEmpty ||
        previewSurface is! String ||
        !color.hasMatch(previewSurface) ||
        previewPrimary is! String ||
        !color.hasMatch(previewPrimary) ||
        previewSecondary is! String ||
        !color.hasMatch(previewSecondary) ||
        locksTheme is! bool ||
        supportsBloom is! bool ||
        startupTransition is! String ||
        startupTransition.isEmpty ||
        requiresEntitlement is! bool ||
        isReleased is! bool ||
        isAvailable is! bool ||
        (source.containsKey('isPreviewAvailable') &&
            isPreviewAvailable is! bool) ||
        (isAvailable && !isReleased) ||
        (isReleased && !requiresEntitlement && !isAvailable)) {
      throw const FormatException('Invalid overlay appearance values.');
    }
    return OverlayWorkspaceAppearance(
      id: id,
      displayNameZh: displayNameZh,
      displayNameEn: displayNameEn,
      summaryZh: summaryZh,
      summaryEn: summaryEn,
      traitsZh: traitsZh,
      traitsEn: traitsEn,
      previewSurface: previewSurface.toUpperCase(),
      previewPrimary: previewPrimary.toUpperCase(),
      previewSecondary: previewSecondary.toUpperCase(),
      locksTheme: locksTheme,
      supportsBloom: supportsBloom,
      startupTransition: startupTransition,
      requiresEntitlement: requiresEntitlement,
      isReleased: isReleased,
      isAvailable: isAvailable,
      isPreviewAvailable: isPreviewAvailable as bool?,
    );
  }

  OverlayWorkspaceAppearance copyWith({
    bool? isReleased,
    bool? isAvailable,
    bool? isPreviewAvailable,
  }) => OverlayWorkspaceAppearance(
    id: id,
    displayNameZh: displayNameZh,
    displayNameEn: displayNameEn,
    summaryZh: summaryZh,
    summaryEn: summaryEn,
    traitsZh: traitsZh,
    traitsEn: traitsEn,
    previewSurface: previewSurface,
    previewPrimary: previewPrimary,
    previewSecondary: previewSecondary,
    locksTheme: locksTheme,
    supportsBloom: supportsBloom,
    startupTransition: startupTransition,
    requiresEntitlement: requiresEntitlement,
    isReleased: isReleased ?? this.isReleased,
    isAvailable: isAvailable ?? this.isAvailable,
    isPreviewAvailable: isPreviewAvailable ?? _previewAvailable,
  );
}

List<String> _appearanceStrings(Object? source) {
  if (source is! List ||
      source.isEmpty ||
      source.any((value) => value is! String)) {
    throw const FormatException('Invalid overlay appearance text.');
  }
  return List<String>.unmodifiable(source.cast<String>());
}
