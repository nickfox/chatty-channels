cmake_minimum_required(VERSION 3.15)
project(AIplayerPluginTests LANGUAGES CXX)

# ── Fetch Catch2 v2 ───────────────────────────────────────────
include(FetchContent)
FetchContent_Declare(
  Catch2
  GIT_REPOSITORY https://github.com/catchorg/Catch2.git
  GIT_TAG        v2.13.9
)
FetchContent_MakeAvailable(Catch2)
list(APPEND CMAKE_MODULE_PATH "${Catch2_SOURCE_DIR}/extras")

# ── Test executable ───────────────────────────────────────────
add_executable(RMSBufferTests
    RMSBufferTests.cpp
)

target_include_directories(RMSBufferTests
    PRIVATE
        ${PROJECT_SOURCE_DIR}/Source      # for RMSCircularBuffer.h
        ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(RMSBufferTests
    PRIVATE
        Catch2::Catch2
        core                              # <── the library defined above
)

# ── Auto-register tests with CTest ────────────────────────────
include(CTest)
include(${Catch2_SOURCE_DIR}/contrib/Catch.cmake)
catch_discover_tests(RMSBufferTests)
