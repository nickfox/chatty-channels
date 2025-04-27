cmake_minimum_required(VERSION 3.15)
project(AIplayerPlugin VERSION 0.5 LANGUAGES CXX)

# -----------------------------------------------------------------------------
# Global compile settings
# -----------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_BUILD_TYPE Debug)

# -----------------------------------------------------------------------------
# JUCE configuration (adjust paths as needed)
# -----------------------------------------------------------------------------
set(JUCE_MODULES_DIR "/Users/nickfox137/Downloads/JUCE/modules")
add_definitions(-DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1 -DDEBUG=1)
include_directories(${JUCE_MODULES_DIR})

# -----------------------------------------------------------------------------
# JUCE library code (produces JuceLibraryCode target)
# -----------------------------------------------------------------------------
add_subdirectory(JuceLibraryCode)

# -----------------------------------------------------------------------------
# Core library: pure C++ / DSP code shared by plug‑in and unit tests
# -----------------------------------------------------------------------------
add_library(core STATIC
    Source/RMSCircularBuffer.cpp            # ← add more "core" .cpp files here
)

target_include_directories(core PUBLIC
    ${PROJECT_SOURCE_DIR}/Source            # exposes headers (e.g. RMSCircularBuffer.h)
)

# -----------------------------------------------------------------------------
# Plug‑in / application target (defined in Source/CMakeLists.txt)
# -----------------------------------------------------------------------------
add_subdirectory(Source)

target_link_libraries(AIplayerPluginSource PRIVATE core)

# -----------------------------------------------------------------------------
# Unit tests (defined in Tests/CMakeLists.txt)
# -----------------------------------------------------------------------------
add_subdirectory(Tests)
