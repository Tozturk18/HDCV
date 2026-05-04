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

add_executable(hdcv_viewer
  src/hdcv_viewer.m
)

target_link_libraries(hdcv_viewer PRIVATE
  hdcv_core
  "-framework AppKit"
  "-framework CoreGraphics"
  "-framework QuartzCore"
  "-framework Foundation"
  "-framework UniformTypeIdentifiers"
)

target_compile_options(hdcv_viewer PRIVATE ${HDCV_OBJC_WARNINGS} -fobjc-arc)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_options(hdcv_core PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  target_compile_options(hdcv_reader PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  target_compile_options(hdcv_viewer PRIVATE -O0 -g3 -fno-omit-frame-pointer)
  if(CMAKE_C_COMPILER_ID MATCHES "Clang|AppleClang|GNU")
    target_compile_options(hdcv_core PRIVATE -fsanitize=address,undefined)
    target_compile_options(hdcv_reader PRIVATE -fsanitize=address,undefined)
    target_compile_options(hdcv_viewer PRIVATE -fsanitize=address,undefined)
    target_link_options(hdcv_reader PRIVATE -fsanitize=address,undefined)
    target_link_options(hdcv_viewer PRIVATE -fsanitize=address,undefined)
  endif()
else()
  target_compile_options(hdcv_core PRIVATE -O3)
  target_compile_options(hdcv_reader PRIVATE -O3)
  target_compile_options(hdcv_viewer PRIVATE -O3)
endif()
