# AIplayer Architecture Refactoring Plan

## Current State
The AIplayer plugin currently has a monolithic architecture with the PluginProcessor class containing over 1800 lines of code. This violates core software engineering principles and makes the codebase difficult to maintain, test, and extend.

## Problems with Current Architecture

### 1. Single Responsibility Principle Violations
The PluginProcessor class currently handles:
- Audio processing and gain control
- OSC message sending and receiving
- Port assignment and management
- Calibration tone generation
- RMS level calculations
- Timer management and callbacks
- Logging infrastructure
- State persistence
- Track UUID management

### 2. Poor Testability
- Cannot unit test RMS calculations without instantiating the entire plugin
- OSC communication is tightly coupled to audio processing
- No way to mock dependencies for testing
- Timer callbacks are embedded in the main class

### 3. Maintenance Issues
- Difficult to locate specific functionality
- High risk of introducing bugs when modifying code
- No clear separation between audio thread and UI thread code
- Error handling is scattered throughout the file

## Proposed Architecture

### Core Design Principles
1. **Single Responsibility**: Each class has one clear purpose
2. **Dependency Injection**: Components receive dependencies rather than creating them
3. **Interface Segregation**: Use protocols/interfaces to define contracts
4. **Thread Safety**: Clear separation of audio thread vs. other thread operations

### Component Breakdown

```
AIplayer/
├── Source/
│   ├── PluginProcessor.h/cpp          (300-400 lines max)
│   ├── PluginEditor.h/cpp
│   ├── Audio/
│   │   ├── AudioMetrics.h/cpp
│   │   └── CalibrationToneGenerator.h/cpp
│   ├── Communication/
│   │   ├── OSCManager.h/cpp
│   │   ├── PortManager.h/cpp
│   │   └── TelemetryService.h/cpp
│   ├── Core/
│   │   ├── Logger.h/cpp
│   │   └── Constants.h
│   └── Models/
│       ├── TrackInfo.h
│       └── TelemetryData.h
```

### Detailed Component Specifications

#### 1. OSCManager
**Responsibility**: All OSC communication (sending and receiving)

```cpp
class OSCManager : public juce::OSCReceiver::Listener<juce::OSCReceiver::MessageLoopCallback> {
public:
    class Listener {
    public:
        virtual ~Listener() = default;
        virtual void handleTrackAssignment(const juce::String& trackID) = 0;
        virtual void handlePortAssignment(int port) = 0;
        virtual void handleParameterChange(const juce::String& param, float value) = 0;
    };
    
    OSCManager(Logger& logger);
    
    bool connect(const juce::String& remoteHost, int remotePort);
    void bindReceiver(int port);
    
    void sendTelemetry(const TelemetryData& data);
    void sendPortRequest(const juce::String& instanceID);
    
    void addListener(Listener* listener);
    void removeListener(Listener* listener);
    
private:
    juce::OSCSender sender;
    juce::OSCReceiver receiver;
    Logger& logger;
    juce::ListenerList<Listener> listeners;
    
    void oscMessageReceived(const juce::OSCMessage& message) override;
};
```

#### 2. AudioMetrics
**Responsibility**: RMS calculations and other audio measurements

```cpp
class AudioMetrics {
public:
    AudioMetrics();
    
    float calculateRMS(const juce::AudioBuffer<float>& buffer);
    void updateMetrics(const juce::AudioBuffer<float>& buffer);
    
    float getCurrentRMS() const { return currentRMS.load(); }
    float getPeakLevel() const { return peakLevel.load(); }
    
private:
    std::atomic<float> currentRMS{0.0f};
    std::atomic<float> peakLevel{0.0f};
    
    // Thread-safe buffer for RMS calculation
    juce::AudioBuffer<float> metricsBuffer;
    juce::CriticalSection bufferLock;
};
```

#### 3. TelemetryService
**Responsibility**: Collect and format telemetry data for transmission

