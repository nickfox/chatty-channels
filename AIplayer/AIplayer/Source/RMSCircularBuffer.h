// /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Source/RMSCircularBuffer.h

#ifndef RMS_CIRCULAR_BUFFER_H
#define RMS_CIRCULAR_BUFFER_H

#include <vector>
#include <cstddef>
#include <stdexcept>

/// Circular buffer to store float RMS telemetry values.
class RMSCircularBuffer {
public:
    /// Constructs a buffer with a given capacity (default is 80).
    explicit RMSCircularBuffer(std::size_t capacity = 80);

    /// Inserts a new value into the buffer.
    /// If the buffer is full, the oldest value is overwritten.
    void push(float value);

    /// Returns the number of values currently stored.
    std::size_t size() const;

    /// Returns the total capacity of the buffer.
    std::size_t capacity() const;

    /// Provides access to the stored values in logical order.
    /// If the buffer is full, the oldest element is at index 0.
    float operator[](std::size_t index) const;

    /// Clears the buffer.
    void clear();

    /// Returns the contents of the buffer as a std::vector in logical order.
    std::vector<float> toVector() const;

private:
    std::vector<float> buffer;
    std::size_t head;   // Next index to write, also the index of the oldest element when full.
    std::size_t count;  // Number of elements stored.
    std::size_t cap;    // Capacity of the buffer.
};

#endif // RMS_CIRCULAR_BUFFER_H