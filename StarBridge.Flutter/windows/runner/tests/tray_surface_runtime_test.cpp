#include "application_lifecycle_bridge.h"
#include "win32_window.h"
#include <flutter/standard_method_codec.h>
#include <flutter/method_call.h>
#include <cstdio>
#include <map>

using Value = flutter::EncodableValue;
class FixtureMessenger : public flutter::BinaryMessenger {
 public:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply reply) const override {
    if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler handler) override {
    handlers[channel] = std::move(handler);
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
};
void Pump(DWORD duration) {
  const auto start = GetTickCount64();
  while (GetTickCount64() - start < duration) {
    MSG msg{};
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    Sleep(5);
  }
}
HWND FixturePanel() {
  HWND result = nullptr;
  EnumThreadWindows(GetCurrentThreadId(), [](HWND window, LPARAM data) -> BOOL {
    wchar_t name[128]{};
    GetClassNameW(window, name, 128);
    if (wcscmp(name, L"StarBridge.Flutter.TraySurface.v1") != 0) return TRUE;
    *reinterpret_cast<HWND*>(data) = window;
    return FALSE;
  }, reinterpret_cast<LPARAM>(&result));
  return result;
}
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
    ApplicationLifecycleBridge bridge(owner, &messenger, false);
    messenger.Configure();
    bridge.HandleWindowMessage(WM_APP + 0x54, 1, WM_LBUTTONUP);
    check(!IsWindowVisible(owner), "left-click-does-not-restore-main-window");
    ShowWindow(owner, SW_HIDE);
    // The original implementation only opens the auxiliary view on right click.
    if (!FixturePanel())
      bridge.HandleWindowMessage(WM_APP + 0x54, 1, WM_RBUTTONUP);
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
    check(GetForegroundWindow() != owner && GetFocus() != main_child,
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
    check(GetFocus() == child, "tray-content-receives-keyboard-focus");
  }
  main_window.Destroy();
  CoUninitialize();
  return failures ? 1 : 0;
}
