import 'dart:async';

import 'menu_organization_avatars.dart';

/// Accept the client's bounded inline account photo, send only a thumbnail to
/// the auxiliary engine. A replaced account/source can never publish late data.
final class MenuAccountAvatar {
  MenuAccountAvatar(this.changed);
  final void Function() changed;
  final _images = MenuOrganizationAvatars();
  String? _source, _value;
  int _epoch = 0;
  String? read(String? source) {
    if (_source != source) {
      _source = source;
      _value = null;
      final epoch = ++_epoch;
      if (source != null) {
        unawaited(
          _images.logo(source).then((value) {
            if (epoch != _epoch || source != _source) return;
            _value = value;
            if (value != null) changed();
          }),
        );
      }
    }
    return _value;
  }

  void clear() {
    _epoch++;
    _source = _value = null;
    _images.clear();
  }

  void dispose() {
    clear();
    _images.dispose();
  }
}
