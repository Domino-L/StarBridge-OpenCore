import 'package:flutter/foundation.dart';

@immutable
final class UpdateHighlight {
  const UpdateHighlight(this.label, this.text);
  final String label, text;
}

/// 更新说明开头的标题和亮点。
///
/// 只是普通文字，不带图、链接，也不多传字段，所以旧客户端照样能当普通说明显示：
///
/// ```
/// # 主舰队上线（测试版）
/// 交易大厅接入 SCM 市场。
/// - 【主舰队】成员、聊天、舰船都接进了客户端
/// - 【交易大厅】挂单、关注和交易私信都在这里
/// - 【社区组织】换成新的两屏页面
///
/// ## 完整更新内容
/// ...
/// ```
@immutable
final class UpdateAnnouncement {
  const UpdateAnnouncement._({
    required this.headline,
    required this.subline,
    required this.isTestVersion,
    required this.highlights,
    required this.fullNotes,
  });

  static const minHighlights = 3, maxHighlights = 4;
  static const _testVersionMark = '（测试版）';

  final String headline;
  final String? subline;
  final bool isTestVersion;
  final List<UpdateHighlight> highlights;

  /// 第一个 `##` 起的全部内容；没有就是 null，也就没有“查看完整更新内容”。
  final String? fullNotes;

  /// 不够格式（没有标题，或亮点少于 [minHighlights] 条）时返回 null，走普通说明。
  static UpdateAnnouncement? parse(String? notes) {
    if (notes == null) return null;
    final lines = stripUpdateHeroLine(notes).split('\n');
    final start = lines.indexWhere((line) => line.trim().isNotEmpty);
    if (start < 0) return null;
    final title = RegExp(r'^#\s+(.+)$').firstMatch(lines[start].trim());
    if (title == null) return null;
    final bodyAt = lines.indexWhere((line) => line.trim().startsWith('## '));
    final head = lines
        .sublist(start + 1, bodyAt < 0 ? lines.length : bodyAt)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    final paragraphs = <String>[];
    final highlights = <UpdateHighlight>[];
    for (final line in head) {
      final bullet = RegExp(r'^[-*]\s+【(.+?)】\s*(.+)$').firstMatch(line);
      if (bullet != null) {
        highlights.add(UpdateHighlight(bullet.group(1)!, bullet.group(2)!));
      } else if (line.startsWith('-') || line.startsWith('*')) {
        return null;
      } else {
        paragraphs.add(line);
      }
    }
    if (highlights.length < minHighlights) return null;
    final full = bodyAt < 0 ? '' : lines.sublist(bodyAt).join('\n').trim();
    final raw = title.group(1)!.trim();
    return UpdateAnnouncement._(
      headline: raw.replaceAll(_testVersionMark, '').trim(),
      subline: paragraphs.isEmpty ? null : paragraphs.join(' '),
      isTestVersion: raw.contains(_testVersionMark),
      highlights: List.unmodifiable(highlights.take(maxHighlights)),
      fullNotes: full.isEmpty ? null : full,
    );
  }
}

/// 大更新是三段版本号（0.7.3），小更新和修复是四段（0.7.3.1）。只有大更新用海报。
bool isMajorUpdateVersion(String version) => version.split('.').length == 3;

final _heroLine = RegExp(r'^主图校验 sha256=[0-9a-f]{64} bytes=[1-9][0-9]{0,7}$');

List<String> _noteLines(String notes) =>
    notes.replaceAll('\r\n', '\n').trimRight().split('\n');

/// 说明的最后一行是校验值、其他行都不是时，这版有一张要从更新服务器下载的主图。
/// 规则和 Host 一样。客户端只看这一行在不在：地址、下载和校验都在 Host。
bool updateNotesHaveHero(String notes) {
  final lines = _noteLines(notes);
  return _heroLine.hasMatch(lines.last) &&
      lines.where(_heroLine.hasMatch).length == 1;
}

/// 校验行不是给人看的，显示前去掉。
String stripUpdateHeroLine(String notes) =>
    _noteLines(notes)
        .where((line) => !_heroLine.hasMatch(line.trim()))
        .join('\n')
        .trimRight();

/// 普通说明开头的 `# 标题` 拆出来放在弹窗标题上；没有就是 null。
({String? title, String notes}) splitUpdateNotesTitle(String notes) {
  final text = notes.replaceAll('\r\n', '\n').trimLeft();
  final line = text.split('\n').first.trim();
  final title = RegExp(r'^#\s+(.+)$').firstMatch(line)?.group(1)?.trim();
  if (title == null) return (title: null, notes: notes);
  return (
    title: title,
    notes: text.substring(text.indexOf(line) + line.length),
  );
}
