#!/usr/bin/env python3
import os
import sys

def update_juce_paths(file_path):
    """Update JUCE paths in the Xcode project file"""
    old_path = '/Users/nickfox137/Downloads/JUCE'
    new_path = '/Users/nickfox137/Documents/JUCE-8.0.8'
    
    # Read the file
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Count occurrences
    count = content.count(old_path)
    print(f"Found {count} occurrences of '{old_path}'")
    
    if count > 0:
        # Replace all occurrences
        updated_content = content.replace(old_path, new_path)
        
        # Write the updated content back
        with open(file_path, 'w') as f:
            f.write(updated_content)
        
        print(f"Successfully updated all {count} occurrences to '{new_path}'")
    else:
        print("No occurrences found to update")

if __name__ == "__main__":
    project_file = "/Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Builds/MacOSX/AIplayer.xcodeproj/project.pbxproj"
    
    if os.path.exists(project_file):
        update_juce_paths(project_file)
    else:
        print(f"Error: Project file not found at {project_file}")
        sys.exit(1)
