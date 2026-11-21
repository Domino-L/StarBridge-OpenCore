#pragma once

#include "hangar_browser_data.h"
#include "rsi_tool_notice_async.h"

#include <filesystem>
#include <functional>
#include <memory>
#include <utility>

namespace hangar_data {

// Deletes the reader's browser folder on a worker thread. The result comes
// back on the creating (UI) thread through a thread timer, so the window keeps
// painting and answering input. A WebView2 folder holds thousands of cache
// files; deleting them on the UI thread made the window "not responding"
// (build 66). One clear at a time: a second request while one runs is refused,
// and the caller reports "busy" instead of waiting.
class BackgroundClear {
 public:
  BackgroundClear() = default;
  BackgroundClear(const BackgroundClear&) = delete;
  BackgroundClear& operator=(const BackgroundClear&) = delete;

  bool Busy() const { return busy_; }

  // Returns false, without calling `done`, while a clear is already running.
  // Otherwise `done` runs once, later, on this thread. It never runs after
  // this object is destroyed; a worker that outlives it only finishes deleting.
  bool Start(std::filesystem::path folder, std::filesystem::path expected_root,
             std::function<void(ClearResult)> done) {
    if (busy_) return false;
    busy_ = true;
    // Written by the worker before it reports; read here only after the
    // report is collected under the same lock.
    auto outcome = std::make_shared<ClearResult>(ClearResult::failed);
    work_.Submit(
        [folder = std::move(folder), expected_root = std::move(expected_root), outcome] {
          *outcome = ClearBrowserData(folder, expected_root);
          return *outcome == ClearResult::success;
        },
        [this, outcome, done = std::move(done)](bool) {
          busy_ = false;
          done(*outcome);
        });
    return true;
  }

 private:
  bool busy_ = false;
  rsi_tool_notice::AsyncWork work_;
};

}  // namespace hangar_data
