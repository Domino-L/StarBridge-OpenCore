import '../../shared/ships/ship_catalog_display.dart';
import 'menu_fleet_summary.dart';
import 'menu_announcement_details_view.dart';

/// Display-only organization projection. Authority references stay in the
/// primary session; row positions only associate presentation with its actions.
final class MenuOrganizationView {
  const MenuOrganizationView({
    required this.tab,
    required this.code,
    required this.description,
    required this.query,
    required this.total,
    required this.matched,
    required this.offset,
    required this.rows,
    this.logo,
    this.activeTime = '',
    this.navigation = const [],
    this.sections = const {},
    this.identity = '',
    this.bodyLoading = false,
    this.bodyError = false,
    this.overview,
    this.fleetStatistics,
  });
  final String tab, code, description, query;
  final int total, matched, offset;
  final List<MenuOrganizationRow> rows;
  final String? logo;
  final String activeTime;
  final List<MenuOrganizationNavigationItem> navigation;
  final Map<String, String?> sections;
  final String identity;
  final bool bodyLoading;
  final bool bodyError;
  final MenuOrganizationOverview? overview;
  final MenuFleetSummary? fleetStatistics;

  static MenuOrganizationView parse(
    Object? raw,
    int rowCount,
    Set<String> actionKeys,
  ) {
    if (raw is! Map) throw const FormatException();
    final sectionMap = raw['sections'] ?? const {};
    if (sectionMap is! Map || sectionMap.length > 4) {
      throw const FormatException();
    }
    final sections = <String, String?>{};
    for (final entry in sectionMap.entries) {
      if (!const {
            'members',
            'chat',
            'ships',
            'announcements',
          }.contains(entry.key) ||
          (entry.value != null &&
              (entry.value is! String ||
                  !actionKeys.contains(entry.value) ||
                  sections.containsValue(entry.value)))) {
        throw const FormatException();
      }
      sections[entry.key as String] = entry.value as String?;
    }
    final tab = _text(raw, 'tab', 24);
    if (!const {
      'directory',
      'members',
      'ships',
      'announcements',
      'chat',
    }.contains(tab)) {
      throw const FormatException();
    }
    final items = raw['rows'];
    if (items is! List || items.length != rowCount || items.length > 500) {
      throw const FormatException();
    }
    int count(String key) {
      final value = raw[key];
      if (value is! int || value < 0 || value > 1000000) {
        throw const FormatException();
      }
      return value;
    }

    return MenuOrganizationView(
      tab: tab,
      code: _text(raw, 'code', 128),
      description: _text(raw, 'description', 8192),
      query: _text(raw, 'query', 128),
      total: count('total'),
      matched: count('matched'),
      offset: count('offset'),
      rows: items.map(MenuOrganizationRow.parse).toList(),
      logo: _inline(raw, 'logo'),
      activeTime: _text(raw, 'activeTime', 1024),
      navigation: MenuOrganizationNavigationItem.parseList(raw['navigation']),
      sections: Map.unmodifiable(sections),
      identity: _text(raw, 'identity', 32),
      bodyLoading: raw['bodyLoading'] == true,
      bodyError: raw['bodyError'] == true,
      overview: MenuOrganizationOverview.parse(raw['overview']),
      fleetStatistics: MenuFleetSummary.parse(raw['fleetStatistics']),
    );
  }
}

final class MenuOrganizationOverview {
  const MenuOrganizationOverview(
    this.online,
    this.gaming,
    this.total,
    this.scoped,
  );
  final int? online, gaming, total;
  final bool scoped;
  static MenuOrganizationOverview? parse(Object? value) {
    if (value == null) return null;
    if (value is! Map) throw const FormatException();
    int? count(String key) {
      final n = value[key];
      if (n != null && (n is! int || n < 0 || n > 1000000)) {
        throw const FormatException();
      }
      return n as int?;
    }

    return MenuOrganizationOverview(
      count('online'),
      count('gaming'),
      count('total'),
      value['scoped'] == true,
    );
  }
}

final class MenuOrganizationNavigationItem {
  const MenuOrganizationNavigationItem(
    this.name,
    this.summary,
    this.time,
    this.avatar,
    this.key,
    this.unread,
    this.selected,
  );
  final String name, summary, time, key;
  final String? avatar;
  final int? unread;
  final bool selected;
  static List<MenuOrganizationNavigationItem> parseList(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > 500) throw const FormatException();
    final keys = <String>{};
    return List.unmodifiable(
      raw.map((value) {
        if (value is! Map) throw const FormatException();
        final key = _text(value, 'key', 32), unread = value['unread'];
        if (!RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(key) ||
            !keys.add(key) ||
            unread != null && (unread is! int || unread < 0 || unread > 500) ||
            value['selected'] is! bool) {
          throw const FormatException();
        }
        return MenuOrganizationNavigationItem(
          _text(value, 'name', 512),
          _text(value, 'summary', 1200),
          _text(value, 'time', 64),
          _inline(value, 'avatar'),
          key,
          unread as int?,
          value['selected'] as bool,
        );
      }),
    );
  }
}

