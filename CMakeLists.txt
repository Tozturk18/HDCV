cmake_minimum_required(VERSION 3.20)

project(hdcv_reader LANGUAGES C OBJC)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(APPLE AND NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architectures" FORCE)
endif()

set(HDCV_COMMON_WARNINGS
  -Wall
  -Wextra
  -Wpedantic
  -Wconversion
  -Wshadow
  -Wstrict-prototypes
  -Wmissing-prototypes
)

set(HDCV_OBJC_WARNINGS
  -Wall
  -Wextra
  -Wpedantic
  -Wshadow
)

add_library(hdcv_core STATIC
  src/hdcv_utils.c
  src/hdcv_metadata.c
  src/hdcv_reader.c
  src/hdcv_export.c
  src/hdcv_analysis.c
)

target_include_directories(hdcv_core PUBLIC src)
target_compile_options(hdcv_core PRIVATE ${HDCV_COMMON_WARNINGS})

add_executable(hdcv_reader
  src/main.c
)

target_link_libraries(hdcv_reader PRIVATE hdcv_core)
target_compile_options(hdcv_reader PRIVATE ${HDCV_COMMON_WARNINGS})

set(HDCV_VIEWER_FRAMEWORKS
  "-framework AppKit"
  "-framework CoreGraphics"
  "-framework QuartzCore"
  "-framework Foundation"
  "-framework UniformTypeIdentifiers"
)

function(configure_hdcv_viewer_target target_name)
  target_link_libraries(${target_name} PRIVATE
    hdcv_core
    ${HDCV_VIEWER_FRAMEWORKS}
  )
  target_compile_options(${target_name} PRIVATE ${HDCV_OBJC_WARNINGS} -fobjc-arc)
endfunction()

add_executable(hdcv_viewer
  src/hdcv_viewer.m
)
configure_hdcv_viewer_target(hdcv_viewer)

set(HDCV_VIEWER_TARGETS hdcv_viewer)

if(APPLE)
  add_executable(hdcv_viewer_app MACOSX_BUNDLE
    src/hdcv_viewer.m
  )
  configure_hdcv_viewer_target(hdcv_viewer_app)
  list(APPEND HDCV_VIEWER_TARGETS hdcv_viewer_app)
  set_target_properties(hdcv_viewer_app PROPERTIES
    OUTPUT_NAME "HDCV Viewer"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/cmake/HDCVViewerInfo.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME "HDCV Viewer"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.hdcv.viewer"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.hdcv.viewer"
  )
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_options(hdcv_core PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  target_compile_options(hdcv_reader PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  foreach(viewer_target IN LISTS HDCV_VIEWER_TARGETS)
    target_compile_options(${viewer_target} PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  endforeach()
  if(CMAKE_C_COMPILER_ID MATCHES "Clang|AppleClang|GNU")
    target_compile_options(hdcv_core PRIVATE -fsanitize=address,undefined)
    target_compile_options(hdcv_reader PRIVATE -fsanitize=address,undefined)
    foreach(viewer_target IN LISTS HDCV_VIEWER_TARGETS)
      target_compile_options(${viewer_target} PRIVATE -fsanitize=address,undefined)
      target_link_options(${viewer_target} PRIVATE -fsanitize=address,undefined)
    endforeach()
    target_link_options(hdcv_reader PRIVATE -fsanitize=address,undefined)
  endif()
else()
  target_compile_options(hdcv_core PRIVATE -O3)
  target_compile_options(hdcv_reader PRIVATE -O3)
  foreach(viewer_target IN LISTS HDCV_VIEWER_TARGETS)
    target_compile_options(${viewer_target} PRIVATE -O3)
  endforeach()
endif()
