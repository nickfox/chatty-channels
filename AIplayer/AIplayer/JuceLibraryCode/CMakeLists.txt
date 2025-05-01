# ─── JuceLibraryCode : minimal CMake wrapper ─────────────────────────────
cmake_minimum_required(VERSION 3.15)

project(JuceLibraryCode LANGUAGES CXX)

# Pick up every .cpp / .mm file Projucer generated in this directory
file(GLOB JUCE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_LIST_DIR}/*.cpp"
     "${CMAKE_CURRENT_LIST_DIR}/*.mm")

add_library(JuceLibraryCode STATIC ${JUCE_SOURCES})

# Public include paths: this folder *and* the JUCE modules folder
target_include_directories(JuceLibraryCode PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}
    ${JUCE_MODULES_DIR}
)

# Match the rest of your project (feel free to tweak)
target_compile_features(JuceLibraryCode PUBLIC cxx_std_17)

# macOS frameworks (no-ops on Windows/Linux)
if(APPLE)
    find_library(FOUNDATION Foundation)
    find_library(APPKIT     AppKit)
    target_link_libraries(JuceLibraryCode PUBLIC ${FOUNDATION} ${APPKIT})
endif()
