#include "friends_window_bridge.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <cstdio>
#include <map>

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
class Messenger : public flutter::BinaryMessenger {
 public:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
  Value reply;
  bool answered = false;
  std::string kind = "friends";
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply callback) const override {
    if (callback) callback(nullptr, 0);
  }
  void SetMessageHandler(const std::string& name, flutter::BinaryMessageHandler handler) override {
    handlers[name] = std::move(handler);
  }
  void Call(const char* method, Value args = Value()) {
    answered = false;
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    auto bytes = codec.EncodeMethodCall(flutter::MethodCall<Value>(method, std::make_unique<Value>(args)));
    handlers.at("starbridge/" + kind + "-primary")(bytes->data(), bytes->size(),
      [this](const uint8_t* data, size_t count) {
        class Response : public flutter::MethodResult<Value> {
         public:
          explicit Response(Messenger* owner) : owner_(owner) {}
         protected:
          void SuccessInternal(const Value* value) override { owner_->reply = value ? *value : Value(); }
          void ErrorInternal(const std::string& code, const std::string&, const Value*) override { owner_->reply = Value(code); }
          void NotImplementedInternal() override { owner_->reply = Value("notImplemented"); }
         private:
          Messenger* owner_;
        } response(this);
        answered = true;
        flutter::StandardMethodCodec::GetInstance().DecodeAndProcessResponseEnvelope(data, count, &response);
      });
  }
};

// Never shows a window, bootstraps account/Host, sends social commands or reads
// user settings. Uses the real friendsMain entry point with synthetic labels.
int wmain(int argc, wchar_t** argv) {
  if (argc != 2 && argc != 3) return 2;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  HWND owner = CreateWindowExW(0, L"STATIC", L"Fixture", WS_OVERLAPPEDWINDOW,
      0, 0, 100, 100, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  int failed = 0;
  auto check = [&failed](bool ok, const char* name) {
    printf("%s|%s\n", ok ? "PASS" : "FAIL", name); if (!ok) ++failed;
  };
  Messenger messenger;
  if (argc == 3) {
    const std::wstring kind(argv[2]);
    if (kind != L"messages" && kind != L"notifications") return 2;
    messenger.kind = kind == L"messages" ? "messages" : "notifications";
  }
  {
    FriendsWindowBridge bridge(owner, &messenger, argv[1], messenger.kind);
    messenger.Call("show");
    check(messenger.answered && messenger.reply == Value("friends.invalid_snapshot"), "reject invalid snapshot");
    Map snapshot{{Value("opening"), Value(1)}, {Value("revision"), Value(1)},
                 {Value("view"), Value("{\"state\":\"loading\",\"scope\":\"fixture\",\"targetVersion\":0}")}};
    messenger.Call("show", Value(snapshot));
    HWND window = FindWindowW(L"StarBridge.Flutter.Friends.Fixture", nullptr);
    check(window && !IsWindowVisible(window), "first opening waits for rendered presentation");
    check(window && SendMessageW(window, WM_NCACTIVATE, TRUE, 0) == TRUE,
          "custom social frame suppresses native activation border paint");
    SendMessageW(window, WM_CLOSE, 0, 0);
    check(messenger.answered && messenger.reply == Value(false), "close cancels pending reveal");
    const auto start = GetTickCount64();
    bool ready = false;
    while (!ready && GetTickCount64() - start < 20000) {
      MSG message{};
      while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message); DispatchMessageW(&message);
      }
      messenger.Call("fixtureStatus");
      const auto* status = std::get_if<Map>(&messenger.reply);
      ready = status && status->at(Value("dartReady")) == Value(true);
      Sleep(10);
    }
    check(ready, "real friendsMain engine completes channel handshake");
    // Approval prompts/other apps may change global foreground during a probe.
    // Assert this fixture cannot activate, rather than requiring the whole OS
    // to keep the same unrelated foreground window for twenty seconds.
    const HWND foreground = GetForegroundWindow();
    check(!IsWindowVisible(window), "closed window stays hidden after handshake");
    check(foreground != window, "closed friends window is not foreground");
    check(foreground != owner, "main window is not activated by hidden preparation");
    check(!IsChild(window, foreground), "hidden Flutter child is not foreground");
    check(IsWindow(owner) != FALSE, "friends close preserves main window");
    const auto style = GetWindowLongPtrW(window, GWL_STYLE);
    check((style & WS_THICKFRAME) && !(style & WS_CAPTION) && (style & WS_SYSMENU), "integrated frame retains native resizing and system menu");
    check(GetWindow(window, GW_OWNER) == nullptr && !(GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOPMOST), "independent ordinary desktop window");
    SetWindowPos(window, nullptr, 0, 0, 520, 760, SWP_NOACTIVATE | SWP_NOZORDER);
    RECT client{}, child{};
    GetClientRect(window, &client); GetClientRect(GetWindow(window, GW_CHILD), &child);
    check(client.right == child.right && client.bottom == child.bottom, "resizing fills client area");
    RECT outer{}; GetWindowRect(window, &outer);
    check(client.right == outer.right - outer.left && client.bottom == outer.bottom - outer.top,
          "no separate system caption or frame strip");
    const UINT dpi = GetDpiForWindow(window);
    auto point = [&](int x, int y) { return MAKELPARAM(outer.left + MulDiv(x, dpi, 96),
                                                     outer.top + MulDiv(y, dpi, 96)); };
    check(SendMessageW(window, WM_NCHITTEST, 0, point(80, 18)) == HTCAPTION, "integrated header is a native drag target");
    check(SendMessageW(GetWindow(window, GW_CHILD), WM_NCHITTEST, 0, point(80, 18)) == HTTRANSPARENT,
          "Flutter child passes caption dragging to native parent");
    check(SendMessageW(window, WM_NCHITTEST, 0, point(1, 1)) == HTTOPLEFT, "corner still resizes");
    check(SendMessageW(window, WM_NCHITTEST, 0, MAKELPARAM(outer.right - MulDiv(22, dpi, 96), outer.top + MulDiv(18, dpi, 96))) == HTCLIENT,
          "caption button area remains interactive Flutter content");
    check(SendMessageW(window, WM_NCHITTEST, 0, point(80, 100)) == HTCLIENT, "roster is not draggable caption");
    MINMAXINFO limits{}; SendMessageW(window, WM_GETMINMAXINFO, 0, reinterpret_cast<LPARAM>(&limits));
    MONITORINFO monitor{sizeof(monitor)};
    GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor);
    check(limits.ptMaxSize.x == monitor.rcWork.right - monitor.rcWork.left &&
          limits.ptMaxSize.y == monitor.rcWork.bottom - monitor.rcWork.top, "maximize respects work area");
    snapshot[Value("opening")] = Value(2);
    messenger.Call("show", Value(snapshot));
    check(FindWindowW(L"StarBridge.Flutter.Friends.Fixture", nullptr) == window, "reopening reuses native window");
    SendMessageW(window, WM_CLOSE, 0, 0);
    messenger.Call("detach");
    check(!IsWindowVisible(window), "detach hides and revokes surface");
  }
  check(FindWindowW(L"StarBridge.Flutter.Friends.Fixture", nullptr) == nullptr, "primary shutdown destroys auxiliary window");
  DestroyWindow(owner); CoUninitialize(); return failed ? 1 : 0;
}
