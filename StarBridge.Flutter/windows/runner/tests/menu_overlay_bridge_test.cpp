#include "menu_overlay_bridge.h"
#include "menu_fixture_messenger.h"
#include "menu_screenshot_settings_intent.h"
#include "menu_exec_hangar_intent.h"
#include "menu_tool_page_intent.h"
#include <cstdio>
#include <windows.h>

// Exercises the real encoded channel, without creating a Flutter engine/Host.
int main(int argc, char** argv) {
  setvbuf(stdout, nullptr, _IONBF, 0);
  const bool hidden_engine = argc == 2 && std::string(argv[1]) == "--hidden-engine";
  const bool image_engine = argc == 2 && std::string(argv[1]) == "--image-retirement-engine";
  const HWND original_foreground = GetForegroundWindow();
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  int failed = 0;
  auto check = [&failed](bool condition, const char* name) {
    printf("%s|%s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) ++failed;
  };
  FixtureMessenger messenger;
  {
    Map intent{{Value("opening"),Value(7)},{Value("action"),Value("pin")}};
    for (const char* position : {"topLeft", "topCenter", "topRight", "bottomRight", "bottomCenter", "bottomLeft"}) {
      intent[Value("position")] = Value(position);
      check(ValidMenuExecHangarGameIntent(intent,7,true,true,true,false),"game hangar exact anchor accepted");
    }
    check(!ValidMenuExecHangarGameIntent(intent,8,true,true,true,false),"game hangar stale opening rejected");
    check(!ValidMenuExecHangarGameIntent(intent,7,false,true,true,false),"game hangar missing capability rejected");
    check(!ValidMenuExecHangarGameIntent(intent,7,true,false,true,false),"game hangar retired owner rejected");
    check(!ValidMenuExecHangarGameIntent(intent,7,true,true,false,false),"game hangar hidden menu rejected");
    check(!ValidMenuExecHangarGameIntent(intent,7,true,true,true,true),"game hangar modal rejected");
    intent[Value("position")]=Value("center");
    check(!ValidMenuExecHangarGameIntent(intent,7,true,true,true,false),"game hangar unapproved anchor rejected");
    intent[Value("position")]=Value("topLeft");intent[Value("payload")]=Value("{}");
    check(!ValidMenuExecHangarGameIntent(intent,7,true,true,true,false),"game hangar arbitrary payload rejected");
    intent.erase(Value("payload"));intent.erase(Value("position"));intent[Value("action")]=Value("unpin");
    check(ValidMenuExecHangarGameIntent(intent,7,true,true,true,false),"game hangar unpin accepted");
    intent[Value("action")]=Value("read");
    check(ValidMenuExecHangarGameIntent(intent,7,true,true,true,false),"game hangar read accepted");
    intent[Value("action")]=Value("stop");
    check(!ValidMenuExecHangarGameIntent(intent,7,true,true,true,false),"game hangar reminder stop rejected");
    intent[Value("action")]=Value("read");intent[Value("opening")]=Value(7.0);
    check(!ValidMenuExecHangarGameIntent(intent,7,true,true,true,false),"game hangar fractional opening rejected");
  }
  {
    Map intent{{Value("opening"), Value(7)}};
    check(ValidMenuExecHangarIntent(intent, 7, true, true, true, false), "hangar summary exact opening accepted");
    check(!ValidMenuExecHangarIntent(intent, 8, true, true, true, false), "hangar stale opening rejected");
    check(!ValidMenuExecHangarIntent(intent, 7, false, true, true, false), "hangar missing capability rejected");
    check(!ValidMenuExecHangarIntent(intent, 7, true, true, false, false), "hangar hidden menu rejected");
    check(!ValidMenuExecHangarIntent(intent, 7, true, false, true, false), "hangar retired owner rejected");
    check(!ValidMenuExecHangarIntent(intent, 7, true, true, true, true), "hangar local modal rejected");
    intent[Value("payload")] = Value("{\"action\":\"stop\"}");
    check(!ValidMenuExecHangarIntent(intent, 7, true, true, true, false), "hangar monitoring payload rejected");
    intent.erase(Value("payload")); intent[Value("opening")] = Value(7.0);
    check(!ValidMenuExecHangarIntent(intent, 7, true, true, true, false), "hangar noninteger opening rejected");
  }
  {
    Map intent{{Value("opening"), Value(7)}};
    check(ValidMenuToolPageIntent(intent, 7, true, true, false), "hud settings page needs no hangar capability");
    check(!ValidMenuToolPageIntent(intent, 8, true, true, false), "hud settings stale opening rejected");
    check(!ValidMenuToolPageIntent(intent, 7, true, false, false), "hud settings hidden menu rejected");
    check(!ValidMenuToolPageIntent(intent, 7, false, true, false), "hud settings retired owner rejected");
    check(!ValidMenuToolPageIntent(intent, 7, true, true, true), "hud settings local modal rejected");
    check(!ValidMenuToolPageIntent(intent, 0, true, true, false), "hud settings before first opening rejected");
    intent[Value("route")] = Value("/settings/privacy");
    check(!ValidMenuToolPageIntent(intent, 7, true, true, false), "hud settings renderer route rejected");
  }
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
    Map retire{{Value("schemaVersion"), Value(1)}, {Value("resourceEpoch"), Value(int64_t{1})}};
    check(messenger.Call("imageMaintenance", Value(retire)) == "success",
        "image retirement before configuration is resource-only");
    check(!std::get<bool>(std::get<Map>(messenger.last_result).at(Value("enginePresent"))),
        "image retirement never creates an engine");
    auto bad_retire = retire;
    bad_retire[Value("resourceEpoch")] = Value(int64_t{-1});
    check(messenger.Call("imageMaintenance", Value(bad_retire)) == "menu.invalidImageMaintenance",
        "negative resource epoch rejected");
    bad_retire = retire; bad_retire[Value("payload")] = Value("forbidden");
    check(messenger.Call("imageMaintenance", Value(bad_retire)) == "menu.invalidImageMaintenance",
        "resource retirement cannot carry a business payload");
    check(messenger.Call("open") == "menu.unavailable", "opening requires configuration");
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
    if (image_engine) {
      // Prewarm only. This mode never opens, reveals or focuses the surface.
      check(messenger.Call("prewarm") == "success" && std::get<bool>(messenger.last_result),
          "resource fixture prewarms isolated engine without opening");
      auto pump = []() {
        MSG msg{};
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
          TranslateMessage(&msg); DispatchMessageW(&msg);
        }
        Sleep(10);
      };
      bool ready = false;
      const auto started = GetTickCount64();
      while (!ready && GetTickCount64() - started < 20000) {
        pump();
        messenger.Call("status");
        const auto* status = std::get_if<Map>(&messenger.last_result);
        if (status) {
          const auto item = status->find(Value("dartReady"));
          const auto* flag = item != status->end() ? std::get_if<bool>(&item->second) : nullptr;
          ready = flag && *flag;
        }
      }
      check(ready, "candidate menuMain acknowledges real method-channel handshake");
      if (ready) {
        auto pending = messenger.CallAsync("imageMaintenance", Value(Map{
            {Value("schemaVersion"), Value(1)},
            {Value("resourceEpoch"), Value(int64_t{2})}}));
        const auto sent = GetTickCount64();
        while (pending->outcome == "no_reply" && GetTickCount64() - sent < 5000) pump();
        check(pending->outcome == "success", "real secondary engine confirms resource retirement");
        const auto* receipt = std::get_if<Map>(&pending->result);
        check(receipt && receipt->size() == 3 &&
            receipt->at(Value("schemaVersion")) == Value(1) &&
            receipt->at(Value("resourceEpoch")) == Value(int64_t{2}) &&
            receipt->at(Value("enginePresent")) == Value(true),
            "real resource receipt preserves exact protocol and epoch");
      }
      messenger.Call("status");
      check(!std::get<bool>(std::get<Map>(messenger.last_result).at(Value("wanted"))),
          "retirement never creates an opening session");
      bool hidden = true;
      EnumThreadWindows(GetCurrentThreadId(), [](HWND window, LPARAM state) -> BOOL {
        if (IsWindowVisible(window)) *reinterpret_cast<bool*>(state) = false;
        return TRUE;
      }, reinterpret_cast<LPARAM>(&hidden));
      check(hidden, "all isolated fixture windows remain hidden");
      DWORD foreground_pid = 0;
      GetWindowThreadProcessId(GetForegroundWindow(), &foreground_pid);
      check(foreground_pid != GetCurrentProcessId(), "isolated engine never acquires foreground");
    }
    if (hidden_engine) {
      // Diagnostics only: name the step after which another window took foreground.
      auto foreground_after = [original_foreground](const char* step) {
        const HWND now = GetForegroundWindow();
        if (now == original_foreground) return;
        wchar_t name[128]{};
        GetClassNameW(now, name, 128);
        DWORD pid = 0;
        GetWindowThreadProcessId(now, &pid);
        printf("INFO|foreground_changed_after=%s|class=%ls|pid=%lu|self=%lu\n",
            step, name, pid, GetCurrentProcessId());
        GUITHREADINFO gui{sizeof(gui)};
        if (GetGUIThreadInfo(GetCurrentThreadId(), &gui)) {
          wchar_t active[128]{}, focus[128]{};
          GetClassNameW(gui.hwndActive, active, 128);
          GetClassNameW(gui.hwndFocus, focus, 128);
          printf("INFO|thread_active=%ls|thread_focus=%ls\n", active, focus);
        }
      };
      LARGE_INTEGER frequency{}, started{}, prewarmed{}, opened{};
      QueryPerformanceFrequency(&frequency);
      QueryPerformanceCounter(&started);
      check(messenger.Call("prewarm") == "success" && std::get<bool>(messenger.last_result),
          "idle prewarm prepares real auxiliary engine");
      QueryPerformanceCounter(&prewarmed);
      foreground_after("prewarm");
      const double prewarm_ms = 1000.0 * (prewarmed.QuadPart - started.QuadPart) / frequency.QuadPart;
      messenger.Call("status");
      check(!std::get<bool>(std::get<Map>(messenger.last_result).at(Value("wanted"))),
          "prewarm creates no opening session");
      HWND prepared = FindWindowW(L"StarBridge.Flutter.MenuOverlay.v1", nullptr);
      check(prepared && !IsWindowVisible(prepared), "prewarmed surface remains hidden");
      check(messenger.Call("prewarm") == "success" && std::get<bool>(messenger.last_result),
          "repeated prewarm reuses the engine");
      QueryPerformanceCounter(&started);
      check(messenger.Call("open") == "success", "prepare real auxiliary engine");
      QueryPerformanceCounter(&opened);
      foreground_after("open");
      // Informational local timing, not an in-game acceptance measurement.
      printf("INFO|prewarm_ms=%.1f|prewarmed_open_call_ms=%.1f\n",
          prewarm_ms,
          1000.0 * (opened.QuadPart - started.QuadPart) / frequency.QuadPart);
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
        foreground_after("pump");
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
    retire[Value("resourceEpoch")] = Value(int64_t{2});
    retire[Value("request")] = Value(int64_t{40});
    check(messenger.Call("imageMaintenance", Value(retire)) == "menu.invalidImageMaintenance",
        "old owner cannot retire a replacement engine");
    retire[Value("request")] = Value(int64_t{41});
    auto scoped_retirement = messenger.CallAsync("imageMaintenance", Value(retire));
    const auto scoped_sent = GetTickCount64();
    while (scoped_retirement->outcome == "no_reply" && GetTickCount64() - scoped_sent < 5000) {
      MSG msg{};
      while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg); DispatchMessageW(&msg);
      }
      Sleep(10);
    }
    check(scoped_retirement->outcome == "success",
        "current owner can retire resources without opening");
    const auto* scoped_ack = std::get_if<Map>(&scoped_retirement->result);
    check(scoped_ack && scoped_ack->at(Value("enginePresent")) == Value(image_engine || hidden_engine),
        "scoped resource retirement preserves existing engine presence");
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
