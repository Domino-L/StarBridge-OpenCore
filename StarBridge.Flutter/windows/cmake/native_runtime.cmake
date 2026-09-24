# One SDK selection for both the managed build and the staged runtime path.
# CI may select an installed SDK; normal developer builds keep the project default.
set(STARBRIDGE_TARGET_PLATFORM_VERSION "$ENV{STARBRIDGE_TARGET_PLATFORM_VERSION}"
  CACHE STRING "Windows SDK used by the managed native runtime")
if(NOT STARBRIDGE_TARGET_PLATFORM_VERSION)
  set(STARBRIDGE_TARGET_PLATFORM_VERSION "10.0.22621.0")
endif()
if(NOT STARBRIDGE_TARGET_PLATFORM_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
  message(FATAL_ERROR "Invalid managed Windows SDK version")
endif()
set(SB_NATIVE_FRAMEWORK "net8.0-windows${STARBRIDGE_TARGET_PLATFORM_VERSION}")
set(SB_NATIVE_SDK_PROPERTY "-p:StarBridgeTargetPlatformVersion=${STARBRIDGE_TARGET_PLATFORM_VERSION}")
