import 'dart:convert';

import 'overlay_settings_models.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_port.dart';
import 'overlay_workspace_projection.dart';

/// The revision-checked write of the active plan's settings and layout.
OverlayWorkspaceMutation overlaySaveMutation(OverlayWorkspaceProjection p) =>
    OverlayWorkspaceMutation.saveActive(
      settings: p.settings!,
      layout: p.layout,
      renderMode: p.renderMode!,
      hotkey: p.hotkey!,
      sources: p.sources,
      appearanceOptions: p.snapshot!.appearanceOptionsEnabled
          ? p.appearanceOptions
          : null,
    );

/// Direct save: writes the current draft without blocking further edits.
/// Edits made during a write are written next; undo history is untouched.
/// A lost revision race re-reads once and re-applies only this device's
/// changes ([rebaseOverlayDraft]). True when nothing is left unsaved.
Future<bool> commitOverlayDraft({
  required OverlayWorkspacePort port,
  required OverlayWorkspaceProjection Function() read,
  required void Function(OverlayWorkspaceProjection value) write,
  required bool Function() disposed,
  required void Function() resetHistory,
}) async {
  var start = read();
  var conflicts = 0;
  for (var attempt = 0; attempt < 6; attempt++) {
    final revision = start.snapshot?.revision;
    if (disposed() || !start.available || revision == null) return false;
    if (!start.dirty) return true;
    final result = await port.apply(
      overlaySaveMutation(start),
      expectedRevision: revision,
    );
    if (disposed()) return false;
    if (result.completed) {
      final latest = read();
      final saved = OverlayWorkspaceProjection.fromSnapshot(
        result.snapshot!,
        runtime: latest.runtime,
      );
      write(
        overlaySameDraft(latest, start)
            ? saved.copyWith(runtimeOperation: latest.runtimeOperation)
            : latest.copyWith(snapshot: result.snapshot, clearFailure: true),
      );
      start = read();
      continue;
    }
    if (result.failure != OverlaySettingsFailure.writeConflict ||
        ++conflicts > 1) {
      write(
        read().copyWith(
          failure: result.failure ?? OverlaySettingsFailure.writeFailed,
        ),
      );
      return false;
    }
    final OverlayWorkspaceSnapshot latest;
    try {
      latest = await port.read();
    } on Object {
      if (!disposed()) {
        write(read().copyWith(failure: OverlaySettingsFailure.writeConflict));
      }
      return false;
    }
    if (disposed()) return false;
    final rebased = rebaseOverlayDraft(read(), latest);
    if (rebased == null) {
      resetHistory();
      write(
        OverlayWorkspaceProjection.fromSnapshot(
          latest,
          runtime: read().runtime,
        ).copyWith(failure: OverlaySettingsFailure.writeConflict),
      );
      return false;
    }
    write(rebased);
    start = rebased;
  }
  return !read().dirty;
}

/// The parts of a projection that a commit writes.
bool overlaySameDraft(
  OverlayWorkspaceProjection a,
  OverlayWorkspaceProjection b,
) =>
    identical(a.settings, b.settings) &&
    identical(a.layout, b.layout) &&
    a.renderMode == b.renderMode &&
    identical(a.hotkey, b.hotkey) &&
    identical(a.sources, b.sources) &&
    identical(a.appearanceOptions, b.appearanceOptions);

/// Re-applies this device's unsaved edits onto a newer saved workspace after
/// another writer (for example the in-game quick panel) won the revision.
/// Settings merge by field and layout by item; hotkey, sources, appearance
/// options and render mode move as wholes. Only values this device changed
/// replace the newer ones. Null when the active plan changed: those edits
/// were made for another plan and are not carried over.
OverlayWorkspaceProjection? rebaseOverlayDraft(
  OverlayWorkspaceProjection draft,
  OverlayWorkspaceSnapshot latest,
) {
  final saved = draft.snapshot;
  if (saved == null ||
      latest.availability != OverlayWorkspaceAvailability.available ||
      latest.activePresetId != saved.activePresetId) {
    return null;
  }
  final base = OverlayWorkspaceProjection.fromSnapshot(saved);
  final fresh = OverlayWorkspaceProjection.fromSnapshot(
    latest,
    runtime: draft.runtime,
  );
  String key(Object? value) => jsonEncode(value);
  var settings = fresh.settings!;
  for (final entry in draft.settings!.values.entries) {
    if (key(entry.value) != key(base.settings![entry.key])) {
      settings = settings.withValue(entry.key, entry.value);
    }
  }
  final before = {for (final item in base.layout) item.key: key(item.toMap())};
  final edited = {
    for (final item in draft.layout)
      if (key(item.toMap()) != before[item.key]) item.key: item,
  };
  T? changed<T>(T value, T original, String Function(T) encode) =>
      encode(value) == encode(original) ? null : value;
  return fresh.copyWith(
    settings: settings,
    layout: [for (final item in fresh.layout) edited[item.key] ?? item],
    renderMode: changed<String?>(
      draft.renderMode,
      base.renderMode,
      (v) => v ?? '',
    ),
    hotkey: changed(draft.hotkey!, base.hotkey!, (v) => key(v.toUpdateMap())),
    sources: draft.sources == null
        ? null
        : changed<OverlayPresetSources?>(
            draft.sources,
            base.sources,
            (v) => key(v?.toMap()),
          ),
    appearanceOptions: changed(
      draft.appearanceOptions,
      base.appearanceOptions,
      (v) => key(v.toMap()),
    ),
    dirty: true,
  );
}
