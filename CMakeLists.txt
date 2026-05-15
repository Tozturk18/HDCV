cmake_minimum_required(VERSION 3.20)

project(hdcv_reader LANGUAGES C OBJC)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(APPLE AND NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architectures" FORCE)
endif()

if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version" FORCE)
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

add_executable(hdcv
  src/hdcv_cli.c
)

target_link_libraries(hdcv PRIVATE hdcv_core)
target_compile_options(hdcv PRIVATE ${HDCV_COMMON_WARNINGS})

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
  set(HDCV_VIEWER_ICON "${CMAKE_CURRENT_SOURCE_DIR}/resources/HDCVViewer.icns")
  set_source_files_properties(${HDCV_VIEWER_ICON} PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources
  )
  add_executable(hdcv_viewer_app MACOSX_BUNDLE
    src/hdcv_viewer.m
    ${HDCV_VIEWER_ICON}
  )
  configure_hdcv_viewer_target(hdcv_viewer_app)
  list(APPEND HDCV_VIEWER_TARGETS hdcv_viewer_app)
  set_target_properties(hdcv_viewer_app PROPERTIES
    OUTPUT_NAME "HDCV Viewer"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/cmake/HDCVViewerInfo.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME "HDCV Viewer"
    MACOSX_BUNDLE_ICON_FILE "HDCVViewer.icns"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.tozturk.hdcvviewer"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.tozturk.hdcvviewer"
  )
  add_dependencies(hdcv_viewer_app hdcv)
  add_custom_command(TARGET hdcv_viewer_app POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:hdcv_viewer_app>/Contents/Resources/bin"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:hdcv>" "$<TARGET_BUNDLE_DIR:hdcv_viewer_app>/Contents/Resources/bin/hdcv"
    COMMENT "Embedding hdcv command line tool in HDCV Viewer.app"
  )
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_options(hdcv_core PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  target_compile_options(hdcv_reader PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  target_compile_options(hdcv PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  foreach(viewer_target IN LISTS HDCV_VIEWER_TARGETS)
    target_compile_options(${viewer_target} PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  endforeach()
  if(CMAKE_C_COMPILER_ID MATCHES "Clang|AppleClang|GNU")
    target_compile_options(hdcv_core PRIVATE -fsanitize=address,undefined)
    target_compile_options(hdcv_reader PRIVATE -fsanitize=address,undefined)
    target_compile_options(hdcv PRIVATE -fsanitize=address,undefined)
    foreach(viewer_target IN LISTS HDCV_VIEWER_TARGETS)
      target_compile_options(${viewer_target} PRIVATE -fsanitize=address,undefined)
      target_link_options(${viewer_target} PRIVATE -fsanitize=address,undefined)
    endforeach()
    target_link_options(hdcv_reader PRIVATE -fsanitize=address,undefined)
    target_link_options(hdcv PRIVATE -fsanitize=address,undefined)
  endif()
else()
  target_compile_options(hdcv_core PRIVATE -O3)
  target_compile_options(hdcv_reader PRIVATE -O3)
  target_compile_options(hdcv PRIVATE -O3)
  foreach(viewer_target IN LISTS HDCV_VIEWER_TARGETS)
    target_compile_options(${viewer_target} PRIVATE -O3)
  endforeach()
endif()
