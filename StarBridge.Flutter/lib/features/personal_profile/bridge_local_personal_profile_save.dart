import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import 'bridge_local_personal_profile_rebase.dart';
import 'personal_profile_auto_import_validation.dart';
import 'personal_profile_edit_groups.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_local_projection.dart';
import 'personal_profile_models.dart';
import 'personal_profile_presentation.dart';
import 'personal_profile_showcases.dart';

/// SCM writers merge into the raw local content. Editor defaults and
/// projected server values cannot reconstruct an untouched local group.
({Map<String, Object?> content, Set<String> editedGroups})
_mergeLocalProfileSave(
  PersonalProfileSnapshot displayed,
  PersonalProfileEdit edit,
  Map<String, Map<String, Object?>> groups,
  Map<String, Object?>? previous,
  Map<String, Object?>? opened,
) {
  final layout = groups['layout'];
  final previousModules = (previous?['modules'] as List? ?? const [])
      .cast<Map>();
  final displayedPicks = {
    for (final item in displayed.moduleLayout)
      item.moduleId: item.favoriteShipIds,
  };
  final editedModulePicks =
      layout?.containsKey('modules') == true &&
      edit.moduleLayout.any(
        (item) => !listEquals(
          item.favoriteShipIds ?? const <String>[],
          displayedPicks[item.moduleId] ?? const <String>[],
        ),
      );
  final protectLocalPicks =
      savedProfileFavoriteIds(opened)?.isNotEmpty == true &&
      displayed.presentation?.canAutoImport('favorites') == true;
  final explicitPicks = changedLocalProfileFavoriteIds(displayed, edit);
  final replacePicks =
      explicitPicks != null || editedModulePicks && !protectLocalPicks;
  final nextPicks = replacePicks
      ? explicitPicks ?? ProfileFavoriteModules.selections(edit.moduleLayout)
      : null;
  final style = changedPersonalProfilePlayStyle(displayed, edit.playStyle);
  final content = <String, Object?>{...?previous};
  content.putIfAbsent('callSign', () => edit.callSign.trim());
  final fieldStates = <String, Object?>{
    if (previous?['fieldStates'] case final Map states)
      for (final entry in states.entries)
        if (entry.value == true) entry.key as String: true,
  };
  void markDefault(String field, bool isDefault) {
    if (isDefault) {
      fieldStates[field] = true;
    } else {
      fieldStates.remove(field);
    }
  }

  void setValue(String field, Object? value, {required bool isDefault}) {
    content[field] = value;
    markDefault(field, isDefault);
  }

  if (groups.containsKey('introduction')) {
    final introduction = edit.about.trim();
    setValue('introduction', introduction, isDefault: introduction.isEmpty);
  }
  if (groups.containsKey('avatarStyle')) {
    setValue('avatarStyle', edit.avatarStyle, isDefault: edit.avatarStyle == 0);
  }
  if (groups.containsKey('wallpaper')) {
    setValue(
      'wallpaperId',
      edit.wallpaperId,
      isDefault: edit.wallpaperId == 'none',
    );
  }
  if (replacePicks) {
    setValue(
      'favoriteShipIds',
      nextPicks,
      isDefault: nextPicks?.isEmpty == true,
    );
  }
  if (style != null) {
    if (style.roles case final roles?) markDefault('roles', roles.isEmpty);
    if (style.interests case final interests?) {
      markDefault('interests', interests.isEmpty);
    }
    if (style.support case final support?) {
      markDefault('support', support.isEmpty);
    }
  }
  content.addAll({
    if (edit.callSign.trim() != displayed.callSign.trim())
      'callSign': edit.callSign.trim(),
    if (style case final style?) ...{
      'playStyle': {
        ...?(previous?['playStyle'] as Map?)?.cast<String, Object?>(),
        ...style.toJson(),
      }..remove('mainRole'),
      'mainRole': ?style.mainRole,
    },
    if (groups.containsKey('schedule')) 'schedule': edit.schedule!.toJson(),
    if (layout?.containsKey('showcases') == true ||
        layout?.containsKey('modules') == true)
      'showcases': PersonalProfileShowcases.wire(
        PersonalProfileLayout.normalize(edit.moduleLayout),
      ),
    if (layout?.containsKey('achievementShowcase') == true)
      'achievementShowcase': edit.achievementShowcase,
  });
  if (groups.containsKey('schedule')) {
    markDefault('schedule', isDefaultProfileSchedule(edit.schedule!));
  }

  if (layout?.containsKey('modules') == true) {
    final modules = [
      for (final item in PersonalProfileShowcases.modulesOf(edit.moduleLayout))
        {
          'id': item.moduleId,
          'span': item.size.span,
          'isVisible': item.isVisible,
          'position': item.position,
          if (item.favoriteShipIds != null && explicitPicks == null)
            'favoriteShipIds': item.favoriteShipIds,
        },
    ];
    content['modules'] = replacePicks
        ? modules
        : _keepLocalModulePicks(modules, previousModules);
  } else if (explicitPicks != null &&
      previous?.containsKey('modules') == true) {
    content['modules'] = _keepLocalModulePicks(previousModules, const []);
  }
  if (fieldStates.containsKey('modules') ||
      layout?.containsKey('modules') == true ||
      layout?.containsKey('showcases') == true) {
    markDefault('modules', !hasSavedProfileLayout(content));
  }
  if (fieldStates['modules'] == true) {
    content.putIfAbsent('modules', () => const <Object?>[]);
  }
  if (fieldStates.isEmpty) {
    content.remove('fieldStates');
  } else {
    content['fieldStates'] = fieldStates;
  }
  return (
    content: content,
    editedGroups: {
      if (edit.callSign.trim() != displayed.callSign.trim()) 'callSign',
      for (final group in const [
        'introduction',
        'avatarStyle',
        'wallpaper',
        'schedule',
      ])
        if (groups.containsKey(group)) group,
      if (style != null) 'playStyle',
      if (layout?.containsKey('modules') == true ||
          layout?.containsKey('showcases') == true ||
          layout?.containsKey('achievementShowcase') == true)
        'layout',
      if (replacePicks) 'favorites',
    },
  );
}

