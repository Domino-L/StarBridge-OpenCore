import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import 'room_tag_catalog.dart';
import 'room_tag_colors.dart';

String tagCopy(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final entry = _copy[key]!;
  return locale.languageCode != 'zh'
      ? entry.$3
      : locale.countryCode == 'TW'
      ? entry.$2
      : entry.$1;
}

const _copy = <String, (String, String, String)>{
  'title': ('选择房间标签', '選擇房間標籤', 'Choose room tags'),
  'searchTags': ('搜索标签或分类', '搜尋標籤或分類', 'Search tags or categories'),
  'choose': ('选择标签', '選擇標籤', 'Choose tags'),
  'gameplay': ('玩法路径', '玩法路徑', 'Gameplay paths'),
  'context': ('附加标签', '附加標籤', 'Additional tags'),
  'pace': ('队伍节奏', '隊伍節奏', 'Pace'),
  'experience': ('经验氛围', '經驗氛圍', 'Experience'),
  'need': ('当前缺口', '目前缺口', 'Roles needed'),
  'other': ('其他', '其他', 'Other'),
  'add': ('选择当前层级', '選擇目前層級', 'Choose this level'),
  'browse': (
    '选择分类继续细分，也可以直接选择当前层级。',
    '選擇分類繼續細分，也可以直接選擇目前層級。',
    'Explore a category or choose its current level.',
  ),
  'required': (
    '至少选择一条玩法路径。',
    '至少選擇一條玩法路徑。',
    'Choose at least one gameplay path.',
  ),
  'gameplayLimit': (
    '玩法路径最多选择 3 条。',
    '玩法路徑最多選擇 3 條。',
    'Choose up to 3 gameplay paths.',
  ),
  'contextLimit': (
    '附加标签最多选择 3 个。',
    '附加標籤最多選擇 3 個。',
    'Choose up to 3 additional tags.',
  ),
  'totalLimit': ('最多选择 5 个标签。', '最多選擇 5 個標籤。', 'Choose up to 5 tags in total.'),
  'unknown': (
    '标签目录已变化，请重新选择。',
    '標籤目錄已變更，請重新選擇。',
    'The catalog changed. Choose tags again.',
  ),
  'branch': ('同一分支仅保留一个层级。', '同一分支僅保留一個層級。', 'Choose one level per branch.'),
  'cancel': ('取消', '取消', 'Cancel'),
  'confirm': ('确认标签', '確認標籤', 'Confirm tags'),
  'filter': ('筛选标签', '篩選標籤', 'Filter tags'),
  'clear': ('清除筛选', '清除篩選', 'Clear filters'),
  'search': ('搜索房间或玩法', '搜尋房間或玩法', 'Search rooms or gameplay'),
  'noMatches': (
    '没有符合筛选条件的房间。',
    '沒有符合篩選條件的房間。',
    'No rooms match these filters.',
  ),
};

Future<Set<String>?> showRoomTagPicker(
  BuildContext context, {
  required List<RoomTag> options,
  required Set<String> selected,
  bool filter = false,
}) => showDialog<Set<String>>(
  context: context,
  builder: (_) =>
      _TagPicker(options: options, selected: selected, filter: filter),
);