```cpp
class TelemetryService : public juce::Timer {
public:
    TelemetryService(AudioMetrics& metrics, 
                     OSCManager& oscManager,
                     Logger& logger);
    
    void setTrackID(const juce::String& trackID);
    void startTelemetry(int frequencyHz = 24);
    void stopTelemetry();
    
private:
    AudioMetrics& audioMetrics;
    OSCManager& oscManager;
    Logger& logger;
    
    juce::String currentTrackID;
    
    void timerCallback() override;
    TelemetryData collectTelemetryData();
};
```

#### 4. PortManager
**Responsibility**: Handle port assignment protocol with ChattyChannels

```cpp
class PortManager {
public:
    enum class State {
        Unassigned,
        Requesting,
        Assigned,
        Bound,
        Failed
    };
    
    PortManager(OSCManager& oscManager, Logger& logger);
    
    void requestPort(const juce::String& instanceID);
    bool bindToPort(int port);
    
    State getState() const { return currentState; }
    int getAssignedPort() const { return assignedPort; }
    
private:
    OSCManager& oscManager;
    Logger& logger;
    
    State currentState{State::Unassigned};
    int assignedPort{-1};
    int retryCount{0};
    
    static constexpr int maxRetries = 5;
};
```

#### 5. CalibrationToneGenerator
**Responsibility**: Generate calibration tones for track identification

```cpp
class CalibrationToneGenerator {
public:
    CalibrationToneGenerator();
    
    void prepare(double sampleRate, int samplesPerBlock);
    void setTone(float frequency, float amplitudeDb);
    void startTone();
    void stopTone();
    
    void processBlock(juce::AudioBuffer<float>& buffer);
    
private:
    juce::dsp::Oscillator<float> oscillator;
    std::atomic<bool> toneEnabled{false};
    std::atomic<float> frequency{440.0f};
    std::atomic<float> amplitude{0.1f};
};
```

#### 6. Logger
**Responsibility**: Centralized logging with thread safety

```cpp
class Logger {
public:
    enum class Level {
        Debug,
        Info,
        Warning,
        Error
    };
    
    Logger(const juce::File& logFile);
    
    void log(Level level, const juce::String& message);
    void setMinimumLevel(Level level);
    
private:
    std::unique_ptr<juce::FileOutputStream> logStream;
    juce::CriticalSection logLock;
    Level minimumLevel{Level::Info};
    
    juce::String getLevelString(Level level);
    void writeToFile(const juce::String& message);
};
```

### Refactored PluginProcessor

The PluginProcessor becomes a thin coordinator:

```cpp
class AIplayerAudioProcessor : public juce::AudioProcessor {
public:
    AIplayerAudioProcessor();
    ~AIplayerAudioProcessor();
    
    // AudioProcessor overrides
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    
    // Component access for editor
    AudioMetrics& getAudioMetrics() { return *audioMetrics; }
    
private:
    // Core components
    std::unique_ptr<Logger> logger;
    std::unique_ptr<AudioMetrics> audioMetrics;
    std::unique_ptr<CalibrationToneGenerator> toneGenerator;
    
    // Communication components
    std::unique_ptr<OSCManager> oscManager;
    std::unique_ptr<PortManager> portManager;
    std::unique_ptr<TelemetryService> telemetryService;
    
    // Plugin state
    juce::AudioProcessorValueTreeState apvts;
    std::atomic<float>* gainParameter{nullptr};
    
    void initializeComponents();
    void setupOSCCommunication();
};
```

## Implementation Strategy

### Phase 1: Core Infrastructure (Week 1)
1. Create directory structure
2. Implement Logger class
3. Create base interfaces and data models
4. Set up CMake/Projucer for new structure

### Phase 2: Extract Audio Components (Week 2)
1. Extract AudioMetrics class  
2. Extract CalibrationToneGenerator
3. Update PluginProcessor to use new components

### Phase 3: Extract Communication (Week 3)
1. Extract OSCManager class
2. Extract PortManager class
3. Extract TelemetryService class
4. Wire up communication flow

