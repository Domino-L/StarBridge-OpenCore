import 'package:flutter/material.dart';

@immutable
final class TypographyTokens {
  const TypographyTokens({
    required this.uiFamily,
    required this.simplifiedChineseFamily,
    required this.traditionalChineseFamily,
    required this.systemFallbacks,
    required this.monoFamily,
    required this.monoFallbacks,
    required this.display,
    required this.headline,
    required this.title,
    required this.titleSmall,
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.mono,
    required this.monoLarge,
    required this.displayWeight,
    required this.titleWeight,
    required this.bodyWeight,
    required this.emphasisWeight,
    required this.displayTracking,
    required this.bodyHeight,
  });

  final String uiFamily;
  final String simplifiedChineseFamily;
  final String traditionalChineseFamily;
  final List<String> systemFallbacks;
  final String monoFamily;
  final List<String> monoFallbacks;
  final double display;
  final double headline;
  final double title;
  final double titleSmall;
  final double body;
  final double bodySmall;
  final double label;
  final double mono;
  final double monoLarge;
  final FontWeight displayWeight;
  final FontWeight titleWeight;
  final FontWeight bodyWeight;
  final FontWeight emphasisWeight;
  final double displayTracking;
  final double bodyHeight;

  List<String> fallbacksFor(Locale locale) {
    if (locale.languageCode.toLowerCase() != 'zh') {
      return List.unmodifiable(systemFallbacks);
    }
    final script = locale.scriptCode?.toLowerCase();
    final country = locale.countryCode?.toUpperCase();
    final traditional =
        script == 'hant' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO';
    return List.unmodifiable([
      traditional ? traditionalChineseFamily : simplifiedChineseFamily,
      ...systemFallbacks,
    ]);
  }

  TypographyTokens scaled(double factor) {
    return TypographyTokens(
      uiFamily: uiFamily,
      simplifiedChineseFamily: simplifiedChineseFamily,
      traditionalChineseFamily: traditionalChineseFamily,
      systemFallbacks: systemFallbacks,
      monoFamily: monoFamily,
      monoFallbacks: monoFallbacks,
      display: display * factor,
      headline: headline * factor,
      title: title * factor,
      titleSmall: titleSmall * factor,
      body: body * factor,
      bodySmall: bodySmall * factor,
      label: label * factor,
      mono: mono * factor,
      monoLarge: monoLarge * factor,
      displayWeight: displayWeight,
      titleWeight: titleWeight,
      bodyWeight: bodyWeight,
      emphasisWeight: emphasisWeight,
      displayTracking: displayTracking,
      bodyHeight: bodyHeight,
    );
  }

  TypographyTokens withFamilies({
    required String ui,
    required String simplifiedChinese,
    required String traditionalChinese,
    required List<String> system,
    required String mono,
    required List<String> monoFallback,
  }) {
    return TypographyTokens(
      uiFamily: ui,
      simplifiedChineseFamily: simplifiedChinese,
      traditionalChineseFamily: traditionalChinese,
      systemFallbacks: system,
      monoFamily: mono,
      monoFallbacks: monoFallback,
      display: display,
      headline: headline,
      title: title,
      titleSmall: titleSmall,
      body: body,
      bodySmall: bodySmall,
      label: label,
      mono: this.mono,
      monoLarge: monoLarge,
      displayWeight: displayWeight,
      titleWeight: titleWeight,
      bodyWeight: bodyWeight,
      emphasisWeight: emphasisWeight,
      displayTracking: displayTracking,
      bodyHeight: bodyHeight,
    );
  }
}
