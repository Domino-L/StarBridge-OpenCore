import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/achievements_strings.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_presentation.dart';

void main() {
  test('Grim HEX approved names, conditions and memories are exact', () {
    for (final (values, name, condition, memory) in [
      (achievementsZhCn, '法外六角湾', '抵达耶拉小行星带里的六角湾', '环中暗礁，自成一港'),
      (achievementsZhTw, '法外六角灣', '抵達耶拉小行星帶裡的六角灣', '環中暗礁，自成一港'),
      (
        achievementsEn,
        'Lawless Grim HEX',
        "Arrive at Grim HEX in Yela's asteroid belt",
        'A hidden reef in the ring, a harbour of its own',
      ),
    ]) {
      expect(values['achievements.grimhex.name'], name);
      expect(values['achievements.grimhex.condition'], condition);
      expect(values['achievements.grimhex.memory'], memory);
    }
  });

  test('11-04 approved simplified conditions are exact', () {
    const expected = {
      'levski': '抵达尼克斯星系的列夫斯基',
      'grimhex': '抵达耶拉小行星带里的六角湾',
      'pyroMajors': '抵达派罗的死局空间站、轨道讣闻站和废墟空间站',
      'pyroAll': '抵达派罗的全部 23 个空间站（不含星门）',
      'contractFirst': '由你本人首次完成一整单合约，阶段目标完成不算',
      'contractTsgLead': '作为任务主完整完成一次“需要战术打击群”合约',
      'contractTsgComplete': '完整完成一次“需要战术打击群”合约',
      'contractTsgSwift': '在 {minutes} 分钟内完整完成“需要战术打击群”合约（到达作战地点后才开始计时）',
      'contractTsgDeathless': '无死亡完整完成一次“需要战术打击群”合约（倒地后被救起不算死亡）',
    };
    for (final entry in expected.entries) {
      expect(
        achievementsZhCn['achievements.${entry.key}.condition'],
        entry.value,
      );
    }
  });

  for (final (locale, values) in [
    (const Locale('zh', 'CN'), achievementsZhCn),
    (const Locale('zh', 'TW'), achievementsZhTw),
    (const Locale('en', 'US'), achievementsEn),
  ]) {
    test('$locale achievement conditions have no terminal period', () {
      final conditions = values.entries.where(
        (entry) =>
            entry.key.endsWith('.condition') &&
            entry.key != 'achievements.idea.condition',
      );
      expect(conditions.length, greaterThanOrEqualTo(17));
      for (final entry in conditions) {
        expect(entry.value, isNot(matches(r'[。.]$')), reason: entry.key);
      }
      final strings = AppStrings.resolve(locale);
      final collection = AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
      );
      for (final definition in achievementCatalog) {
        final p = AchievementPresentation(definition, collection, strings);
        expect(p.condition, isNot(matches(r'[。.]$')), reason: definition.id);
        expect(p.condition, isNot(contains('{')));
        if (definition.groupId == 'contract') {
          expect(strings.text(definition.memoryKey), isEmpty);
          expect(p.memory, isEmpty);
        }
      }
      final removed = locale.languageCode == 'en'
          ? ['inventory', 'backfill', 'once per account', 'record continuously']
          : locale.countryCode == 'TW'
          ? ['倉庫', '不補歷史', '僅獲得一次', '全程連線']
          : ['仓库', '不补历史', '仅获得一次', '全程在线'];
      for (final entry in conditions) {
        for (final phrase in removed) {
          expect(entry.value, isNot(contains(phrase)), reason: entry.key);
        }
      }
    });
  }

  test(
    '0.7.3 notes match approved conditions, local records and app rarity',
    () {
      final catalog = jsonDecode(
        File('../release-notes/catalog.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final version = (catalog['entries'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['version'] == '0.7.3');
      final lines = (version['highlights'] as List).cast<String>();
      const grimhexNote = '【旅程成就】新增“法外六角湾”：抵达耶拉小行星带里的六角湾。';
      expect(lines.where((line) => line == grimhexNote), hasLength(1));
      // 0.7.3.md is generated from catalog.json: the 【分类】 tag becomes the
      // "## 分类" heading and each item is listed without the tag.
      // Windows checkouts may use CRLF (core.autocrlf); compare line content only.
      final markdown = File('../release-notes/0.7.3.md')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final journeySection = markdown
          .split('\n## ')
          .singleWhere((section) => section.startsWith('旅程成就\n'));
      expect(
        journeySection,
        contains('- ${grimhexNote.substring('【旅程成就】'.length)}\n'),
      );
      for (final key in [
        'levski',
        'grimhex',
        'pyroMajors',
        'pyroAll',
        'contractFirst',
        'contractTsgLead',
        'contractTsgComplete',
        'contractTsgSwift',
        'contractTsgDeathless',
      ]) {
        final condition = achievementsZhCn['achievements.$key.condition']!
            .replaceAll('{minutes}', '90');
        expect(
          lines.any((line) => line.contains(condition)),
          isTrue,
          reason: key,
        );
      }
      final relevant = lines
          .where(
            (line) => line.startsWith('【旅程成就】') || line.startsWith('【合约成就】'),
          )
          .join();
      for (final phrase in ['仓库', '不补历史', '仅获得一次', '不会', '保证']) {
        expect(relevant, isNot(contains(phrase)));
      }
      expect(relevant, contains('卡片和详情'));
      expect(relevant, contains('最佳成绩'));
      expect(relevant, contains('用时更短'));
      final rarity = lines.singleWhere((line) => line.contains('全应用达成比例'));
      for (final phrase in ['稀有', '极稀有', '近 30 天活跃账号', '人数不足时不显示']) {
        expect(rarity, contains(phrase));
      }
    },
  );
}