final class MenuOrganizationRow {
  const MenuOrganizationRow({
    required this.handle,
    required this.role,
    required this.roleColor,
    required this.presence,
    required this.ship,
    required this.location,
    required this.server,
    required this.owner,
    required this.price,
    required this.spec,
    required this.status,
    required this.image,
    required this.isSelf,
    this.avatar,
    this.profileKey,
    this.logo,
    this.memberCount,
    this.importedAt = '',
    this.iconKey = '',
    this.announcementState = '',
    this.announcementTime = '',
    this.currentAnnouncement = false,
    this.announcement,
    this.relationship = '',
    this.tags = '',
    this.language = '',
    this.activeTime = '',
  });
  final String handle,
      role,
      roleColor,
      presence,
      ship,
      location,
      server,
      owner,
      price,
      spec,
      status;
  final String? image;
  final String? avatar, profileKey;
  final bool isSelf;
  final String? logo;
  final int? memberCount;
  final String relationship, tags, language, activeTime;
  final String importedAt, iconKey, announcementState, announcementTime;
  final bool currentAnnouncement;
  final MenuAnnouncementDetailsView? announcement;
  static MenuOrganizationRow parse(Object? value) {
    if (value is! Map) throw const FormatException();
    final presence = _text(value, 'presence', 24);
    if (!const {
      '',
      'online',
      'inGame',
      'away',
      'offline',
      'unknown',
    }.contains(presence)) {
      throw const FormatException();
    }
    final color = _text(value, 'roleColor', 9);
    if (color.isNotEmpty && !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(color)) {
      throw const FormatException();
    }
    final avatar = _text(value, 'avatar', 28000);
    final profileKey = _text(value, 'profileKey', 32);
    final memberCount = value['memberCount'];
    if (memberCount != null &&
        (memberCount is! int || memberCount < 0 || memberCount > 1000000)) {
      throw const FormatException();
    }
    if ((avatar.isNotEmpty && !avatar.startsWith('data:image/png;base64,')) ||
        (profileKey.isNotEmpty &&
            !RegExp(r'^om[1-9][0-9]{0,13}$').hasMatch(profileKey))) {
      throw const FormatException();
    }
    return MenuOrganizationRow(
      handle: _text(value, 'handle', 128),
      role: _text(value, 'role', 128),
      roleColor: color,
      presence: presence,
      ship: _text(value, 'ship', 512),
      location: _text(value, 'location', 512),
      server: _text(value, 'server', 128),
      owner: _text(value, 'owner', 256),
      price: _text(value, 'price', 128),
      spec: _text(value, 'spec', 128),
      status: _text(value, 'status', 128),
      image: ShipCatalogDisplay.image(_text(value, 'image', 256)),
      isSelf: value['isSelf'] == true,
      avatar: avatar.isEmpty ? null : avatar,
      profileKey: profileKey.isEmpty ? null : profileKey,
      logo: _inline(value, 'logo'),
      memberCount: memberCount as int?,
      importedAt: _text(value, 'importedAt', 64),
      iconKey: _text(value, 'iconKey', 64),
      announcementState: _text(value, 'announcementState', 16),
      announcementTime: _text(value, 'announcementTime', 64),
      currentAnnouncement: value['currentAnnouncement'] == true,
      announcement: MenuAnnouncementDetailsView.parse(value['announcement']),
      relationship: _text(value, 'relationship', 24),
      tags: _text(value, 'tags', 2048),
      language: _text(value, 'language', 128),
      activeTime: _text(value, 'activeTime', 1024),
    );
  }
}

String? _inline(Map value, String key) {
  final text = _text(value, key, 28000);
  if (text.isEmpty) return null;
  if (!text.startsWith('data:image/png;base64,')) throw const FormatException();
  return text;
}

String _text(Map value, String key, int max) {
  final text = value[key] ?? '';
  if (text is! String || text.length > max) throw const FormatException();
  return text;
}

String organizationPresence(bool online, String status) =>
    switch (status.toLowerCase()) {
      'ingame' => online ? 'inGame' : 'offline',
      'away' => online ? 'away' : 'offline',
      'apponline' || 'online' || 'offline' => online ? 'online' : 'offline',
      _ => 'unknown',
    };

String organizationPresenceText(String value) => switch (value) {
  'online' => '应用在线',
  'inGame' => '游戏中',
  'away' => '暂离',
  'offline' => '离线',
  _ => '状态未共享',
};
