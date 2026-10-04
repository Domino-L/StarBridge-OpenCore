#ifndef RUNNER_MENU_SCREENSHOT_STORAGE_H_
#define RUNNER_MENU_SCREENSHOT_STORAGE_H_
#include <windows.h>
#include <objbase.h>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace menu_screenshot {
inline bool ValidDirectory(const std::wstring& directory) {
  if (directory.empty() || directory.size() > 32767 ||
      directory.rfind(L"\\\\?\\", 0) == 0 || directory.rfind(L"\\\\.\\", 0) == 0 ||
      !std::filesystem::path(directory).is_absolute()) return false;
  for (const auto character : directory) if (character < 32 || character == 127) return false;
  for (const auto& part : std::filesystem::path(directory)) if (part == L"." || part == L"..") return false;
  return true;
}

// Both save-as and direct export use the same complete-write/flush/atomic-commit
// implementation. Only an explicit save-as may replace an existing file.
inline bool WriteAtomic(const std::wstring& destination, const std::vector<uint8_t>& bytes,
    const std::function<bool()>& current, bool replace) {
  if (bytes.empty() || bytes.size() > 32 * 1024 * 1024 || !current()) return false;
  GUID id{}; wchar_t suffix[40]{};
  if (FAILED(CoCreateGuid(&id)) || !StringFromGUID2(id, suffix, static_cast<int>(std::size(suffix)))) return false;
  const auto temporary = destination + L".starbridge-" + suffix + L".tmp";
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool complete = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) &&
      written == bytes.size() && FlushFileBuffers(file);
  CloseHandle(file);
  const bool saved = complete && current() && MoveFileExW(temporary.c_str(), destination.c_str(),
      (replace ? MOVEFILE_REPLACE_EXISTING : 0) | MOVEFILE_WRITE_THROUGH);
  // Capture the commit error before cleanup, for collision-only retries.
  const auto error = GetLastError();
  if (!saved) DeleteFileW(temporary.c_str());
  SetLastError(error);
  return saved;
}

inline std::wstring SaveUnique(const std::wstring& directory, const std::vector<uint8_t>& bytes,
    bool jpeg, const SYSTEMTIME& time, const std::function<bool()>& current) {
  if (!ValidDirectory(directory) || bytes.empty() || bytes.size() > 32 * 1024 * 1024 || !current() ||
      time.wYear < 1 || time.wYear > 9999 || time.wMonth < 1 || time.wMonth > 12 ||
      time.wDay < 1 || time.wDay > 31 || time.wHour > 23 || time.wMinute > 59 || time.wSecond > 59 || time.wMilliseconds > 999) return {};
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  if (error || !std::filesystem::is_directory(directory, error) || error || !current()) return {};
  wchar_t stem[80]{};
  swprintf_s(stem, L"StarBridge_%04u%02u%02u_%02u%02u%02u_%03u", static_cast<unsigned>(time.wYear),
      static_cast<unsigned>(time.wMonth), static_cast<unsigned>(time.wDay), static_cast<unsigned>(time.wHour),
      static_cast<unsigned>(time.wMinute), static_cast<unsigned>(time.wSecond), static_cast<unsigned>(time.wMilliseconds));
  for (unsigned index = 1; index <= 9999 && current(); ++index) {
    wchar_t collision[20]{};
    if (index > 1) swprintf_s(collision, L"_%02u", index);
    const auto name = std::wstring(stem) + collision + (jpeg ? L".jpg" : L".png");
    const auto destination = (std::filesystem::path(directory) / name).wstring();
    if (WriteAtomic(destination, bytes, current, false)) return destination;
    const auto failed = GetLastError();
    if (failed != ERROR_ALREADY_EXISTS && failed != ERROR_FILE_EXISTS) return {};
  }
  return {};
}
}
#endif
