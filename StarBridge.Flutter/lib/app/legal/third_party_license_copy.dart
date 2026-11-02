import 'package:flutter/widgets.dart';

/// Browser status only; license paragraphs are never translated or rewritten.
({String loading, String failed, String retry}) thirdPartyLicenseCopy(
  BuildContext context,
) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode != 'zh') {
    return (
      loading: 'Loading licenses…',
      failed: 'Licenses could not be fully loaded. Try again.',
      retry: 'Try again',
    );
  }
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
    return (loading: '正在讀取授權條款…', failed: '授權條款未能完整讀取，請重試。', retry: '重試');
  }
  return (loading: '正在读取许可条款…', failed: '许可条款未能完整读取，请重试。', retry: '重试');
}
