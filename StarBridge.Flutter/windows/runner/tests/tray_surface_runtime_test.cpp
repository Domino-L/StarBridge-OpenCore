#include "application_lifecycle_bridge.h"
#include "tray_surface_bridge.h"
#include "win32_window.h"
#include <flutter/standard_method_codec.h>
#include <flutter/method_call.h>
#include <cstdio>
#include <map>
#include <cstring>
#include <algorithm>
#include <atomic>
#include <functional>

using Value = flutter::EncodableValue;
class FixtureMessenger : public flutter::BinaryMessenger {
 public:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
  mutable std::atomic<int> refreshes{0}, actions{0}, wrong_thread_sends{0};
  const DWORD main_thread = GetCurrentThreadId();
  std::function<void()> on_tray_handler_registered;
  void Send(const std::string& channel, const uint8_t* data, size_t size,
            flutter::BinaryReply reply) const override {
    if (GetCurrentThreadId() != main_thread) ++wrong_thread_sends;
    if (channel == "starbridge/tray-primary") {
      const auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(data, size);
      if (call && call->method_name() == "refresh") ++refreshes;
      if (call && call->method_name() == "action") ++actions;
    }
    if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler handler) override {
    handlers[channel] = std::move(handler);
    if (channel == "starbridge/tray-primary" && handlers[channel] &&
        on_tray_handler_registered) {
      auto reenter = std::move(on_tray_handler_registered);
      reenter();
    }
  }
  void Configure() {
    const auto snapshot = flutter::EncodableMap{
      {Value("schemaVersion"), Value(1)}, {Value("scope"), Value(0)},
      {Value("runtime"), Value("background")}, {Value("overlay"), Value("unavailable")},
      {Value("canChangePresence"), Value(false)}, {Value("canToggleOverlay"), Value(false)},
      {Value("dark"), Value(true)}, {Value("reduceMotion"), Value(false)},
      {Value("locale"), Value("zh-CN")}};
    auto message = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<Value>("configure", std::make_unique<Value>(snapshot)));
    handlers.at("starbridge/tray-primary")(message->data(), message->size(), [](const uint8_t*, size_t) {});
  }
  void Detach() {
    auto message = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<Value>("detach", nullptr));
    handlers.at("starbridge/tray-primary")(message->data(), message->size(), [](const uint8_t*, size_t) {});
  }
  bool ConfigureLifecycle() {
    const auto handler = handlers.find("starbridge/application-lifecycle");
    if (handler == handlers.end() || !handler->second) return false;
    const auto settings = flutter::EncodableMap{
        {Value("keepRunningInBackground"), Value(false)},
        {Value("startMinimized"), Value(false)}};
    auto message = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<Value>("configure", std::make_unique<Value>(settings)));
    // Keep the reply storage alive even if a regression makes the response
    // asynchronous. This test requires the acknowledgement before returning.
    auto accepted = std::make_shared<bool>(false);
    handler->second(message->data(), message->size(),
        [accepted](const uint8_t* data, size_t size) {
          const auto expected = flutter::StandardMethodCodec::GetInstance().EncodeSuccessEnvelope();
          *accepted = data && size == expected->size() &&
              std::equal(expected->begin(), expected->end(), data);
        });
    return *accepted;
  }
};
ULONGLONG PumpMeasured(DWORD duration) {
  const auto start = GetTickCount64();
  auto previous = start;
  ULONGLONG maximum_gap = 0;
  auto sample = [&]() {
    const auto now = GetTickCount64();
    maximum_gap = (std::max)(maximum_gap, now - previous);
    previous = now;
  };
  while (GetTickCount64() - start < duration) {
    MSG msg{};
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
      sample();
    }
    Sleep(5);
    sample();
  }
  return maximum_gap;
}
void Pump(DWORD duration) { PumpMeasured(duration); }
HWND FixturePanel() {
  HWND result = nullptr;
  EnumWindows([](HWND window, LPARAM data) -> BOOL {
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    if (process != GetCurrentProcessId()) return TRUE;
    wchar_t name[128]{};
    GetClassNameW(window, name, 128);
    if (wcscmp(name, L"StarBridge.Flutter.TraySurface.v1") != 0) return TRUE;
    *reinterpret_cast<HWND*>(data) = window;
    return FALSE;
  }, reinterpret_cast<LPARAM>(&result));
  return result;
}
HWND ThreadFocus(HWND window) {
  const DWORD thread = window ? GetWindowThreadProcessId(window, nullptr) : 0;
  GUITHREADINFO info{};
  info.cbSize = sizeof(info);
  return thread && GetGUIThreadInfo(thread, &info) ? info.hwndFocus : nullptr;
}
// Observe only this fixture's activation, including a brief activation followed
// by deactivation. An approval dialog or terminal changing focus is unrelated.
class FixtureForegroundEvents {
 public:
  FixtureForegroundEvents() {
    hook_ = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
        nullptr, OnForeground, GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);
    if (hook_) observers_[hook_] = this;
  }
  ~FixtureForegroundEvents() {
    if (hook_) {
      observers_.erase(hook_);
      UnhookWinEvent(hook_);
    }
  }
  FixtureForegroundEvents(const FixtureForegroundEvents&) = delete;
  FixtureForegroundEvents& operator=(const FixtureForegroundEvents&) = delete;
  bool installed() const { return hook_ != nullptr; }
  int count() const { return count_; }
 private:
  static void CALLBACK OnForeground(HWINEVENTHOOK hook, DWORD event,
                                    HWND, LONG, LONG, DWORD, DWORD) {
    const auto observer = observers_.find(hook);
    if (observer == observers_.end() || event != EVENT_SYSTEM_FOREGROUND) return;
    // The subscription already filters the PID. Do not resolve the HWND again:
    // a briefly activated window may have been destroyed before delivery.
    ++observer->second->count_;
  }
  inline static std::map<HWINEVENTHOOK, FixtureForegroundEvents*> observers_;
  HWINEVENTHOOK hook_ = nullptr;
  int count_ = 0;
};
// Optional diagnostic capture is cropped strictly to this fixture's own panel.
// It lives in build output, never in the source tree or acceptance artifacts.
bool CapturePanel(HWND panel, const char* path) {
  RECT rect{};
  GetClientRect(panel, &rect);
  HDC source = GetDC(panel), target = CreateCompatibleDC(source);
  BITMAPINFO info{};
  info.bmiHeader = {sizeof(BITMAPINFOHEADER), rect.right, -rect.bottom, 1, 32, BI_RGB};
  void* pixels = nullptr;
  HBITMAP bitmap = CreateDIBSection(source, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  const auto previous = SelectObject(target, bitmap);
  BitBlt(target, 0, 0, rect.right, rect.bottom, source, 0, 0, SRCCOPY);
  size_t white = 0, ink = 0;
  const auto* colors = static_cast<const DWORD*>(pixels);
  for (int i = 0; i < rect.right * rect.bottom; ++i) {
    if ((colors[i] & 0xffffff) == 0xffffff) ++white;
    const DWORD r = (colors[i] >> 16) & 255, g = (colors[i] >> 8) & 255, b = colors[i] & 255;
    if (r > 150 && g > 150 && b > 150 && (r < 245 || g < 245 || b < 245)) ++ink;
  }
  printf("INFO|white-background-pixels=%zu/%ld|visible-ink=%zu\n", white, rect.right * rect.bottom, ink);
  BITMAPFILEHEADER header{};
  header.bfType = 0x4d42;
  header.bfOffBits = sizeof(header) + sizeof(BITMAPINFOHEADER);
  header.bfSize = header.bfOffBits + rect.right * rect.bottom * 4;
  FILE* file = nullptr;
  if (path && fopen_s(&file, path, "wb") == 0) {
    fwrite(&header, sizeof(header), 1, file);
    fwrite(&info.bmiHeader, sizeof(BITMAPINFOHEADER), 1, file);
    fwrite(pixels, rect.right * rect.bottom * 4, 1, file);
    fclose(file);
  }
  SelectObject(target, previous); DeleteObject(bitmap);
  DeleteDC(target); ReleaseDC(panel, source);
  return white < static_cast<size_t>(rect.right * rect.bottom / 10) && ink > 150;
}
bool CheckPanelPixels(HWND panel, const char* capture_path = nullptr) {
  RECT rect{};
  GetWindowRect(panel, &rect);
  HWND underlay = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      L"STATIC", L"", WS_POPUP | SS_WHITERECT,
      rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  SetWindowPos(underlay, panel, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  UpdateWindow(underlay);
  Pump(100);
  const bool painted = CapturePanel(panel, capture_path);
  DestroyWindow(underlay);
  return painted;
}
int main(int argc, char** argv) {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Win32Window main_window;
  main_window.Create(L"StarBridge isolated tray fixture", {0, 0}, {500, 400});
  const HWND owner = main_window.GetHandle();
  const HWND main_child = CreateWindowW(L"STATIC", L"Fixture content", WS_CHILD | WS_VISIBLE,
      0, 0, 500, 400, owner, nullptr, GetModuleHandleW(nullptr), nullptr);
  main_window.SetChildContent(main_child);
  FixtureMessenger messenger;
  int failures = 0;
  auto check = [&](bool value, const char* text) { printf("%s|%s\n", value ? "PASS" : "FAIL", text); fflush(stdout); if (!value) failures++; };
  SetFocus(nullptr);
  SendMessageW(owner, WM_ACTIVATE, WA_INACTIVE, 0);
  check(GetFocus() != main_child, "deactivating-main-window-does-not-reclaim-keyboard-focus");
  {
    FixtureForegroundEvents preparation_focus;
    const auto preparation_start = GetTickCount64();
    ApplicationLifecycleBridge bridge(owner, &messenger, false);
    const auto preparation_duration = GetTickCount64() - preparation_start;
    const auto configure_start = GetTickCount64();
    messenger.Configure();
    const auto configure_duration = GetTickCount64() - configure_start;
    if (argc > 1 && strcmp(argv[1], "--latency") == 0) {
      // Exercise only the isolated tray entrypoint, never the app/account/Host.
      // Hidden startup cost is reported separately; it must not be hidden in
      // the click latency or reintroduced into the running main message pump.
      const auto maximum_gap = PumpMeasured(1500);
      printf("PREPARATION|constructor-ms=%llu|configure-ms=%llu|main-pump-max-gap-ms=%llu\n",
             preparation_duration, configure_duration, maximum_gap);
      check(maximum_gap < 100, "prepared-tray-does-not-block-running-main-message-pump");
      check(preparation_focus.installed(), "fixture-foreground-event-monitor-is-installed");
      check(preparation_focus.count() == 0 && !IsWindowVisible(owner),
            "idle-preparation-does-not-show-or-focus-main-window");
      HWND prepared = FixturePanel();
      check(prepared && !IsWindowVisible(prepared), "tray-is-prepared-hidden-before-first-click");
      check(messenger.refreshes == 0 && messenger.actions == 0,
            "hidden-preparation-does-not-refresh-or-run-business-actions");
      messenger.Configure();
      Pump(100);
      check(prepared && FixturePanel() == prepared,
            "snapshot-update-reuses-the-prepared-window");
      for (int attempt = 0; attempt < 2; ++attempt) {
        const auto start = GetTickCount64();
        bridge.HandleWindowMessage(WM_APP + 0x54, 1, WM_RBUTTONUP);
        const auto synchronous = GetTickCount64() - start;
        HWND panel = FixturePanel();
        while ((!panel || !IsWindowVisible(panel)) && GetTickCount64() - start < 3000) {
          Pump(5);
          panel = FixturePanel();
        }
        const auto visible = GetTickCount64() - start;
        printf("LATENCY|attempt=%d|click-handler-ms=%llu|visible-ms=%llu\n", attempt + 1, synchronous, visible);
        check(synchronous < 100, "tray-click-does-not-block-ui-for-engine-startup");
        check(panel && IsWindowVisible(panel) && visible < 250, "tray-first-and-repeat-visible-within-250ms");
        check(panel && panel == prepared, "tray-click-reuses-the-prepared-window");
        check(!IsWindowVisible(owner), "tray-latency-probe-keeps-main-hidden");
        if (panel && IsWindowVisible(panel)) bridge.HandleWindowMessage(WM_APP + 0x54, 1, WM_RBUTTONUP);
        Pump(100);
      }
      check(messenger.actions == 0, "opening-and-closing-do-not-run-business-actions");
      check(messenger.wrong_thread_sends == 0, "primary-channel-stays-on-its-own-thread");
    } else {
    bridge.HandleWindowMessage(WM_APP + 0x54, 1, WM_LBUTTONUP);
    check(!IsWindowVisible(owner), "left-click-does-not-restore-main-window");
    ShowWindow(owner, SW_HIDE);
    // A pending first opening may not have created its HWND yet. Do not send a
    // second click here: it correctly cancels that opening in the fixed code.
    Pump(2500);
    HWND panel = FixturePanel();
    check(panel && GetWindow(panel, GW_OWNER) == nullptr,
          "tray-is-independent-and-cannot-raise-main-owner");
    check(panel && IsWindowVisible(panel), "auxiliary-panel-becomes-visible");
    check(panel && CheckPanelPixels(panel, argc > 1 ? argv[1] : nullptr),
          "tray-has-visible-content-not-transparent-or-blank");
    HWND child = panel ? FindWindowExW(panel, nullptr, L"FLUTTERVIEW", nullptr) : nullptr;
    RECT outer{}, inner{};
    if (panel) GetClientRect(panel, &outer);
    if (child) GetClientRect(child, &inner);
    const LONG logical_height = panel ? MulDiv(outer.bottom, 96, GetDpiForWindow(panel)) : 0;
    check(logical_height > 300 && logical_height < 500,
          "native-height-follows-menu-without-fixed-bottom-gap");
    RECT child_position{};
    if (child) {
      GetWindowRect(child, &child_position);
      MapWindowPoints(HWND_DESKTOP, panel, reinterpret_cast<POINT*>(&child_position), 2);
    }
    printf("INFO|child-position=%ld,%ld\n", child_position.left, child_position.top);
    check(child && child_position.left == 0 && child_position.top == 0,
          "flutter-child-is-positioned-at-panel-origin");
    printf("INFO|parent=%ldx%ld|child=%ldx%ld\n", outer.right, outer.bottom, inner.right, inner.bottom);
    check(child && inner.right == outer.right && inner.bottom == outer.bottom && inner.right > 0,
          "flutter-child-fills-panel-client-area");
    check(GetForegroundWindow() != owner && ThreadFocus(owner) != main_child,
          "real-main-window-does-not-steal-tray-focus");
    for (const UINT button : {WM_RBUTTONUP, WM_LBUTTONUP, WM_RBUTTONUP}) {
      bridge.HandleWindowMessage(WM_APP + 0x54, 1, button);
      Pump(40);
      check(!IsWindowVisible(panel), "second-click-dismisses-panel");
      bridge.HandleWindowMessage(WM_APP + 0x54, 1, button);
      Pump(600);
      check(IsWindowVisible(panel), "reopen-paints-a-fresh-frame");
      check(CheckPanelPixels(panel), "reopened-panel-retains-visible-content");
      check(!IsWindowVisible(owner), "reopen-keeps-main-window-hidden");
    }
    // Unlike the old hidden-only fixture, exercise a real visible main window
    // losing activation to the auxiliary Flutter view.
    ShowWindow(owner, SW_SHOW);
    SetForegroundWindow(owner);
    Pump(80);
    if (IsWindowVisible(panel)) bridge.HandleWindowMessage(WM_APP + 0x54, 1, WM_RBUTTONUP);
    bridge.HandleWindowMessage(WM_APP + 0x54, 1, WM_LBUTTONUP);
    Pump(600);
    check(GetForegroundWindow() != owner,
          "tray-does-not-foreground-visible-main");
    check(ThreadFocus(panel) == child, "tray-content-receives-keyboard-focus");
    }
  }
  check(FixturePanel() == nullptr, "destroyed-lifecycle-leaves-no-tray-window");
  if (argc > 1 && strcmp(argv[1], "--latency") == 0) {
    // Direct callbacks make a stale timeout observable without opening a real
    // TrackPopupMenu or exiting the fixture. Only the isolated tray entrypoint
    // runs; no account, NativeHost, app bootstrap, or second tray icon exists.
    FixtureMessenger isolated_messenger;
    std::atomic<int> opens{0}, exits{0}, fallbacks{0};
    {
      FixtureForegroundEvents detach_focus;
      TraySurfaceBridge tray(owner, &isolated_messenger,
          [&]() { ++opens; }, [&]() { ++exits; }, [&]() { ++fallbacks; });
      isolated_messenger.Configure();
      isolated_messenger.Detach();
      Pump(1500);
      HWND panel = FixturePanel();
      check(!panel || !IsWindowVisible(panel), "detach-before-ready-does-not-reveal-panel");
      check(opens == 0 && exits == 0 && fallbacks == 0 &&
            isolated_messenger.refreshes == 0 && isolated_messenger.actions == 0,
            "detach-before-ready-does-not-run-business-or-fallback");
      check(detach_focus.installed(), "detach-foreground-event-monitor-is-installed");
      check(detach_focus.count() == 0 && !IsWindowVisible(owner),
            "detach-before-ready-does-not-steal-focus");

      isolated_messenger.Configure();
      const POINT anchor{400, 400};
      check(tray.Show(anchor, false), "pending-first-open-is-accepted");
      check(tray.Show(anchor, false), "rapid-second-click-is-accepted-as-cancel");
      Pump(1500);
      panel = FixturePanel();
      check(panel && !IsWindowVisible(panel), "rapid-double-click-cancels-pending-first-frame");
      // Simulate messages already queued before Hide/KillTimer; neither may
      // reveal a dismissed panel nor dispatch the system-menu fallback.
      if (panel) {
        PostMessageW(panel, WM_TIMER, 0x5343, 0);
        PostMessageW(panel, WM_APP + 0x71, 1, 0);
      }
      Pump(100);
      check(!panel || !IsWindowVisible(panel), "late-frame-after-cancel-stays-hidden");
      check(fallbacks == 0, "late-timeout-after-cancel-does-not-fallback");
      check(opens == 0 && exits == 0 && isolated_messenger.actions == 0,
            "cancel-and-late-messages-do-not-run-business-actions");

      isolated_messenger.Detach();
      if (panel) PostMessageW(panel, WM_TIMER, 0x5343, 0);
      Pump(100);
      check(fallbacks == 0, "late-timeout-after-detach-does-not-fallback");
      check(isolated_messenger.wrong_thread_sends == 0,
            "lifecycle-races-keep-primary-channel-on-its-own-thread");
      // Leave stale work queued across destruction, then pump after teardown.
      if (panel) {
        PostMessageW(panel, WM_TIMER, 0x5343, 0);
        PostMessageW(panel, WM_APP + 0x71, 1, 0);
      }
    }
    check(FixturePanel() == nullptr, "destroyed-preparation-leaves-no-tray-window");
    Pump(100);
    check(FixturePanel() == nullptr && opens == 0 && exits == 0 && fallbacks == 0,
          "queued-work-cannot-recreate-window-or-call-back-after-destruction");

    // Flutter's constructor/resize path can pump platform messages. Reenter
    // lifecycle configuration while the native tray bridge is still being
    // constructed: accept the early request, but reveal only after preparation.
    FixtureMessenger reentrant_messenger;
    bool reentrant_request_seen = false;
    reentrant_messenger.on_tray_handler_registered = [&]() {
      reentrant_request_seen = true;
      check(reentrant_messenger.ConfigureLifecycle(),
            "reentrant-startup-configure-is-acknowledged-during-preparation");
      check(!IsWindowVisible(owner),
            "reentrant-startup-configure-does-not-reveal-main-before-preparation");
    };
    {
      ApplicationLifecycleBridge bridge(owner, &reentrant_messenger, false);
      check(reentrant_request_seen, "startup-configure-was-delivered-reentrantly");
      check(IsWindowVisible(owner),
            "deferred-startup-request-shows-main-after-preparation");
      const HWND panel = FixturePanel();
      check(panel && !IsWindowVisible(panel),
            "reentrant-startup-request-keeps-tray-panel-hidden");
      ShowWindow(owner, SW_HIDE);
    }
    check(FixturePanel() == nullptr && !IsWindowVisible(owner),
          "reentrant-startup-fixture-is-hidden-and-leaves-no-tray-window");
  }
  main_window.Destroy();
  CoUninitialize();
  return failures ? 1 : 0;
}
