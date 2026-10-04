import 'package:flutter/foundation.dart';

import '../../platform/window/menu_browser_resume.dart';

/// Shared by settings and browser within one opening. No timers, account keys,
/// URL history or disk access. Confirmed native status feeds the existing path.
class MenuBrowserResumeController extends ChangeNotifier {
  MenuBrowserResumeController(this.port);
  final MenuBrowserResumePort port;
  MenuBrowserResume? saved;
  bool busy = false, failed = false, closed = false;
  int _epoch = 0;
  Future<void>? _loading, _writing;
  String? _pending, _remembered;
  void _notify() {
    if (!closed) notifyListeners();
  }

  Future<void> load() async {
    if (closed) return;
    if (_loading case final pending?) return pending;
    final work = _load();
    _loading = work;
    try {
      await work;
    } finally {
      _loading = null;
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    busy = true;
    failed = false;
    _notify();
    try {
      final value = await port.read();
      if (closed || epoch != _epoch) return;
      saved = value;
      _remembered = value.url;
    } on Object {
      if (!closed && epoch == _epoch) {
        saved = null;
        _remembered = null;
        failed = true;
      }
    } finally {
      if (!closed && epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final current = saved;
    if (closed || busy || current == null) return;
    final epoch = ++_epoch;
    _pending = null;
    busy = true;
    failed = false;
    _notify();
    try {
      final value = await port.setEnabled(current, enabled);
      if (closed || epoch != _epoch) return;
      saved = value;
      _remembered = value.url;
    } on Object {
      if (!closed && epoch == _epoch) {
        failed = true;
        saved = null;
        _remembered = null;
      }
    } finally {
      if (!closed && epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> confirmed(String url) async {
    if (closed ||
        busy ||
        saved?.enabled != true ||
        !MenuBrowserResume.validUrl(url) ||
        url == _remembered) {
      return;
    }
    _pending = url;
    if (_writing case final pending?) return pending;
    final work = _flush();
    _writing = work;
    try {
      await work;
    } finally {
      _writing = null;
    }
  }

  Future<void> _flush() async {
    while (!closed && !busy && _pending != null && saved?.enabled == true) {
      final url = _pending!, current = saved!, epoch = _epoch;
      _pending = null;
      try {
        final value = await port.remember(current, url);
        if (closed || epoch != _epoch) return;
        saved = value;
        _remembered = value.url;
        failed = false;
        _notify();
      } on Object {
        if (closed || epoch != _epoch) return;
        // A policy changed in the main client (or revoked account) never keeps
        // saving with old consent. Require an explicit re-read, not a poller.
        _pending = null;
        saved = null;
        _remembered = null;
        failed = true;
        _notify();
        return;
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    ++_epoch;
    _pending = null;
    saved = null;
    _remembered = null;
    super.dispose();
  }
}
