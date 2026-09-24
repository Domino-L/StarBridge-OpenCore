#include "menu_overlay_bridge.h"
#include "menu_fixture_messenger.h"
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
    MenuOverlayBridge bridge(&messenger);
    check(messenger.Call("open") == "menu.unavailable", "opening requires configuration");
    check(messenger.Call("shortcut") == "menu.shortcut_unavailable", "no shortcut before configuration");
    check(messenger.Call("configure") == "menu.invalid_configuration", "invalid configuration rejected");
    check(messenger.Call("preview") == "menu.invalid_configuration", "preview requires validated presentation labels");
    check(messenger.Call("handoffProfile", Value(Map{{Value("opening"), Value(1)}})) == "success" &&
        std::get<bool>(messenger.last_result) == false, "profile handoff cannot activate an unconfigured client");
    Map config{{Value("schemaVersion"), Value(1)}, {Value("contextLabel"), Value("Fixture")},
        {Value("returnLabel"), Value("Return")}, {Value("settingsLabel"), Value("Settings")}};
    check(messenger.Call("configure", Value(config)) == "success", "valid labels accepted");
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
  }
  check(!messenger.handlers.at("starbridge/menu-primary"), "destructor unregisters channel");
  CoUninitialize();
  return failed == 0 ? 0 : 1;
}
