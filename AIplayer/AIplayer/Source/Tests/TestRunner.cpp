/*
  ==============================================================================

    TestRunner.cpp
    Created: 18 Jun 2025
    Author:  Nick Fox

    Main test runner for AIplayer unit tests.
    
    To run tests:
    1. Build the project with TEST_BUILD=1 defined
    2. Run the plugin or standalone app
    3. Tests will run automatically and output results

  ==============================================================================
*/

#include <JuceHeader.h>

#ifdef TEST_BUILD

namespace AIplayer {

class TestRunner : public juce::JUCEApplication
{
public:
    TestRunner() {}
    
    const juce::String getApplicationName() override { return "AIplayer Tests"; }
    const juce::String getApplicationVersion() override { return "1.0.0"; }
    bool moreThanOneInstanceAllowed() override { return false; }
    
    void initialise(const juce::String&) override
    {
        // Run all tests
        juce::UnitTestRunner testRunner;
        testRunner.setAssertOnFailure(false);
        
        // Run tests and collect results
        testRunner.runAllTests();
        
        // Output results
        int numTests = testRunner.getNumResults();
        int numPassed = 0;
        int numFailed = 0;
        
        for (int i = 0; i < numTests; ++i)
        {
            auto* result = testRunner.getResult(i);
            if (result != nullptr)
            {
                if (result->failures > 0)
                {
                    numFailed++;
                    DBG("FAILED: " << result->unitTestName << " - " << result->failures << " failures");
                    
                    // Print failure messages
                    for (const auto& message : result->messages)
                    {
                        DBG("  " << message);
                    }
                }
                else
                {
                    numPassed++;
                    DBG("PASSED: " << result->unitTestName);
                }
            }
        }
        
        DBG("=====================================");
        DBG("Test Results: " << numPassed << " passed, " << numFailed << " failed");
        DBG("=====================================");
        
        // Exit with appropriate code
        quit();
        setApplicationReturnValue(numFailed > 0 ? 1 : 0);
    }
    
    void shutdown() override {}
    
    void systemRequestedQuit() override
    {
        quit();
    }
};

} // namespace AIplayer

// Create the application instance
START_JUCE_APPLICATION(AIplayer::TestRunner)

#else // TEST_BUILD not defined

// For normal builds, include this file but don't create test runner
namespace AIplayer {
    
// Function to run tests programmatically (can be called from plugin)
void runAllTests(bool outputToConsole = true)
{
    juce::UnitTestRunner testRunner;
    testRunner.setAssertOnFailure(false);
    
    if (outputToConsole)
    {
        DBG("Running AIplayer Tests...");
    }
    
    testRunner.runAllTests();
    
    int numTests = testRunner.getNumResults();
    int numPassed = 0;
    int numFailed = 0;
    
    for (int i = 0; i < numTests; ++i)
    {
        auto* result = testRunner.getResult(i);
        if (result != nullptr)
        {
            if (result->failures > 0)
            {
                numFailed++;
            }
            else
            {
                numPassed++;
            }
        }
    }
    
    if (outputToConsole)
    {
        DBG("Test Results: " << numPassed << " passed, " << numFailed << " failed");
    }
}

} // namespace AIplayer

#endif // TEST_BUILD