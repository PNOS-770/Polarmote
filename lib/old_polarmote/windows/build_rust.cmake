# Build Rust transfer core
# Usage: cmake -DCrateDir=... -DOutputDir=... -DConfig=... -DPlatform=... -P build_rust.cmake

if(NOT DEFINED CrateDir)
  message(FATAL_ERROR "CrateDir not defined")
endif()
if(NOT DEFINED OutputDir)
  message(FATAL_ERROR "OutputDir not defined")
endif()
if(NOT DEFINED Config)
  set(Config "Debug")
endif()
if(NOT DEFINED Platform)
  set(Platform "windows")
endif()

set(RustScript "${CrateDir}/scripts/build_desktop_libs.ps1")

if(NOT EXISTS "${RustScript}")
  message(FATAL_ERROR "Rust desktop build script not found: ${RustScript}")
endif()

if(Config MATCHES "Debug")
  set(RustProfile "debug")
else()
  set(RustProfile "release")
endif()

# Set OpenSSL environment variables
set(ENV{OPENSSL_DIR} "C:/Program Files/OpenSSL-Win64")
set(ENV{OPENSSL_LIB_DIR} "C:/Program Files/OpenSSL-Win64/lib/VC/x64/MT")
set(ENV{OPENSSL_INCLUDE_DIR} "C:/Program Files/OpenSSL-Win64/include")

execute_process(
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File "${RustScript}"
    -CrateDir "${CrateDir}"
    -OutputDir "${OutputDir}"
    -Profile "${RustProfile}"
    -Platform "${Platform}"
  RESULT_VARIABLE RustBuildRc
)

if(NOT RustBuildRc EQUAL 0)
  message(FATAL_ERROR "Failed to build Rust transfer core (exit code: ${RustBuildRc})")
endif()