class _TagPicker extends StatefulWidget {
  const _TagPicker({
    required this.options,
    required this.selected,
    required this.filter,
  });
  final List<RoomTag> options;
  final Set<String> selected;
  final bool filter;
  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final catalog = RoomTagCatalog(widget.options);
  late Set<String> selected = catalog.normalizeSelection(widget.selected);
  List<String> path = [];
  String query = '';
  String? error;
  void add(String id) {
    final next = catalog.adding(selected, id);
    final failure = widget.filter
        ? null
        : catalog.invalid(next, requireGameplay: false);
    setState(() {
      error = failure;
      if (failure == null) selected = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => tagCopy(context, key);
    final levels = <List<String>>[catalog.children(null)];
    for (final id in path.take(2)) {
      final children = catalog.children(id);
      if (children.isNotEmpty) levels.add(children);
    }
    return AlertDialog(
      title: Text(t(widget.filter ? 'filter' : 'title')),
      content: SizedBox(
        width: 850,
        height: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${t('gameplay')} · ${selected.length}${widget.filter ? '' : ' / 5'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in RoomTagCatalog.ordered(
                    catalog.options.values.where(
                      (tag) =>
                          selected.contains(RoomTagCatalog.normalize(tag.id)),
                    ),
                  ))
                    InputChip(
                      key: ValueKey('selected-tag-${tag.id}'),
                      label: Text(RoomTagCatalog.fullText(tag)),
                      backgroundColor: roomTagColors(context, tag.id).soft,
                      labelStyle: TextStyle(
                        color: roomTagColors(context, tag.id).foreground,
                      ),
                      onDeleted: () => setState(
                        () => selected.remove(RoomTagCatalog.normalize(tag.id)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                path.isEmpty
                    ? t('browse')
                    : path.map(catalog.label).join(' / '),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('tag-catalog-search'),
                decoration: InputDecoration(labelText: t('searchTags')),
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              if (query.isNotEmpty)
                SizedBox(
                  height: 220,
                  child: Material(
                    color: Colors.transparent,
                    child: ListView(
                      children: [
                        for (final tag in catalog.options.values.where(
                          (tag) =>
                              RoomTagCatalog.fullText(tag)
                                  .toLowerCase()
                                  .contains(query),
                        ))
                          ListTile(
                            key: ValueKey('search-tag-${tag.id}'),
                            title: Text(
                              RoomTagCatalog.fullText(tag),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: roomTagColors(
                                      context,
                                      tag.id,
                                    ).foreground,
                                  ),
                            ),
                            selected: selected.contains(tag.id),
                            selectedTileColor: roomTagColors(
                              context,
                              tag.id,
                            ).soft,
                            onTap: () => add(tag.id),
                          ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, bounds) {
                    final wide = bounds.maxWidth >= 620;
                    final columns = <Widget>[
                      for (var level = 0; level < levels.length; level++)
                        SizedBox(
                          width: wide
                              ? (bounds.maxWidth - 16) / 3
                              : bounds.maxWidth,
                          height: wide ? 220 : 150,
                          child: Card.outlined(
                            margin: const EdgeInsets.all(2),
                            child: ListView(
                              children: [
                                for (final id in levels[level])
                                  ListTile(
                                    dense: true,
                                    key: ValueKey('browse-tag-$id'),
                                    selected: path.contains(id),
                                    title: Text(
                                      catalog.label(id),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: roomTagColors(
                                              context,
                                              id,
                                            ).foreground,
                                          ),
                                    ),
                                    textColor: roomTagColors(
                                      context,
                                      id,
                                    ).foreground,
                                    selectedColor: roomTagColors(
                                      context,
                                      id,
                                    ).foreground,
                                    selectedTileColor: roomTagColors(
                                      context,
                                      id,
                                    ).soft,
                                    trailing: catalog.children(id).isEmpty
                                        ? null
                                        : const StandardIcon(
                                            StandardIconSemantic.chevronRight,
                                            size: 16,
                                          ),
                                    onTap: () => setState(() {
                                      path = [...path.take(level), id];
                                      error = null;
                                    }),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ];
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: columns,
                          )
                        : Column(children: columns);
                  },
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const Key('room-tag-add-current'),
                  onPressed:
                      path.isNotEmpty && catalog.options.containsKey(path.last)
                      ? () => add(path.last)
                      : null,
                  child: Text(t('add')),
                ),
              ),
              const Divider(height: 24),
              Text(
                t('context'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final group in ['need', 'pace', 'experience', 'other'])
                if (catalog.options.values.any(
                  (tag) =>
                      !tag.isGameplay && RoomTagCatalog.group(tag.id) == group,
                )) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(t(group)),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in catalog.options.values.where(
                        (tag) =>
                            !tag.isGameplay &&
                            RoomTagCatalog.group(tag.id) == group,
                      ))
                        FilterChip(
                          key: ValueKey('context-tag-${tag.id}'),
                          label: Text(tag.text),
                          selected: selected.contains(tag.id),
                          selectedColor: roomTagColors(context, tag.id).soft,
                          checkmarkColor: roomTagColors(
                            context,
                            tag.id,
                          ).foreground,
                          labelStyle: TextStyle(
                            color: roomTagColors(context, tag.id).foreground,
                          ),
                          onSelected: (value) => value
                              ? add(tag.id)
                              : setState(() => selected.remove(tag.id)),
                        ),
                    ],
                  ),
                ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    t(error!),
                    style: TextStyle(color: context.tokens.colors.warning),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('cancel')),
        ),
        FilledButton(
          key: const Key('room-tags-confirm'),
          onPressed: () {
            final failure = widget.filter ? null : catalog.invalid(selected);
            if (failure != null) {
              setState(() => error = failure);
              return;
            }
            Navigator.pop(context, selected);
          },
          child: Text(t('confirm')),
        ),
      ],
    );
  }
}
