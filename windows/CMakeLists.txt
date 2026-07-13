# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(Polarmote LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "Polarmote")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Build Rust native core
set(RUST_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native/Polarmote_native_core")
set(RUST_BUILD_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/build_rust.cmake")
set(RUST_OUTPUT_DIR "${CMAKE_BINARY_DIR}/rust_output")

# Always build Rust core
add_custom_target(build_rust_core ALL
  COMMAND ${CMAKE_COMMAND}
    -DCrateDir=${RUST_CORE_DIR}
    -DOutputDir=${RUST_OUTPUT_DIR}
    -DConfig=$<CONFIG>
    -DPlatform=windows
    -P ${RUST_BUILD_SCRIPT}
  COMMENT "Building Rust native core..."
  VERBATIM
)

# Copy Rust DLL to output directory after building
add_custom_command(TARGET build_rust_core POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${BINARY_NAME}>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${RUST_OUTPUT_DIR}/Polarmote_native_core.dll"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/Polarmote_native_core.dll"
  COMMENT "Copying Rust native core DLL..."
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# Ensure super_native_extensions precompiled binaries are present before plugin
# targets start building.
set(SUPER_NATIVE_PRECOMPILED_SCRIPT
  "${CMAKE_CURRENT_SOURCE_DIR}/ensure_super_native_precompiled.cmake")
add_custom_target(ensure_super_native_precompiled ALL
  COMMAND ${CMAKE_COMMAND}
    -DPolarmote_ROOT_DIR:PATH=${CMAKE_CURRENT_SOURCE_DIR}/..
    -DBUILD_DIR:PATH=${CMAKE_BINARY_DIR}
    -P ${SUPER_NATIVE_PRECOMPILED_SCRIPT}
  VERBATIM
)

if(TARGET super_native_extensions)
  add_dependencies(super_native_extensions ensure_super_native_precompiled)
endif()
if(TARGET super_native_extensions_plugin)
  add_dependencies(super_native_extensions_plugin ensure_super_native_precompiled)
endif()
if(TARGET super_native_extensions_plugin_cargokit)
  add_dependencies(super_native_extensions_plugin_cargokit ensure_super_native_precompiled)
endif()

# media_kit_video depends on ANGLE & libmpv archives being extracted by
# media_kit_libs_windows_video at build time.  If the extraction targets exist,
# force a build‑order dependency so compilation doesn't race with extraction.
if(TARGET media_kit_libs_windows_video_LIBMPV_EXTRACT AND TARGET media_kit_libs_windows_video_ANGLE_EXTRACT AND TARGET media_kit_video_plugin)
  add_dependencies(media_kit_video_plugin media_kit_libs_windows_video_LIBMPV_EXTRACT)
  add_dependencies(media_kit_video_plugin media_kit_libs_windows_video_ANGLE_EXTRACT)
endif()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
# Always install into the local build bundle directory.
# This avoids stale cached prefixes (e.g. Program Files) causing
# non-admin builds to fail at INSTALL.vcxproj.
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Build and copy the Rust transfer core.
set(RUST_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native/Polarmote_native_core")
set(RUST_BUILD_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/build_rust.cmake")
set(RUST_OUTPUT_DIR "${CMAKE_BINARY_DIR}/rust_output")

# Copy Rust DLL to install directory
install(FILES "${RUST_OUTPUT_DIR}/Polarmote_native_core.dll"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Legacy: Keep the install-time build as fallback
install(CODE "
  if(NOT EXISTS \"${INSTALL_BUNDLE_LIB_DIR}/Polarmote_native_core.dll\")
    if(CMAKE_INSTALL_CONFIG_NAME MATCHES \"Debug\")
      set(_config Debug)
    else()
      set(_config Release)
    endif()
    execute_process(
      COMMAND \${CMAKE_COMMAND}
        -DCrateDir=${RUST_CORE_DIR}
        -DOutputDir=${INSTALL_BUNDLE_LIB_DIR}
        -DConfig=\${_config}
        -DPlatform=windows
        -P ${RUST_BUILD_SCRIPT}
      RESULT_VARIABLE _rust_build_rc
    )
    if(NOT _rust_build_rc EQUAL 0)
      message(FATAL_ERROR \"Failed to build Rust transfer core (exit code: \${_rust_build_rc})\")
    endif()
  endif()
  " COMPONENT Runtime)
