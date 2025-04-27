// /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Tests/RMSBufferTests.cpp

#define CATCH_CONFIG_MAIN
#include "../Source/RMSCircularBuffer.h"
#include <catch2/catch.hpp>

TEST_CASE("RMSCircularBuffer basic functionality", "[RMSBuffer]") {
    // Create a circular buffer with capacity 5
    RMSCircularBuffer buffer(5);
    
    // Initially, the buffer should be empty
    REQUIRE(buffer.size() == 0);
    
    // Push some values and verify size and contents
    buffer.push(1.0f);
    buffer.push(2.0f);
    buffer.push(3.0f);
    REQUIRE(buffer.size() == 3);
    
    std::vector<float> vec = buffer.toVector();
    REQUIRE(vec.size() == 3);
    REQUIRE(vec[0] == Approx(1.0f));
    REQUIRE(vec[1] == Approx(2.0f));
    REQUIRE(vec[2] == Approx(3.0f));
    
    // Test clear functionality
    buffer.clear();
    REQUIRE(buffer.size() == 0);
}

TEST_CASE("RMSCircularBuffer overflow handling", "[RMSBuffer]") {
    // Create a buffer with capacity 3
    RMSCircularBuffer buffer(3);
    
    // Fill the buffer to capacity
    buffer.push(1.0f);
    buffer.push(2.0f);
    buffer.push(3.0f);
    REQUIRE(buffer.size() == 3);
    
    // Push additional values (should overwrite oldest)
    buffer.push(4.0f);
    buffer.push(5.0f);
    
    // Size should remain at capacity
    REQUIRE(buffer.size() == 3);
    
    // Verify oldest values were overwritten (1.0f, 2.0f should be gone)
    std::vector<float> vec = buffer.toVector();
    REQUIRE(vec.size() == 3);
    REQUIRE(vec[0] == Approx(3.0f));
    REQUIRE(vec[1] == Approx(4.0f));
    REQUIRE(vec[2] == Approx(5.0f));
}

TEST_CASE("RMSCircularBuffer operator access", "[RMSBuffer]") {
    RMSCircularBuffer buffer(4);
    
    // Add some values
    buffer.push(10.0f);
    buffer.push(20.0f);
    buffer.push(30.0f);
    
    // Test operator[] access
    REQUIRE(buffer[0] == Approx(10.0f));
    REQUIRE(buffer[1] == Approx(20.0f));
    REQUIRE(buffer[2] == Approx(30.0f));
    
    // Test out-of-range exception
    REQUIRE_THROWS_AS(buffer[3], std::out_of_range);
    
    // Fill buffer past capacity
    buffer.push(40.0f);
    buffer.push(50.0f);
    
    // Check correct indexing after overflow
    REQUIRE(buffer[0] == Approx(20.0f)); // 10.0f was overwritten
    REQUIRE(buffer[1] == Approx(30.0f));
    REQUIRE(buffer[2] == Approx(40.0f));
    REQUIRE(buffer[3] == Approx(50.0f));
}

TEST_CASE("RMSCircularBuffer capacity", "[RMSBuffer]") {
    const size_t testCapacity = 100;
    RMSCircularBuffer buffer(testCapacity);
    
    // Verify capacity matches constructor argument
    REQUIRE(buffer.capacity() == testCapacity);
    
    // Fill half the buffer
    for (size_t i = 0; i < testCapacity / 2; ++i) {
        buffer.push(static_cast<float>(i));
    }
    
    // Verify size reflects added elements
    REQUIRE(buffer.size() == testCapacity / 2);
    
    // Verify capacity remains unchanged
    REQUIRE(buffer.capacity() == testCapacity);
}