import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Already-redacted text only. No account, conversation or command identifiers.
final class MenuNotice {
  const MenuNotice(this.title, this.message);
  final String title, message;
  Map<String, String> toMap() => {'title': title, 'message': message};
  static MenuNotice? parse(Object? payload) {
    if (payload is! String || payload.length > 65536) return null;
    try {
      final raw = jsonDecode(payload);
      if (raw is! Map ||
          raw.length != 2 ||
          raw['title'] is! String ||
          raw['message'] is! String ||
          (raw['title'] as String).length > 1024 ||
          (raw['message'] as String).length > 8192) {
        return null;
      }
      return MenuNotice(raw['title'] as String, raw['message'] as String);
    } on Object {
      return null;
    }
  }
}

abstract interface class MenuNoticeSource
    implements ValueListenable<MenuNotice?> {
  void clear();
  void dispose();
}

abstract interface class MenuNoticeDeliveryOwner {
  bool get menuNoticeDeliveryActive;
}

/// Primary-engine identity only; never serialized to the menu surface.
abstract interface class MenuConversationVisibility {
  String? get visibleConversationKey;
}

abstract interface class MenuNoticeReadingContext {
  set visibleConversationKey(String? Function()? read);
  set menuSettings(Map? Function()? read);
}