// Host validates that flat favorites and module picks agree. A new structure
// that cannot hold the old assignments keeps the existing local modules.
List<Map> _keepLocalModulePicks(List<Map> modules, List<Map> previous) {
  final picks = {
    for (final item in previous)
      if (item['favoriteShipIds'] case final List ids) item['id']: ids,
  };
  final spans = {for (final item in modules) item['id']: item['span'] as int};
  if (picks.entries.any(
    (entry) => (spans[entry.key] ?? -1) < entry.value.length,
  )) {
    return previous;
  }
  return [
    for (final item in modules)
      {
        for (final entry in item.entries)
          if (entry.key != 'favoriteShipIds') entry.key: entry.value,
        'favoriteShipIds': ?picks[item['id']],
      },
  ];
}

typedef LocalProfileRevision = ({int revision, Map<String, Object?>? content});

LocalProfileRevision parseLocalProfileRevision(Map<String, Object?> payload) {
  final revision = payload['revision'] as int;
  final wire = (payload['content'] as Map?)?.cast<String, Object?>();
  if (revision < 0 || (revision == 0) != (wire == null)) {
    throw const FormatException();
  }
  if (wire == null) return (revision: revision, content: null);

  return (revision: revision, content: wire);
}

const _retryLocalProfileEdit = PersonalProfileActionResult(
  PersonalProfileActionOutcome.rejected,
  failureKey: 'profile.error.retryLocalDraft',
);

/// A content event may queue a UI refresh until the editor closes. Recover the
/// local revision here without replacing that editor's displayed baseline.
final class LocalProfileSaveBaseline {
  LocalProfileSaveBaseline(this._opened) : _latest = _opened;

  final LocalProfileRevision _opened;
  LocalProfileRevision _latest;
  final _reviewed = <String, Map<String, Object?>?>{};
  ({String content, String id})? _pending;
  bool _needsRead = false;

