// /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Source/RMSCircularBuffer.h

#ifndef RMS_CIRCULAR_BUFFER_H
#define RMS_CIRCULAR_BUFFER_H

#include <vector>
#include <cstddef>
#include <stdexcept>

namespace AIplayer {

/**
 * @class RMSCircularBuffer
 * @brief Circular buffer for storing float RMS telemetry values
 *
 * This class implements a circular buffer (ring buffer) that efficiently stores
 * a fixed number of float values. When the buffer is full, new values overwrite
 * the oldest values. This is particularly useful for storing time-series data
 * like RMS audio levels where only the most recent values are needed.
 */
class RMSCircularBuffer {
public:
    /**
     * @brief Constructs a circular buffer with the specified capacity
     *
     * @param capacity The maximum number of elements the buffer can store (default: 80)
     */
    explicit RMSCircularBuffer(std::size_t capacity = 80);

    /**
     * @brief Adds a new value to the buffer
     *
     * If the buffer is full, the oldest value is overwritten.
     *
     * @param value The new float value to add to the buffer
     */
    void push(float value);

    /**
     * @brief Gets the current number of values stored in the buffer
     *
     * @return The number of values currently stored
     */
    std::size_t size() const;

    /**
     * @brief Gets the total capacity of the buffer
     *
     * @return The maximum number of elements the buffer can store
     */
    std::size_t capacity() const;

    /**
     * @brief Accesses buffer elements by index in logical order
     *
     * This operator allows accessing buffer elements in logical order,
     * where index 0 is the oldest element (when the buffer is full).
     *
     * @param index The logical index of the element to access
     * @return The value at the specified index
     * @throws std::out_of_range if the index is out of range
     */
    float operator[](std::size_t index) const;

    /**
     * @brief Removes all values from the buffer
     *
     * After calling this method, the buffer will be empty (size() will return 0).
     */
    void clear();

    /**
     * @brief Converts the buffer contents to a standard vector
     *
     * The elements in the vector will be in logical order,
     * with the oldest element (when the buffer is full) at index 0.
     *
     * @return A vector containing all buffer elements in logical order
     */
    std::vector<float> toVector() const;

private:
    /**
     * @brief The underlying storage for buffer elements
     */
    std::vector<float> buffer;
    
    /**
     * @brief Index of the next element to write
     *
     * This is also the index of the oldest element when the buffer is full.
     */
    std::size_t head;
    
    /**
     * @brief Number of elements currently stored in the buffer
     */
    std::size_t count;
    
    /**
     * @brief Maximum capacity of the buffer
     */
    std::size_t cap;
};

} // namespace AIplayer

#endif // RMS_CIRCULAR_BUFFER_H