#ifndef RUNNER_MENU_BROWSER_OPTIONS_H_
#define RUNNER_MENU_BROWSER_OPTIONS_H_
#include <flutter/encodable_value.h>
#include <optional>
#include <string>

// Preferences contain behavior only: no address, script, profile or account.
struct MenuBrowserOptions {
  int32_t limit = 8;
  bool new_tab = true, pause_hidden = true;
  static std::optional<MenuBrowserOptions> Parse(const flutter::EncodableValue& value) {
    using V = flutter::EncodableValue;
    const auto map = std::get_if<flutter::EncodableMap>(&value);
    if (!map || map->size() != 4) return {};
    const auto field = [&](const char* key) -> const V* {
      const auto it = map->find(V(key)); return it == map->end() ? nullptr : &it->second;
    };
    const auto p = field("provider"), n = field("tabLimit"), links = field("openLinksInNewTab"), pause = field("pauseWhenHidden");
    if (!p || !n || !links || !pause) return {};
    const auto provider = std::get_if<std::string>(p);
    const auto new_tab = std::get_if<bool>(links), pause_hidden = std::get_if<bool>(pause);
    int64_t limit = 0;
    if (const auto i = std::get_if<int32_t>(n)) limit = *i;
    else if (const auto wide = std::get_if<int64_t>(n)) limit = *wide;
    if (!provider || (*provider != "bing-cn" && *provider != "baidu" && *provider != "google" &&
        *provider != "duckduckgo" && *provider != "bing-global") || !new_tab || !pause_hidden || limit < 1 || limit > 12) return {};
    return MenuBrowserOptions{static_cast<int32_t>(limit), *new_tab, *pause_hidden};
  }
};
#endif
