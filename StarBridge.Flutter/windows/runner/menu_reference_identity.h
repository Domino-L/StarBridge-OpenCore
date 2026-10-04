#ifndef RUNNER_MENU_REFERENCE_IDENTITY_H_
#define RUNNER_MENU_REFERENCE_IDENTITY_H_
#include <windows.h>
#include <objbase.h>
#include <array>
#include <deque>
#include <optional>
#include <string>
#include <algorithm>

namespace menu_image {
// Never sent to Flutter: same file/version only, sampled from the already-open
// picker handle while other writers are denied. No pathname is retained.
using ReferenceFileKey = std::array<DWORD, 9>;
inline std::optional<ReferenceFileKey> ReferenceKey(HANDLE file) {
  BY_HANDLE_FILE_INFORMATION info{};
  if (file == INVALID_HANDLE_VALUE || !GetFileInformationByHandle(file, &info) ||
      (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
      (!info.nFileIndexHigh && !info.nFileIndexLow)) return std::nullopt;
  return ReferenceFileKey{info.dwVolumeSerialNumber, info.nFileIndexHigh,
    info.nFileIndexLow, info.nFileSizeHigh, info.nFileSizeLow,
    info.ftCreationTime.dwHighDateTime, info.ftCreationTime.dwLowDateTime,
    info.ftLastWriteTime.dwHighDateTime, info.ftLastWriteTime.dwLowDateTime};
}
class ReferenceIdentityCache {
 public:
  static constexpr size_t kLimit = 32;
  std::optional<std::string> Resolve(const std::optional<ReferenceFileKey>& key) {
    if (!key) return std::nullopt;
    const auto found = std::find_if(entries_.begin(), entries_.end(),
      [&key](const auto& entry) { return entry.first == *key; });
    if (found != entries_.end()) {
      const auto entry = *found;
      entries_.erase(found); entries_.push_back(entry); return entry.second;
    }
    GUID id{}; wchar_t text[40]{};
    if (FAILED(CoCreateGuid(&id)) || !StringFromGUID2(id, text, 40)) return std::nullopt;
    std::string token;
    for (const auto ch : text) { if (!ch) break; token.push_back(static_cast<char>(ch)); }
    if (entries_.size() == kLimit) entries_.pop_front();
    entries_.emplace_back(*key, token); return token;
  }
  void Clear() { entries_.clear(); }
  size_t Size() const { return entries_.size(); }
 private:
  std::deque<std::pair<ReferenceFileKey, std::string>> entries_;
};
}
#endif
