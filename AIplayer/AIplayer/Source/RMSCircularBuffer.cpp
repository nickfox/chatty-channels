// /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Source/RMSCircularBuffer.cpp

#include "RMSCircularBuffer.h"
#include <stdexcept>

RMSCircularBuffer::RMSCircularBuffer(std::size_t capacity)
    : buffer(capacity, 0.0f), head(0), count(0), cap(capacity) {}

void RMSCircularBuffer::push(float value) {
    buffer[head] = value;
    head = (head + 1) % cap;
    if (count < cap) {
        ++count;
    }
}

std::size_t RMSCircularBuffer::size() const {
    return count;
}

std::size_t RMSCircularBuffer::capacity() const {
    return cap;
}

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

void RMSCircularBuffer::clear() {
    count = 0;
    head = 0;
}

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