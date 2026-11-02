import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import 'communities_module.dart';

/// Directory query controls only. Account ownership and request arbitration stay
/// in the existing module; the page retains its controller and filter route.
List<Widget> communityDirectoryControls({
  required CommunitiesModule model,
  required TextEditingController search,
  required String Function(String) text,
  required bool showFilterButton,
  required Future<void> Function() onFilters,
}) => [
  Row(
    children: [
      Expanded(
        child: StarBridgeFieldFrame(
          enabled: !model.writing,
          builder: (_, focus) => TextField(
            focusNode: focus,
            controller: search,
            maxLength: 128,
            decoration: InputDecoration(
              labelText: text('search'),
              counterText: '',
            ),
            enabled: !model.writing,
            onSubmitted: (_) => unawaited(
              runStarBridgeActivation<void>(
                InteractionSource.keyboard,
                () => model.refresh(newQuery: search.text),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      StarBridgeActionButton(
        controlKey: const Key('community-directory-search'),
        onActivate: model.writing
            ? null
            : (_) => model.refresh(newQuery: search.text),
        child: Text(text('searchButton')),
      ),
    ],
  ),
  const SizedBox(height: 12),
  if (model.view == 'discover') ...[
    Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showFilterButton)
          StarBridgeActionButton(
            controlKey: const Key('community-directory-filters'),
            onActivate: model.writing ? null : (_) => onFilters(),
            child: Text(text('filters')),
          ),
        SizedBox(
          width: 180,
          child: StarBridgeSelectFormField<String>(
            identity: ('community-directory-sort', model.filters),
            controlKey: const ValueKey('community-directory-sort-control'),
            isExpanded: true,
            initialValue: model.filters == null
                ? 'recommended'
                : (jsonDecode(model.filters!) as Map)['sort'] as String? ??
                      'recommended',
            key: ValueKey('sort-${model.filters}'),
            decoration: InputDecoration(labelText: text('sort')),
            items: [
              for (final sort in ['recommended', 'recent', 'members', 'name'])
                DropdownMenuItem(value: sort, child: Text(text('sort.$sort'))),
            ],
            onChanged: model.writing
                ? null
                : (sort) {
                    final filters = model.filters == null
                        ? <String, dynamic>{}
                        : Map<String, dynamic>.from(jsonDecode(model.filters!));
                    filters['sort'] = sort;
                    unawaited(model.refresh(newFilters: jsonEncode(filters)));
                  },
          ),
        ),
        if (model.directory?.totalCount != null)
          Text('${model.directory!.totalCount} ${text('resultCount')}'),
        if (model.filters != null && model.filters != '{}')
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('community-directory-reset'),
            onActivate: model.writing
                ? null
                : (_) => model.refresh(newFilters: '{}'),
            child: Text(text('reset')),
          ),
      ],
    ),
    const SizedBox(height: 12),
  ],
];