  Future<PersonalProfileActionResult?> save({
    required PersonalProfileSnapshot displayed,
    required PersonalProfileEdit edit,
    required Map<String, Map<String, Object?>> groups,
    required bool legacyRelay,
    required bool Function() current,
    required Future<Map<String, Object?>> Function(
      String name,
      Map<String, Object?> payload,
    )
    request,
  }) async {
    if (legacyRelay) {
      return _saveLegacyRelay(displayed, edit, current, request);
    }
    for (var attempt = 0; ; attempt++) {
      if (_needsRead) {
        LocalProfileRevision fresh;
        try {
          fresh = parseLocalProfileRevision(
            await request('personalProfile.localRead', const {}),
          );
        } on Object {
          return current() ? _retryLocalProfileEdit : staleProfileEdit;
        }
        if (!current()) return staleProfileEdit;
        if (fresh.revision <= _latest.revision) return _retryLocalProfileEdit;
        _latest = fresh;
        _needsRead = false;
      }

      final (:content, :editedGroups) = _mergeLocalProfileSave(
        displayed,
        edit,
        groups,
        _latest.content,
        _opened.content,
      );
      final conflicts = editedGroups
          .where(
            (group) => !_sameLocalGroup(
              group,
              _reviewed.containsKey(group) ? _reviewed[group] : _opened.content,
              _latest.content,
            ),
          )
          .toList();
      if (conflicts.isNotEmpty) {
        for (final group in conflicts) {
          _reviewed[group] = _latest.content;
        }
        return confirmProfileEditConflict;
      }

      final encoded = jsonEncode(content);
      if (_pending?.content != encoded) {
        final random = Random.secure();
        _pending = (
          content: encoded,
          id: List.generate(
            16,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join(),
        );
      }
      final operation = _pending!.id;
      try {
        final response = await request('personalProfile.localSave', {
          'expectedRevision': _latest.revision,
          'operationId': operation,
          'content': content,
        });
        if (!current()) return staleProfileEdit;
        if (response['operationId'] != operation ||
            response['revision'] != _latest.revision + 1) {
          throw const FormatException();
        }
        return null;
      } on BridgeRemoteException catch (error) {
        if (error.code != 'profile_local.conflict') rethrow;
        if (!current()) return staleProfileEdit;
        _pending = null;
        _needsRead = true;
        if (attempt > 0) return _retryLocalProfileEdit;
      }
    }
  }

  Future<PersonalProfileActionResult?> _saveLegacyRelay(
    PersonalProfileSnapshot displayed,
    PersonalProfileEdit edit,
    bool Function() current,
    Future<Map<String, Object?>> Function(String, Map<String, Object?>) request,
  ) async {
    // The legacy editor saves the full displayed draft, including inherited
    // values. The opening revision protects the whole draft from a stale save.
    final previous = _opened.content;
    final content = <String, Object?>{
      'callSign': edit.callSign.trim(),
      'introduction': edit.about.trim(),
      'avatarStyle': edit.avatarStyle,
      'wallpaperId': edit.wallpaperId,
      'preserveEmptyFields': true,
      'favoriteShipIds':
          edit.favoriteShipIds ??
          ProfileFavoriteModules.selections(edit.moduleLayout) ??
          displayed.local!.favoriteShipIds,
      if (edit.playStyle != null || previous?['playStyle'] != null)
        'playStyle': {
          ...?(previous?['playStyle'] as Map?)?.cast<String, Object?>(),
          ...?edit.playStyle?.toJson(),
        }..remove('mainRole'),
      'mainRole': ?(edit.playStyle?.mainRole ?? previous?['mainRole']),
      if (edit.schedule != null || previous?['schedule'] != null)
        'schedule': edit.schedule?.toJson() ?? previous?['schedule'],
      'showcases': PersonalProfileShowcases.wire(
        PersonalProfileLayout.normalize(edit.moduleLayout),
      ),
      'achievementShowcase':
          ?(edit.achievementShowcase ?? previous?['achievementShowcase']),
      'modules': [
        for (final item in PersonalProfileShowcases.modulesOf(edit.moduleLayout))
          {
            'id': item.moduleId,
            'span': item.size.span,
            'isVisible': item.isVisible,
            'position': item.position,
            if (item.favoriteShipIds != null && edit.favoriteShipIds == null)
              'favoriteShipIds': item.favoriteShipIds,
          },
      ],
    };
    final encoded = jsonEncode(content);
    if (_pending?.content != encoded) {
      final random = Random.secure();
      _pending = (
        content: encoded,
        id: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      );
    }
    final operation = _pending!.id;
    final response = await request('personalProfile.localSave', {
      'expectedRevision': _opened.revision,
      'operationId': operation,
      'content': content,
    });
    if (!current()) return staleProfileEdit;
    if (response['operationId'] != operation ||
        response['revision'] != _opened.revision + 1) {
      throw const FormatException();
    }
    return null;
  }
}

bool _sameLocalGroup(
  String group,
  Map<String, Object?>? opened,
  Map<String, Object?>? latest,
) {
  if (group == 'playStyle') {
    final left = opened?['playStyle'] as Map?;
    final right = latest?['playStyle'] as Map?;
    return opened?['mainRole'] == latest?['mainRole'] &&
        const ['roles', 'interests', 'support'].every(
          (field) => PersonalProfilePresentation.samePlayStyleField(
            left?[field],
            right?[field],
          ),
        );
  }

  Object? values(Map<String, Object?>? content) => switch (group) {
    'introduction' => content?['introduction'] ?? '',
    'avatarStyle' => content?['avatarStyle'] ?? 0,
    'wallpaper' => content?['wallpaperId'] ?? 'none',
    'layout' => [
      content?['modules'],
      content?['showcases'],
      content?['achievementShowcase'],
    ],
    'favorites' => [
      savedProfileFavoriteIds(content),
      {
        for (final module
            in (content?['modules'] as List? ?? const []).cast<Map>())
          if (module['favoriteShipIds'] case final List ids when ids.isNotEmpty)
            module['id']: ids,
      },
    ],
    _ => content?[group],
  };
  return PersonalProfilePresentation.sameValue(values(opened), values(latest));
}
