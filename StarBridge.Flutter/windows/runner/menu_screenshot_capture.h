#ifndef RUNNER_MENU_SCREENSHOT_CAPTURE_H_
#define RUNNER_MENU_SCREENSHOT_CAPTURE_H_
#include <flutter/encodable_value.h>
#include <optional>

inline std::optional<bool> MenuCaptureHidesMenu(const flutter::EncodableMap& args) {
  using V = flutter::EncodableValue;
  for (const auto& field : args) {
    const auto* key = std::get_if<std::string>(&field.first);
    if (!key || (*key != "action" && *key != "opening" && *key != "hideMenu")) return std::nullopt;
  }
  const auto setting = args.find(V("hideMenu"));
  if (setting == args.end()) return true; // Existing callers keep their behavior.
  if (const auto* value = std::get_if<bool>(&setting->second)) return *value;
  return std::nullopt;
}

// The capture owner supplies native visibility operations. Always release the
// presentation lease, including empty captures and exceptions; no second capture.
template <typename Prepare, typename Finish, typename Capture>
auto RunMenuCapture(bool hide, Prepare prepare, Finish finish, Capture capture) {
  struct Release {
    Finish& finish;
    ~Release() { finish(); }
  } release{finish};
  prepare(hide);
  return capture();
}
#endif
