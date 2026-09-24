#include "menu_overlay_bridge.h"
#include "menu_fixture_messenger.h"
#include <windows.h>

namespace {
constexpr wchar_t kClass[] = L"StarBridge.MenuPreview.Control.v1";
FixtureMessenger* caller = nullptr;
HWND status_label = nullptr;
LRESULT CALLBACK ControlProc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_CREATE) {
    const auto font = reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    auto label = CreateWindowW(L"STATIC",
        L"独立菜单预览（演示数据）\n不连接账号，不改变当前客户端。\n在浮层中按 Esc 关闭，再从这里打开。",
        WS_CHILD | WS_VISIBLE, 20, 20, 400, 68, window, nullptr, nullptr, nullptr);
    SendMessageW(label, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    auto button = CreateWindowW(L"BUTTON", L"打开菜单浮层", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
        20, 106, 180, 38, window, reinterpret_cast<HMENU>(1), nullptr, nullptr);
    SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    button = CreateWindowW(L"BUTTON", L"退出预览", WS_CHILD | WS_VISIBLE | WS_TABSTOP,
        220, 106, 180, 38, window, reinterpret_cast<HMENU>(2), nullptr, nullptr);
    SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    status_label = CreateWindowW(L"STATIC", L"准备就绪", WS_CHILD | WS_VISIBLE,
        20, 155, 400, 22, window, nullptr, nullptr, nullptr);
    SendMessageW(status_label, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    SetTimer(window, 1, 500, nullptr);
    return 0;
  }
  if (message == WM_TIMER && caller) {
    caller->Call("status");
    const auto* status = std::get_if<Map>(&caller->last_result);
    bool ready = false, wanted = false;
    if (status) {
      ready = std::get<bool>(status->at(Value("dartReady")));
      wanted = std::get<bool>(status->at(Value("wanted")));
    }
    const wchar_t* label = wanted ? (ready ? L"正在显示 / 准备首帧" : L"正在启动 Flutter 预览")
                                 : (ready ? L"预览已隐藏，可再次打开" : L"准备就绪");
    SetWindowTextW(status_label, label);
    return 0;
  }
  if (message == WM_COMMAND && caller) {
    if (LOWORD(wp) == 1) {
      if (caller->Call("open") != "success")
        MessageBoxW(window, L"未能准备预览。请重试或关闭预览窗口。", L"菜单预览", MB_OK | MB_ICONWARNING);
      return 0;
    }
    if (LOWORD(wp) == 2) { DestroyWindow(window); return 0; }
  }
  if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcW(window, message, wp, lp);
}
}

// Private manual harness: no production singleton, plugins, login or Native Host.
int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, wchar_t*, int) {
  const auto existing = FindWindowW(kClass, nullptr);
  if (existing) { ShowWindow(existing, SW_RESTORE); SetForegroundWindow(existing); return 0; }
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  {
    FixtureMessenger messenger;
    caller = &messenger;
    MenuOverlayBridge bridge(&messenger);
    const Map config{{Value("schemaVersion"), Value(1)},
        {Value("contextLabel"), Value("Menu workspace preview")},
        {Value("returnLabel"), Value("Close preview")},
        {Value("settingsLabel"), Value("Settings")}};
    messenger.Call("configure", Value(config));
    WNDCLASSW wc{};
    wc.lpfnWndProc = ControlProc;
    wc.hInstance = instance;
    wc.lpszClassName = kClass;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    RegisterClassW(&wc);
    HWND window = CreateWindowW(kClass, L"StarBridge 菜单浮层预览", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 450, 235, nullptr, nullptr, instance, nullptr);
    if (window) {
      ShowWindow(window, SW_SHOW);
      MSG msg{};
      while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if ((msg.hwnd != window && !IsChild(window, msg.hwnd)) || !IsDialogMessageW(window, &msg)) {
          TranslateMessage(&msg); DispatchMessageW(&msg);
        }
      }
    }
    messenger.Call("detach");
    caller = nullptr;
  }
  CoUninitialize();
  return 0;
}
