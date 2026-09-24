#pragma once
#include <windows.h>
#include <WebView2.h>
#include <string>

inline bool IsHangarProfileKey(const std::string& key) {
  return key.size() == 64 && key.find_first_not_of("0123456789ABCDEF") == std::string::npos;
}

inline HRESULT ConfigureHangarProfile(ICoreWebView2ControllerOptions* options, const std::string& key) {
  if (!options || !IsHangarProfileKey(key)) return E_INVALIDARG;
  // ProfileName permits at most 64 characters. Keep the entire digest: no prefix or truncation.
  const std::wstring name(key.begin(), key.end());
  auto result = options->put_IsInPrivateModeEnabled(FALSE);
  return FAILED(result) ? result : options->put_ProfileName(name.c_str());
}

inline void SetHangarInteraction(HWND viewport, HWND flutter_parent, bool locked) {
  if (locked) SetFocus(flutter_parent);
  EnableWindow(viewport, locked ? FALSE : TRUE);
}
