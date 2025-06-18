// /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Source/RMSCircularBuffer.cpp

#include "RMSCircularBuffer.h"
#include <stdexcept>

namespace AIplayer {

/**
 * @brief Constructs a circular buffer with the specified capacity
 *
 * Initializes an empty buffer with the given capacity, setting all values to 0.0f.
 *
 * @param capacity The maximum number of elements the buffer can store
 */
RMSCircularBuffer::RMSCircularBuffer(std::size_t capacity)
    : buffer(capacity, 0.0f), head(0), count(0), cap(capacity) {}

/**
 * @brief Adds a new value to the buffer
 *
 * Stores the value at the current head position and updates the head.
 * If the buffer is not yet full, the count is incremented.
 *
 * @param value The new float value to add to the buffer
 */
void RMSCircularBuffer::push(float value) {
    buffer[head] = value;
    head = (head + 1) % cap;
    if (count < cap) {
        ++count;
    }
}

/**
 * @brief Gets the current number of values stored in the buffer
 *
 * @return The number of values currently stored
 */
std::size_t RMSCircularBuffer::size() const {
    return count;
}

/**
 * @brief Gets the total capacity of the buffer
 *
 * @return The maximum number of elements the buffer can store
 */
std::size_t RMSCircularBuffer::capacity() const {
    return cap;
}

/**
 * @brief Accesses buffer elements by index in logical order
 *
 * This method handles two different cases:
 * 1. When the buffer is full (count == cap), the logical index must be
 *    translated to the physical index in the underlying vector.
 * 2. When the buffer is not full, the logical index matches the physical index.
 *
 * @param index The logical index of the element to access
 * @return The value at the specified index
 * @throws std::out_of_range if the index is out of range
 */
float RMSCircularBuffer::operator[](std::size_t index) const {
    if (index >= count) {
        throw std::out_of_range("Index out of range in RMSCircularBuffer");
    }
    if (count == cap) {
        std::size_t realIndex = (head + index) % cap;
        return buffer[realIndex];
    } else {
        return buffer[index];
    }
}

/**
 * @brief Removes all values from the buffer
 *
 * Resets the count and head to 0, effectively clearing the buffer
 * without deallocating memory.
 */
void RMSCircularBuffer::clear() {
    count = 0;
    head = 0;
}

/**
 * @brief Converts the buffer contents to a standard vector
 *
 * Creates a new vector containing all elements from the buffer in logical order.
 * The algorithm handles two cases:
 * 1. When the buffer is full (count == cap), elements are rearranged to
 *    put the oldest element first.
 * 2. When the buffer is not full, elements are copied in their original order.
 *
 * @return A vector containing all buffer elements in logical order
 */
std::vector<float> RMSCircularBuffer::toVector() const {
    std::vector<float> vec;
    vec.reserve(count);
    if (count == cap) {
        for (std::size_t i = 0; i < cap; i++) {
            std::size_t idx = (head + i) % cap;
            vec.push_back(buffer[idx]);
        }
    } else {
        for (std::size_t i = 0; i < count; i++) {
            vec.push_back(buffer[i]);
        }
    }
    return vec;
}

} // namespace AIplayer