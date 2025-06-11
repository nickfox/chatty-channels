#!/bin/bash
# Clear the corrupted database
rm -f "$HOME/Library/Application Support/ChattyChannels/track_mappings.db"
echo "Database cleared"

# Also clear any cached OSC data
echo "Restart the app to reload track mappings"
