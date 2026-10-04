#ifndef RUNNER_MENU_LOCAL_TOOLS_H_
#define RUNNER_MENU_LOCAL_TOOLS_H_
#include <flutter/encodable_value.h>
#include <flutter/method_result.h>
#include <functional>
#include <memory>
#include <windows.h>

// Native-only image selection/capture and an isolated, unprivileged WebView.
// No account, Host, hangar-reader, filesystem path or arbitrary RPC interface.
class MenuLocalTools {
 public:
  using Value = flutter::EncodableValue;
  using Result = std::unique_ptr<flutter::MethodResult<Value>>;
  MenuLocalTools(HWND owner, std::function<bool()> current,
      std::function<void(bool)> modal, std::function<void()> dismiss);
  ~MenuLocalTools();
  void Handle(const flutter::EncodableMap& args, Result result);
  // Trusted primary Host reply only. This arms ONE explicit direct save;
  // the auxiliary surface cannot provide a path or reuse old authorization.
  bool AuthorizeScreenshotDirectory(const std::string& directory);
  void Hide();
  // Session detachment retires local pages/images without deleting the browser
  // profile. Ordinary menu hiding only suspends them.
  void Reset();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
