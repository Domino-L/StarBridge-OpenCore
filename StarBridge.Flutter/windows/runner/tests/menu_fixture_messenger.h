#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <map>

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
// Local synchronous caller for the real menu protocol, never a remote channel.
class FixtureMessenger : public flutter::BinaryMessenger {
 public:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
  Value last_result;
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply reply) const override {
    if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string& name, flutter::BinaryMessageHandler handler) override {
    handlers[name] = std::move(handler);
  }
  std::string Call(const char* method, Value args = Value()) {
    std::string outcome = "no_reply";
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    auto encoded = codec.EncodeMethodCall(flutter::MethodCall<Value>(method, std::make_unique<Value>(args)));
    flutter::MethodResultFunctions<Value> result(
        [this, &outcome](const Value* value) {
          outcome = "success";
          last_result = value ? *value : Value();
        },
        [&outcome](const std::string& code, const std::string&, const Value*) { outcome = code; },
        [&outcome]() { outcome = "not_implemented"; });
    handlers.at("starbridge/menu-primary")(encoded->data(), encoded->size(),
        [&codec, &result, &outcome](const uint8_t* bytes, size_t count) {
          if (!bytes || count == 0) outcome = "not_implemented";
          else codec.DecodeAndProcessResponseEnvelope(bytes, count, &result);
        });
    return outcome;
  }
};
