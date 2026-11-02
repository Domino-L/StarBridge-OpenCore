import 'achievement_catalog.dart';
import 'achievement_collection_port.dart';

/// Assemble a pinned, account-fenced snapshot before publishing any rows.
/// The callback owns authentication/mode checks for every subsequent page.
Future<AchievementCollection> readScmAchievementPages(
  Map<String, Object?> first,
  Future<Map<String, Object?>> Function(int offset, String snapshotId) next, {
  required int generation,
  required bool cached,
}) async {
  Never invalid() =>
      throw const FormatException('Invalid SCM achievement snapshot');
  DateTime time(Object? value) {
    final at = value is String ? DateTime.tryParse(value) : null;
    if (at == null ||
        !at.isUtc ||
        !at.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) ||
        at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
      invalid();
    }
    return at;
  }

  final snapshot = first['snapshotId'];
  final total = first['total'];
  if (snapshot is! String ||
      snapshot.length > 64 ||
      total is! int ||
      total < 0 ||
      total > 4096) {
    invalid();
  }
  final readAt = time(first['readAtUtc']);
  final cachedAt = cached ? time(first['cachedAtUtc']) : null;
  final definitions = <AchievementDefinition>[];
  final earned = <String, DateTime>{};
  final owned = <String>{};
  final progress = <String, num>{};
  final ids = <String>{};
  String text(Map row, String key, int max, {bool required = false}) {
    final value = row[key];
    if (value == null && !required) return '';
    if (value is! String ||
        value.length > max ||
        required && value.trim().isEmpty ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(value)) {
      invalid();
    }
    return value;
  }

  num? number(Object? value, {bool target = false}) {
    if (value == null) return null;
    if (value is! num || !value.isFinite || value < 0 || target && value <= 0) {
      invalid();
    }
    return value;
  }

  var page = first, offset = 0;
  while (true) {
    final rows = page['items'];
    if (page['schemaVersion'] != 1 ||
        page['snapshotId'] != snapshot ||
        page['readAtUtc'] != first['readAtUtc'] ||
        page['total'] != total ||
        page['offset'] != offset ||
        page['cachedAtUtc'] != first['cachedAtUtc'] ||
        rows is! List ||
        rows.length > 16 ||
        rows.length != (total - offset).clamp(0, 16)) {
      invalid();
    }
    for (final raw in rows) {
      if (raw is! Map) invalid();
      final id = text(raw, 'id', 24, required: true);
      if (!RegExp(r'^scm-[1-9][0-9]{0,18}$').hasMatch(id) || !ids.add(id)) {
        invalid();
      }
      final name = text(raw, 'name', 160, required: true);
      final title = text(raw, 'title', 300);
      final description = text(raw, 'description', 4000);
      final condition = text(raw, 'condition', 4000);
      final url = text(raw, 'imageUrl', 2048);
      if (url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment ||
            !RegExp(r'\.[a-zA-Z]{2,}$').hasMatch(uri.host)) {
          invalid();
        }
      }
      final unlocked = raw['unlocked'];
      if (unlocked is! bool) invalid();
      if (unlocked) {
        owned.add(id);
        if (raw['unlockedAtUtc'] != null) {
          earned[id] = time(raw['unlockedAtUtc']);
        }
      } else if (raw['unlockedAtUtc'] != null) {
        invalid();
      }
      final current = number(raw['currentValue']);
      if (current != null) progress[id] = current;
      final rarity = switch (raw['rarity']) {
        null => null,
        'COMMON' => AchievementRarity.common,
        'RARE' => AchievementRarity.rare,
        'EPIC' => AchievementRarity.epic,
        'LEGENDARY' => AchievementRarity.legendary,
        _ => invalid(),
      };
      final type = raw['type'];
      if (!const [
        'NORMAL',
        'SPECIAL',
        'HIDDEN',
        'HOLIDAY',
        'EVENT_LIMITED',
      ].contains(type)) {
        invalid();
      }
      definitions.add(
        AchievementDefinition(
          id: id,
          nameKey: '',
          conditionKey: 'achievements.progressPending',
          memoryKey: '',
          earnedAsset: '',
          lockedAsset: '',
          source: AchievementSource.scm,
          groupId: 'scm-$type',
          groupNameKey: 'achievements.group.scm.$type',
          serverName: scmDisplayTitle(title) ?? name,
          serverCondition: condition.isNotEmpty
              ? scmDisplayText(condition)
              : description.isNotEmpty
              ? scmDisplayText(description)
              : null,
          serverMemory: scmDisplayText(description),
          remoteImageUrl: url.isEmpty ? null : url,
          rarity: rarity,
          target: number(raw['targetValue'], target: true),
        ),
      );
    }
    offset += rows.length;
    if (offset == total) {
      if (page['nextOffset'] != null) invalid();
      break;
    }
    if (page['nextOffset'] != offset) invalid();
    page = await next(offset, snapshot);
  }
  return AchievementCollection(
    generation: generation,
    status: AchievementCollectionStatus.ready,
    catalog: List.unmodifiable(definitions),
    earnedAt: earned,
    ownedIds: Set.unmodifiable(owned),
    progress: progress,
    cachedAtUtc: cachedAt,
    synchronizedAtUtc: readAt,
  );
}

/// SCM 的标题偶尔带着多余的符号，例如“×星际劳模”“⚒星际劳模”。显示和取图都用
/// 清过的名字；只去掉首尾的记号和空白，不碰标题本身的字。清完是空的就返回 null。
String? scmDisplayTitle(String raw) {
  const marks = r'[\s\p{So}\p{Sk}\uFE0F×*·•\-–—_~|]+';
  final cleaned = raw
      .replaceFirst(RegExp('^$marks', unicode: true), '')
      .replaceFirst(RegExp('$marks\$', unicode: true), '');
  return cleaned.isEmpty ? null : cleaned;
}

/// SCM 的成就说明写“登录网站”。客户端里只说登录，其余文字不动。
String scmDisplayText(String raw) => raw
    .replaceAllMapped(RegExp(r'(登[录錄入])(?:网站|網站)'), (match) => match[1]!)
    .replaceAllMapped(
      RegExp(
        r'\b(log(?:ging)? ?in|logged in|sign(?:ing)? ?in|signed in)'
        r' (?:to|into|on|at) (?:the )?(?:web)?site\b',
        caseSensitive: false,
      ),
      (match) => match[1]!,
    );
