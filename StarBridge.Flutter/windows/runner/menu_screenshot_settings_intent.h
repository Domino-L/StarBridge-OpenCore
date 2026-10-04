#ifndef RUNNER_MENU_SCREENSHOT_SETTINGS_INTENT_H_
#define RUNNER_MENU_SCREENSHOT_SETTINGS_INTENT_H_
#include <flutter/encodable_value.h>

// The auxiliary settings UI may read a path, but never supplies one to Host.
inline bool ValidScreenshotSettingsIntent(const flutter::EncodableMap& args) {
  using V = flutter::EncodableValue;
  const auto action = args.find(V("action"));
  if (action == args.end()) return false;
  const auto* text = std::get_if<std::string>(&action->second);
  if (!text || args.find(V("opening")) == args.end()) return false;
  if (*text == "read") return args.size() == 2;
  if ((*text != "choose" && *text != "reset" && *text != "open") || args.size() != 3) return false;
  const auto revision = args.find(V("revision"));
  if (revision == args.end()) return false;
  if (const auto* value = std::get_if<int64_t>(&revision->second)) return *value >= 0;
  if (const auto* value = std::get_if<int32_t>(&revision->second)) return *value >= 0;
  return false;
}
#endif
