#include "native_host_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

constexpr UINT kPipeEventMessage = WM_APP + 0x53;
constexpr size_t kMaximumFrameBytes = 1024 * 1024;
constexpr size_t kMaximumQueuedFrames = 128;

enum class PipeEventKind { kConnected, kFrame, kDisconnected };

using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

struct PipeEvent {
  PipeEventKind kind = PipeEventKind::kDisconnected;
  uint64_t generation = 0;
  std::vector<uint8_t> frame;
  std::string error;
  std::unique_ptr<MethodResult> result;
};

std::string LastErrorCode(const char* prefix) {
  return std::string(prefix) + "." + std::to_string(GetLastError());
}

bool ReadExact(HANDLE pipe, uint8_t* target, size_t length) {
  HANDLE completed = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  if (!completed) {
    return false;
  }
  size_t offset = 0;
  while (offset < length) {
    DWORD received = 0;
    const DWORD requested = static_cast<DWORD>(
        std::min(length - offset, static_cast<size_t>(MAXDWORD)));
    ResetEvent(completed);
    OVERLAPPED operation{};
    operation.hEvent = completed;
    if (!ReadFile(pipe, target + offset, requested, &received, &operation)) {
      if (GetLastError() != ERROR_IO_PENDING ||
          WaitForSingleObject(completed, INFINITE) != WAIT_OBJECT_0 ||
          !GetOverlappedResult(pipe, &operation, &received, FALSE)) {
        CloseHandle(completed);
        return false;
      }
    }
    if (received == 0) {
      CloseHandle(completed);
      return false;
    }
    offset += received;
  }
  CloseHandle(completed);
  return true;
}

bool WriteExact(HANDLE pipe, const uint8_t* source, size_t length) {
  HANDLE completed = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  if (!completed) {
    return false;
  }
  size_t offset = 0;
  while (offset < length) {
    DWORD written = 0;
    const DWORD requested = static_cast<DWORD>(
        std::min(length - offset, static_cast<size_t>(MAXDWORD)));
    ResetEvent(completed);
    OVERLAPPED operation{};
    operation.hEvent = completed;
    if (!WriteFile(pipe, source + offset, requested, &written, &operation)) {
      if (GetLastError() != ERROR_IO_PENDING ||
          WaitForSingleObject(completed, INFINITE) != WAIT_OBJECT_0 ||
          !GetOverlappedResult(pipe, &operation, &written, FALSE)) {
        CloseHandle(completed);
        return false;
      }
    }
    if (written == 0) {
      CloseHandle(completed);
      return false;
    }
    offset += written;
  }
  CloseHandle(completed);
  return true;
}

bool IsValidFrame(const std::vector<uint8_t>& frame) {
  if (frame.size() < 5 || frame.size() > kMaximumFrameBytes + 4) {
    return false;
  }
  const uint32_t payload_length =
      static_cast<uint32_t>(frame[0]) |
      (static_cast<uint32_t>(frame[1]) << 8) |
      (static_cast<uint32_t>(frame[2]) << 16) |
      (static_cast<uint32_t>(frame[3]) << 24);
  return payload_length > 0 && payload_length <= kMaximumFrameBytes &&
         payload_length == frame.size() - 4;
}

}  // namespace

