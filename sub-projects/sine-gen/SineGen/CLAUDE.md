# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a JUCE audio plugin project called SineGen - a simple synthesizer plugin that generates a sine wave at 137Hz. The project is configured to build as both AU (Audio Unit) and VST3 formats on macOS.

## Build Commands

To build the project:
```bash
# Navigate to the Xcode project directory
cd Builds/MacOSX

# Build Debug configuration
xcodebuild -project SineGen.xcodeproj -configuration Debug

# Build Release configuration
xcodebuild -project SineGen.xcodeproj -configuration Release

# Clean build
xcodebuild -project SineGen.xcodeproj clean
```

## Architecture

The project follows the standard JUCE plugin architecture:

- **PluginProcessor** (Source/PluginProcessor.cpp/h): Core audio processing logic
  - Uses `juce::dsp::Oscillator` for sine wave generation
  - Fixed frequency at 137Hz
  - Processes audio in stereo format
  - No MIDI support, no GUI editor

- **JuceLibraryCode/**: Auto-generated JUCE framework code
- **SineGen.jucer**: JUCE project configuration file
- **Builds/MacOSX/**: Xcode project and build outputs

## Key Technical Details

- JUCE version: 8.0.8 (modules located at ../../JUCE-8.0.8/modules)
- Plugin formats: AU and VST3
- Company: websmithing (com.websmithing.SineGen)
- Plugin type: Synthesizer (pluginIsSynth)
- No MIDI input/output
- No GUI (hasEditor returns false)

## Development Notes

When modifying the plugin:
- The oscillator frequency is hardcoded in the constructor
- The plugin uses JUCE's DSP module for efficient audio processing
- All audio processing happens in `processBlock()`
- The plugin has no parameters or state saving/loading implemented