import 'package:flutter/material.dart';

abstract final class BridgeInk {
  // Constant-only menu chrome mirrors the client dark tokens. Regression
  // tests compare these aliases against FutureRestraintStyle.
  static const text = Color(0xffe7eef2);
  static const muted = Color(0xff93a4ae);
  static const blue = Color(0xff4cb2f5);
  static const line = Color(0xff4c616e);
  static const green = Color(0xff3ed59a);
  static const amber = Color(0xfff5b544);
  static const danger = Color(0xfff26d75);
  static const ground = Color(0xff080c10);
  // Match client panel RGB; opacity is specific to the menu desktop.
  static const panel = Color(0xee111920);
  // Windows are reading surfaces, distinct from the translucent desktop chrome.
  static const window = Color(0xfa111920);
  static const divider = Color(0xff26333c);
  static const selected = Color(0xff173348);
  static const scrim = Color(0x85000000);
}