class NativeHostBridge::Impl {
 public:
  Impl(HWND window, flutter::BinaryMessenger* messenger)
      : window_(window),
        channel_(std::make_unique<
                 flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, "starbridge/native-host",
            &flutter::StandardMethodCodec::GetInstance())) {
    channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  ~Impl() {
    Shutdown();
    channel_->SetMethodCallHandler(nullptr);
    MSG message{};
    while (PeekMessage(&message, nullptr, kPipeEventMessage,
                       kPipeEventMessage, PM_REMOVE)) {
      delete reinterpret_cast<PipeEvent*>(message.lParam);
    }
  }

  bool HandleWindowMessage(UINT message, LPARAM lparam) noexcept {
    if (message != kPipeEventMessage) {
      return false;
    }
    std::unique_ptr<PipeEvent> event(reinterpret_cast<PipeEvent*>(lparam));
    if (!event) {
      return true;
    }
    switch (event->kind) {
      case PipeEventKind::kConnected:
        if (!event->result) {
          break;
        }
        if (event->error.empty()) {
          event->result->Success(flutter::EncodableValue(
              static_cast<int64_t>(event->generation)));
        } else {
          event->result->Error("host.pipe.connect_failed", event->error);
        }
        break;
      case PipeEventKind::kFrame:
        if (event->generation == generation_.load() && !shutting_down_) {
          flutter::EncodableMap arguments;
          arguments[flutter::EncodableValue("generation")] =
              flutter::EncodableValue(static_cast<int64_t>(event->generation));
          arguments[flutter::EncodableValue("frame")] =
              flutter::EncodableValue(event->frame);
          channel_->InvokeMethod(
              "frame", std::make_unique<flutter::EncodableValue>(arguments));
        }
        break;
      case PipeEventKind::kDisconnected:
        if (event->generation == generation_.load() && !shutting_down_) {
          flutter::EncodableMap arguments;
          arguments[flutter::EncodableValue("generation")] =
              flutter::EncodableValue(static_cast<int64_t>(event->generation));
          arguments[flutter::EncodableValue("code")] =
              flutter::EncodableValue(event->error);
          channel_->InvokeMethod(
              "disconnected",
              std::make_unique<flutter::EncodableValue>(arguments));
        }
        break;
    }
    return true;
  }

  void Shutdown() noexcept {
    if (shutting_down_.exchange(true)) {
      return;
    }
    CloseConnection();
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<MethodResult> result) {
    if (call.method_name() == "connect") {
      const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!arguments) {
        result->Error("host.pipe.invalid_arguments", "connect requires a map");
        return;
      }
      const auto pipe_iterator = arguments->find(flutter::EncodableValue("pipeName"));
      const auto timeout_iterator =
          arguments->find(flutter::EncodableValue("timeoutMilliseconds"));
      if (pipe_iterator == arguments->end() ||
          timeout_iterator == arguments->end()) {
        result->Error("host.pipe.invalid_arguments", "connect arguments are incomplete");
        return;
      }
      const auto* pipe_name = std::get_if<std::string>(&pipe_iterator->second);
      const auto* timeout = std::get_if<int32_t>(&timeout_iterator->second);
      if (!pipe_name) {
        result->Error("host.pipe.invalid_arguments", "pipe name is invalid");
        return;
      }
      if (!timeout) {
        const auto* timeout64 = std::get_if<int64_t>(&timeout_iterator->second);
        if (timeout64 && *timeout64 > 0 && *timeout64 <= INT32_MAX) {
          StartConnect(*pipe_name, static_cast<int>(*timeout64), std::move(result));
          return;
        }
      }
      if (!pipe_name || pipe_name->empty() || !timeout || *timeout <= 0) {
        result->Error("host.pipe.invalid_arguments", "connect arguments are invalid");
        return;
      }
      StartConnect(*pipe_name, *timeout, std::move(result));
      return;
    }
    if (call.method_name() == "send") {
      const auto* frame = std::get_if<std::vector<uint8_t>>(call.arguments());
      if (!frame || !IsValidFrame(*frame)) {
        result->Error("host.pipe.invalid_frame", "bridge frame is invalid");
        return;
      }
      std::string error;
      if (!QueueFrame(*frame, &error)) {
        result->Error(error, "bridge frame was not queued");
        return;
      }
      result->Success();
      return;
    }
    if (call.method_name() == "close") {
      CloseConnection();
      result->Success();
      return;
    }
    result->NotImplemented();
  }

  void StartConnect(const std::string& pipe_name, int timeout_milliseconds,
                    std::unique_ptr<MethodResult> result) {
    if (pipe_name.find('\\') != std::string::npos ||
        pipe_name.find('/') != std::string::npos) {
      result->Error("host.pipe.invalid_name", "pipe name must be local");
      return;
    }
    CloseConnection();
    shutting_down_ = false;
    disconnect_reported_ = false;
    const uint64_t generation = generation_.fetch_add(1) + 1;
    const std::wstring wide_name(pipe_name.begin(), pipe_name.end());
    connect_thread_ = std::thread(
        [this, wide_name, timeout_milliseconds, generation,
         result = std::move(result)]() mutable {
          const std::wstring path = L"\\\\.\\pipe\\" + wide_name;
          const auto deadline = std::chrono::steady_clock::now() +
              std::chrono::milliseconds(timeout_milliseconds);
          HANDLE pipe = INVALID_HANDLE_VALUE;
          std::string error = "host.pipe.connect_timeout";
          while (!shutting_down_ && std::chrono::steady_clock::now() < deadline) {
            pipe = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                               nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED,
                               nullptr);
            if (pipe != INVALID_HANDLE_VALUE) {
              error.clear();
              break;
            }
            const DWORD last_error = GetLastError();
            if (last_error != ERROR_PIPE_BUSY &&
                last_error != ERROR_FILE_NOT_FOUND) {
              error = LastErrorCode("host.pipe.open_failed");
              break;
            }
            WaitNamedPipeW(path.c_str(), 100);
          }

          if (pipe != INVALID_HANDLE_VALUE && !shutting_down_ &&
              generation == generation_.load()) {
            {
              std::scoped_lock lock(state_mutex_);
              pipe_ = pipe;
              connected_ = true;
            }
            reader_thread_ = std::thread([this, pipe, generation]() {
              ReadLoop(pipe, generation);
            });
            writer_thread_ = std::thread([this, pipe, generation]() {
              WriteLoop(pipe, generation);
            });
          } else if (pipe != INVALID_HANDLE_VALUE) {
            CloseHandle(pipe);
            if (error.empty()) {
              error = "host.pipe.connect_cancelled";
            }
          }

          auto event = std::make_unique<PipeEvent>();
          event->kind = PipeEventKind::kConnected;
          event->generation = generation;
          event->error = std::move(error);
          event->result = std::move(result);
          PostEvent(std::move(event));
        });
  }

  bool QueueFrame(const std::vector<uint8_t>& frame, std::string* error) {
    std::scoped_lock lock(write_mutex_);
    if (!connected_) {
      *error = "host.pipe.not_connected";
      return false;
    }
    if (write_queue_.size() >= kMaximumQueuedFrames) {
      *error = "host.pipe.backpressure";
      return false;
    }
    write_queue_.push_back(frame);
    write_ready_.notify_one();
    return true;
  }

  void ReadLoop(HANDLE pipe, uint64_t generation) {
    while (!shutting_down_ && generation == generation_.load()) {
      std::vector<uint8_t> header(4);
      if (!ReadExact(pipe, header.data(), header.size())) {
        ReportDisconnected(generation, "host.pipe.read_failed");
        return;
      }
      const uint32_t payload_length =
          static_cast<uint32_t>(header[0]) |
          (static_cast<uint32_t>(header[1]) << 8) |
          (static_cast<uint32_t>(header[2]) << 16) |
          (static_cast<uint32_t>(header[3]) << 24);
      if (payload_length == 0 || payload_length > kMaximumFrameBytes) {
        ReportDisconnected(generation, "host.pipe.invalid_frame");
        return;
      }
      std::vector<uint8_t> frame(4 + payload_length);
      std::copy(header.begin(), header.end(), frame.begin());
      if (!ReadExact(pipe, frame.data() + 4, payload_length)) {
        ReportDisconnected(generation, "host.pipe.read_failed");
        return;
      }
      auto event = std::make_unique<PipeEvent>();
      event->kind = PipeEventKind::kFrame;
      event->generation = generation;
      event->frame = std::move(frame);
      PostEvent(std::move(event));
    }
  }

  void WriteLoop(HANDLE pipe, uint64_t generation) {
    while (!shutting_down_ && generation == generation_.load()) {
      std::vector<uint8_t> frame;
      {
        std::unique_lock lock(write_mutex_);
        write_ready_.wait(lock, [this, generation]() {
          return shutting_down_ || generation != generation_.load() ||
                 !write_queue_.empty();
        });
        if (shutting_down_ || generation != generation_.load()) {
          return;
        }
        frame = std::move(write_queue_.front());
        write_queue_.pop_front();
      }
      if (!WriteExact(pipe, frame.data(), frame.size())) {
        ReportDisconnected(generation, "host.pipe.write_failed");
        return;
      }
    }
  }

  void ReportDisconnected(uint64_t generation, const std::string& error) {
    if (shutting_down_) {
      return;
    }
    if (disconnect_reported_.exchange(true)) {
      return;
    }
    {
      std::scoped_lock lock(state_mutex_);
      connected_ = false;
      if (pipe_ != INVALID_HANDLE_VALUE) {
        CancelIoEx(pipe_, nullptr);
        CloseHandle(pipe_);
        pipe_ = INVALID_HANDLE_VALUE;
      }
    }
    write_ready_.notify_all();
    auto event = std::make_unique<PipeEvent>();
    event->kind = PipeEventKind::kDisconnected;
    event->generation = generation;
    event->error = error;
    PostEvent(std::move(event));
  }

  void CloseConnection() noexcept {
    shutting_down_ = true;
    {
      std::scoped_lock lock(state_mutex_);
      connected_ = false;
      if (pipe_ != INVALID_HANDLE_VALUE) {
        CancelIoEx(pipe_, nullptr);
        CloseHandle(pipe_);
        pipe_ = INVALID_HANDLE_VALUE;
      }
    }
    write_ready_.notify_all();
    if (connect_thread_.joinable()) {
      connect_thread_.join();
    }
    if (reader_thread_.joinable()) {
      reader_thread_.join();
    }
    if (writer_thread_.joinable()) {
      writer_thread_.join();
    }
    {
      std::scoped_lock lock(write_mutex_);
      write_queue_.clear();
    }
  }

  void PostEvent(std::unique_ptr<PipeEvent> event) noexcept {
    PipeEvent* raw = event.release();
    if (!PostMessage(window_, kPipeEventMessage, 0,
                     reinterpret_cast<LPARAM>(raw))) {
      delete raw;
    }
  }

  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::mutex state_mutex_;
  std::mutex write_mutex_;
  std::condition_variable write_ready_;
  std::deque<std::vector<uint8_t>> write_queue_;
  std::thread connect_thread_;
  std::thread reader_thread_;
  std::thread writer_thread_;
  HANDLE pipe_ = INVALID_HANDLE_VALUE;
  std::atomic<uint64_t> generation_{0};
  std::atomic<bool> shutting_down_{false};
  std::atomic<bool> disconnect_reported_{false};
  std::atomic<bool> connected_{false};
};

NativeHostBridge::NativeHostBridge(HWND window,
                                   flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(window, messenger)) {}

NativeHostBridge::~NativeHostBridge() = default;

bool NativeHostBridge::HandleWindowMessage(UINT message,
                                           LPARAM lparam) noexcept {
  return impl_->HandleWindowMessage(message, lparam);
}

void NativeHostBridge::Shutdown() noexcept { impl_->Shutdown(); }
