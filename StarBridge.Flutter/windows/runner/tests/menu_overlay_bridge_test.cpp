#include "menu_overlay_bridge.h"
#include "menu_fixture_messenger.h"
#include "menu_screenshot_settings_intent.h"
#include <cstdio>
#include <windows.h>

// Exercises the real encoded channel, without creating a Flutter engine/Host.
int main(int argc, char** argv) {
  const bool hidden_engine = argc == 2 && std::string(argv[1]) == "--hidden-engine";
  const HWND original_foreground = GetForegroundWindow();
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  int failed = 0;
  auto check = [&failed](bool condition, const char* name) {
    printf("%s|%s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) ++failed;
  };
  FixtureMessenger messenger;
  {
    Map intent{{Value("opening"), Value(1)}, {Value("action"), Value("read")}};
    check(ValidScreenshotSettingsIntent(intent), "directory read intent accepted");
    intent[Value("path")] = Value("C:\\forbidden");
    check(!ValidScreenshotSettingsIntent(intent), "directory path injection rejected");
    intent.erase(Value("path"));
    for (const char* action : {"choose", "reset", "open"}) {
      intent[Value("action")] = Value(action);
      intent[Value("revision")] = Value(int64_t{0});
      check(ValidScreenshotSettingsIntent(intent), "directory revision-only intent accepted");
      intent[Value("revision")] = Value(-1);
      check(!ValidScreenshotSettingsIntent(intent), "negative directory revision rejected");
      intent[Value("revision")] = Value(0.0);
      check(!ValidScreenshotSettingsIntent(intent), "non-integer directory revision rejected");
    }
    intent[Value("action")] = Value("write");
    check(!ValidScreenshotSettingsIntent(intent), "unknown directory action rejected");
  }
  {
    MenuOverlayBridge bridge(&messenger);
    check(messenger.Call("open") == "menu.unavailable", "opening requires configuration");
    check(messenger.Call("shortcut") == "menu.shortcut_unavailable", "no shortcut before configuration");
    check(messenger.Call("configure") == "menu.invalid_configuration", "invalid configuration rejected");
    check(messenger.Call("preview") == "menu.invalid_configuration", "preview requires validated presentation labels");
    check(messenger.Call("attentionView", Value(Map{{Value("opening"), Value(1)},
        {Value("revision"), Value(1)}, {Value("payload"), Value("{\"friends\":1,\"comms\":2,\"rooms\":3,\"organizations\":4}")}})) == "success",
        "unopened count-only presentation is ignored without acquiring account authority");
    check(messenger.Call("handoffProfile", Value(Map{{Value("opening"), Value(1)}})) == "success" &&
        std::get<bool>(messenger.last_result) == false, "profile handoff cannot activate an unconfigured client");
    check(messenger.Call("noticeView", Value(Map{{Value("opening"), Value(1)},
        {Value("revision"), Value(1)}, {Value("payload"), Value("{\"title\":\"Fixture\",\"message\":\"Notice\"}")}})) == "success",
        "unopened redacted notice is ignored without acquiring account authority");
    Map config{{Value("schemaVersion"), Value(1)}, {Value("contextLabel"), Value("Fixture")},
        {Value("returnLabel"), Value("Return")}, {Value("settingsLabel"), Value("Settings")}};
    check(messenger.Call("configure", Value(config)) == "success", "valid labels accepted");
    auto delayed = config;
    delayed[Value("targetWindow")] = Value(int64_t{1});
    delayed[Value("targetProcessId")] = Value(int64_t{42});
    check(messenger.Call("preview", Value(delayed)) == "menu.foreground_changed",
        "delayed hotkey for missing foreground cannot create an engine");
    delayed.erase(Value("targetProcessId"));
    check(messenger.Call("preview", Value(delayed)) == "menu.invalid_configuration",
        "hotkey target requires both handle and process identity");
    if (hidden_engine) {
      check(messenger.Call("open") == "success", "prepare real auxiliary engine");
      // Cancel before pumping any native frame messages; never display UI.
      check(messenger.Call("close") == "success", "cancel real engine opening before reveal");
      bool ready = false;
      const auto start = GetTickCount64();
      while (!ready && GetTickCount64() - start < 20000) {
        MSG msg{};
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
          TranslateMessage(&msg); DispatchMessageW(&msg);
        }
        messenger.Call("status");
        if (const auto* status = std::get_if<Map>(&messenger.last_result)) {
          const auto item = status->find(Value("dartReady"));
          const auto* flag = item != status->end() ? std::get_if<bool>(&item->second) : nullptr;
          ready = flag && *flag;
        }
        Sleep(10);
      }
      check(ready, "menuMain completed real method-channel handshake while hidden");
      HWND menu = FindWindowW(L"StarBridge.Flutter.MenuOverlay.v1", nullptr);
      check(menu && !IsWindowVisible(menu), "auxiliary surface remains hidden");
      check(GetForegroundWindow() == original_foreground, "engine fixture never changes foreground");
    }
    config[Value("contextLabel")] = Value(std::string(513, 'x'));
    check(messenger.Call("configure", Value(config)) == "menu.invalid_configuration", "oversized label rejected");
    check(messenger.Call("future-command") == "not_implemented", "unknown command not executed");
    check(messenger.Call("close") == "success", "unopened close safe");
    check(messenger.Call("detach") == "success", "detach safe");
    check(messenger.Call("open") == "menu.unavailable", "detach revokes opening");
    check(messenger.Call("handoffProfile", Value(Map{{Value("opening"), Value(1)}})) == "success" &&
        std::get<bool>(messenger.last_result) == false, "detach revokes profile handoff");
    config[Value("contextLabel")] = Value("Fixture");
    config[Value("request")] = Value(int64_t{41});
    check(messenger.Call("configure", Value(config)) == "success", "scoped owner configured");
    check(messenger.Call("detach", Value(Map{{Value("request"), Value(int64_t{40})}})) == "success",
        "stale detach is harmless");
    messenger.Call("status");
    check(std::get<bool>(std::get<Map>(messenger.last_result).at(Value("configured"))),
        "old owner cannot revoke new configuration");
    messenger.Call("detach");
    messenger.Call("status");
    check(std::get<bool>(std::get<Map>(messenger.last_result).at(Value("configured"))),
        "unscoped detach cannot revoke scoped configuration");
    messenger.Call("detach", Value(Map{{Value("request"), Value(int64_t{41})}}));
    messenger.Call("status");
    check(!std::get<bool>(std::get<Map>(messenger.last_result).at(Value("configured"))),
        "current owner can revoke configuration");
    config[Value("request")] = Value(-1);
    check(messenger.Call("configure", Value(config)) == "menu.invalid_configuration", "invalid request rejected");
  }
  check(!messenger.handlers.at("starbridge/menu-primary"), "destructor unregisters channel");
  CoUninitialize();
  return failed == 0 ? 0 : 1;
}
