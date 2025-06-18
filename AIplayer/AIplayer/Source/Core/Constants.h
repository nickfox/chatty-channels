/*
  ==============================================================================

    Constants.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Global constants and configuration values for AIplayer plugin.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"

namespace AIplayer {

/**
 * @namespace Constants
 * @brief Global constants used throughout the AIplayer plugin
 */
namespace Constants {

    // OSC Communication
    constexpr const char* OSC_HOST = "127.0.0.1";
    constexpr int OSC_CHATTY_CHANNELS_PORT = 8999;
    constexpr int OSC_EPHEMERAL_PORT_START = 50000;
    constexpr int OSC_EPHEMERAL_PORT_END = 60000;
    constexpr int OSC_EPHEMERAL_PORT_STEP = 100;
    
    // Timing
    constexpr int TELEMETRY_RATE_HZ = 24;  // Cinema framerate for smooth VU meters
    constexpr int PORT_REQUEST_TIMEOUT_MS = 2000;
    constexpr int PORT_REQUEST_MAX_RETRIES = 5;
    constexpr int OSC_RECONNECT_DELAY_MS = 100;
    
    // Audio
    constexpr float DEFAULT_TONE_FREQUENCY = 440.0f;
    constexpr float DEFAULT_TONE_AMPLITUDE_DB = -20.0f;
    constexpr double DEFAULT_SAMPLE_RATE = 44100.0;
    constexpr int DEFAULT_BLOCK_SIZE = 512;
    
    // RMS
    constexpr float RMS_MINIMUM_VALUE = 0.0001f;
    constexpr float RMS_EPSILON = 1.0e-10f;
    
    // OSC Address Patterns
    namespace OSCAddresses {
        // Outgoing messages (to ChattyChannels)
        constexpr const char* REQUEST_PORT = "/aiplayer/request_port";
        constexpr const char* PORT_CONFIRMED = "/aiplayer/port_confirmed";
        constexpr const char* RMS_TELEMETRY = "/aiplayer/rms";
        constexpr const char* RMS_TELEMETRY_UNIDENTIFIED = "/aiplayer/rms_unidentified";
        constexpr const char* TELEMETRY = "/aiplayer/telemetry";
        constexpr const char* UUID_CONFIRMED = "/aiplayer/uuid_assignment_confirmed";
        constexpr const char* TONE_STARTED = "/aiplayer/tone_started";
        constexpr const char* TONE_STOPPED = "/aiplayer/tone_stopped";
        constexpr const char* TONE_STATUS_RESPONSE = "/aiplayer/tone_status_response";
        constexpr const char* TONE_ERROR = "/aiplayer/tone_error";
        constexpr const char* RMS_RESPONSE = "/aiplayer/rms_response";
        constexpr const char* CHAT_REQUEST = "/aiplayer/chat/request";
        
        // Incoming messages (from ChattyChannels)
        constexpr const char* PORT_ASSIGNMENT = "/aiplayer/port_assignment";
        constexpr const char* TRACK_UUID_ASSIGNMENT = "/aiplayer/track_uuid_assignment";
        constexpr const char* QUERY_RMS = "/aiplayer/query_rms";
        constexpr const char* START_TONE = "/aiplayer/start_tone";
        constexpr const char* STOP_TONE = "/aiplayer/stop_tone";
        constexpr const char* TONE_STATUS = "/aiplayer/tone_status";
        constexpr const char* SET_PARAMETER = "/aiplayer/set_parameter";
        constexpr const char* CHAT_RESPONSE = "/aiplayer/chat/response";
    }
    
    // Parameter IDs
    namespace Parameters {
        constexpr const char* GAIN_ID = "GAIN";
        constexpr int GAIN_VERSION = 1;
        constexpr float GAIN_MIN_DB = -60.0f;
        constexpr float GAIN_MAX_DB = 0.0f;
        constexpr float GAIN_DEFAULT_DB = 0.0f;
        constexpr float GAIN_STEP = 0.1f;
    }
    
    // File paths
    namespace Paths {
        constexpr const char* LOG_DIRECTORY = "Documents/chatty-channel/logs";
        constexpr const char* LOG_FILENAME = "AIplayer.log";
    }

} // namespace Constants
} // namespace AIplayer
