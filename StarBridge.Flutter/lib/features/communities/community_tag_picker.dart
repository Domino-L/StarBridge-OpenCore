import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'community_creation_port.dart';
import 'community_gameplay_tags.dart';
import 'community_profile_rules.dart';
import 'community_profile_copy.dart';

/// Edits a private selection copy. Only Apply returns values to the caller.
class CommunityTagPicker extends StatefulWidget {
  const CommunityTagPicker({
    required this.options,
    required this.selected,
    this.profileQuotas = false,
    super.key,
  });
  final CommunityCreationOptions options;
  final List<String> selected;
  final bool profileQuotas;
  @override
  State<CommunityTagPicker> createState() => _CommunityTagPickerState();
}

class _CommunityTagPickerState extends State<CommunityTagPicker> {
  late final Set<String> selected = widget.selected.toSet();
  String? category;
  String query = '';
  String t(String key) => AppStrings.of(context).text('communities.$key');

  Color accent(String categoryId) => Color(
    0xff000000 |
        int.parse(
          widget.options.categories
              .firstWhere((c) => c.id == categoryId)
              .accentHex
              .substring(1),
          radix: 16,
        ),
  );

  @override
  Widget build(BuildContext context) {
    final quota = CommunityTagQuota(selected, widget.options.tags);
    final tags = widget.options.tags.where(
      (tag) =>
          (category == null || tag.categoryId == category) &&
          (query.isEmpty ||
              '${tag.name} ${tag.description}'.toLowerCase().contains(query)),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('tagPicker.title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.profileQuotas
                    ? '${profileText(context, 'quotaCore')} ${quota.core}/3 · '
                          '${profileText(context, 'quotaStyle')} ${quota.reservedStyle}/2 · '
                          '${profileText(context, 'quotaShared')} ${quota.shared}/5'
                    : '${t('tagPicker.selected')} ${selected.length} / ${widget.options.maxTags}',
              ),
              if (widget.profileQuotas) Text(profileText(context, 'quotaHelp')),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 110),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in widget.options.tags.where(
                        (t) => selected.contains(t.id),
                      ))
                        InputChip(
                          key: ValueKey('selected-${tag.id}'),
                          label: Text(tag.name),
                          side: BorderSide(color: accent(tag.categoryId)),
                          backgroundColor: accent(tag.categoryId)
                              .withValues(alpha: .14),
                          onDeleted: () =>
                              setState(() => selected.remove(tag.id)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: t('tagPicker.search'),
                  counterText: '',
                  prefixIcon: const StandardIcon(StandardIconSemantic.search),
                ),
                onChanged: (text) =>
                    setState(() => query = text.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text(t('tagPicker.all')),
                        selected: category == null,
                        onSelected: (_) => setState(() => category = null),
                      ),
                      for (final item in widget.options.categories)
                        Tooltip(
                          message: item.description,
                          child: ChoiceChip(
                            key: ValueKey('category-${item.id}'),
                            label: Text(item.name),
                            side: BorderSide(color: accent(item.id)),
                            selected: category == item.id,
                            onSelected: (_) =>
                                setState(() => category = item.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: tags.isEmpty
                    ? Center(child: Text(t('tagPicker.empty')))
                    : ListView(
                        children: [
                          for (final tag in tags)
                            CheckboxListTile(
                              key: ValueKey('tag-${tag.id}'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              activeColor: accent(tag.categoryId),
                              title: CommunityGameplayTags(
                                value: tag.name,
                                options: widget.options,
                              ),
                              subtitle: Text(tag.description),
                              value: selected.contains(tag.id),
                              onChanged:
                                  !selected.contains(tag.id) &&
                                      (widget.profileQuotas
                                          ? !CommunityTagQuota(
                                              {...selected, tag.id},
                                              widget.options.tags,
                                            ).withinCapacity
                                          : selected.length >=
                                                widget.options.maxTags)
                                  ? null
                                  : (checked) => setState(() {
                                      if (checked == true) {
                                        selected.add(tag.id);
                                      } else {
                                        selected.remove(tag.id);
                                      }
                                    }),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              OverflowBar(
                spacing: 8,
                overflowSpacing: 8,
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(selected.clear),
                    child: Text(t('tagPicker.clear')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t('cancel')),
                  ),
                  FilledButton(
                    onPressed: widget.profileQuotas && !quota.valid
                        ? null
                        : () => Navigator.pop(
                            context,
                            List<String>.unmodifiable(
                              widget.options.tags
                                  .where((t) => selected.contains(t.id))
                                  .map((t) => t.id),
                            ),
                          ),
                    child: Text(t('applyFilters')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