### Phase 4: Testing & Validation (Week 4)
1. Create unit tests for each component
2. Integration testing
3. Performance profiling
4. Fix any regressions

## Benefits of Refactoring

### 1. Maintainability
- Each component has a clear, single responsibility
- Easy to locate and modify specific functionality
- Reduced risk of introducing bugs

### 2. Testability
- Each component can be unit tested in isolation
- Mock implementations can be created for testing
- Better code coverage possible

### 3. Extensibility
- New features can be added without modifying core components
- Different implementations can be swapped (e.g., different audio analysis methods)
- Clear interfaces make it easy to understand component contracts

### 4. Performance
- Better control over thread allocation
- Reduced lock contention
- Optimized memory usage per component

### 5. Team Collaboration
- Multiple developers can work on different components
- Reduced merge conflicts
- Clear ownership boundaries

## Success Metrics

1. **Code Quality**
   - No single file over 500 lines
   - Each class has a single, clear responsibility
   - 80%+ unit test coverage

2. **Performance**
   - No regression in CPU usage
   - Improved memory allocation patterns
   - Maintained real-time audio performance

3. **Maintainability**
   - Reduced time to implement new features
   - Easier onboarding for new developers
   - Clear documentation for each component

## Risks and Mitigation

### Risk 1: Regression Bugs
**Mitigation**: Comprehensive test suite before refactoring begins

### Risk 2: Performance Degradation  
**Mitigation**: Profile before and after each phase

### Risk 3: Breaking Existing Functionality
**Mitigation**: Incremental refactoring with continuous testing

## Conclusion

This refactoring is essential for the long-term health of the AIplayer project. While it requires significant effort upfront, it will pay dividends in reduced bugs, easier feature development, and improved team productivity. The proposed architecture follows industry best practices and will position AIplayer as a truly production-ready audio plugin.

## Implementation Notes for v0.7 Refactoring

### Starting Point
- Working with v0.7 codebase (NO FFT implementation)
- Current PluginProcessor.cpp is ~1800 lines (monolithic)
- Everything works but is not maintainable/testable
- Build system: Xcode project (NOT CMake)
- Project location: `/Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Builds/MacOSX/AIplayer.xcodeproj`

### Critical Build Information
- This is a JUCE project using .jucer file
- Must add new files to Xcode project manually
- Build scheme: "AIplayer - AU"
- Test with Logic Pro using kick drum on TR1
- Logs location: `~/Documents/chatty-channel/logs/AIplayer.log`

### Implementation Order (DO NOT SKIP STEPS)
1. **Create directory structure first**
   - Source/Core/
   - Source/Audio/
   - Source/Communication/
   - Source/Models/

2. **Start with Logger component**
   - Already created in previous attempt
   - Initialize in PluginProcessor constructor
   - Replace all logMessage() calls incrementally

3. **Extract AudioMetrics next**
   - Move RMS calculation only (no FFT)
   - Keep thread safety with bufferLock
   - Test that VU meters still work

4. **Add files to Xcode project**
   - Right-click Source group → Add Files
   - Select "Create groups" not "Create folder references"
   - Add to target: "AIplayer - Shared Code"

### Key Refactoring Principles
- Keep existing functionality working at all times
- Test after each component extraction
- Use forward declarations to minimize header dependencies
- All components use AIplayer namespace
- Production quality: proper error handling, no memory leaks

### Testing Checklist After Each Component
- [ ] Project builds without errors
- [ ] Plugin loads in Logic Pro
- [ ] OSC communication works (port assignment)
- [ ] RMS telemetry sends correctly
- [ ] VU meters update in ChattyChannels
- [ ] Calibration tone works
- [ ] No memory leaks or crashes

### Common Pitfalls to Avoid
- Don't try to refactor everything at once
- Don't break the build - test frequently
- Don't forget to update #includes when moving code
- Don't modify ChattyChannels UI (it's fragile)
- Remember track IDs are "TR1", "TR2" not "TR01"