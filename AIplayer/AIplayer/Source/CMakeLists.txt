cmake_minimum_required(VERSION 3.15)
project(AIplayerPluginSource)

# List source files (modify if additional files exist)
set(SOURCE_FILES
    PluginProcessor.cpp
    PluginEditor.cpp
)

# List header files (optional)
set(HEADER_FILES
    PluginProcessor.h
    PluginEditor.h
)

# Create a static library for the plugin source code
add_library(AIplayerPluginSource STATIC ${SOURCE_FILES} ${HEADER_FILES})

# Include current directory for header files
target_include_directories(AIplayerPluginSource PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../JuceLibraryCode
    ${CMAKE_CURRENT_SOURCE_DIR}/../JuceLibraryCode/modules
)
if(DEFINED ENV{JUCE_MODULES_DIR})
    target_include_directories(AIplayerPluginSource PRIVATE $ENV{JUCE_MODULES_DIR})
endif()

# Link against the Juce library code
target_link_libraries(AIplayerPluginSource PRIVATE JuceLibraryCode)