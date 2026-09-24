import '../../shared/ships/ship_catalog_display.dart';

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
  });
  final String tab, code, description, query;
  final int total, matched, offset;
  final List<MenuOrganizationRow> rows;
  final String? logo;
  final String activeTime;

  static MenuOrganizationView parse(Object? raw, int rowCount) {
    if (raw is! Map) throw const FormatException();
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
