import '../../shared/downloadable_image_cache.dart';
import 'menu_directory_logos.dart';

/// The feature's organization logos have separate ownership from member
/// portraits, chat media and drafts. Only their presentation paths are reset.
final class MenuOrganizationImages implements DownloadableImageCache {
  MenuOrganizationImages(this.port, this.logos, this.retire);
  final Object port;
  final MenuDirectoryLogos logos;
  final void Function() retire;
  @override
  void beginImageMaintenance() {
    logos.beginImageMaintenance();
    if (port case final DownloadableImageCache cache) {
      cache.beginImageMaintenance();
    }
    retire();
  }

  @override
  void endImageMaintenance() {
    if (port case final DownloadableImageCache cache) {
      cache.endImageMaintenance();
    }
    logos.endImageMaintenance();
    retire();
  }

  Future<Map<String, Object?>> read(
    Future<Map<String, Object?>> Function() run,
  ) async {
    final started = logos.imageEpoch;
    final view = await run();
    return logos.imagesCurrent(started) ? view : strip(view);
  }

  static List<Map<String, Object?>> navigation(
    List<Map<String, Object?>> rows,
  ) => [
    for (final row in rows) {...row, 'avatar': null},
  ];

  static Map<String, Object?>? stripNullable(Map<String, Object?>? view) =>
      view == null ? null : strip(view);

  static Map<String, Object?> strip(Map<String, Object?> view) {
    final org = view['organization'];
    return {
      ...view,
      if (view['channels'] is List)
        'channels': [
          for (final row in view['channels'] as List)
            {...row as Map, 'avatar': null},
        ],
      if (org is Map)
        'organization': {
          ...org,
          'logo': null,
          if (org['navigation'] is List)
            'navigation': [
              for (final row in org['navigation'] as List)
                {...row as Map, 'avatar': null},
            ],
          if (org['tab'] == 'directory' && org['rows'] is List)
            'rows': [
              for (final row in org['rows'] as List)
                {...row as Map, 'logo': null},
            ],
        },
    };
  }
}
