#!/bin/bash
# Test script to find track names using AXLayoutItem - JavaScript version
# More robust than AppleScript for UI traversal

echo "=== Searching for AXLayoutItem elements with track names ==="
echo

osascript -l JavaScript <<'EOF'
function findTrackNamesInLayoutItems() {
    const sf = Application("System Events");
    const logic = sf.processes["Logic Pro"];
    
    try {
        const window = logic.windows[0];
        const allElements = window.entireContents();
        
        let trackLayoutItems = [];
        let allLayoutItems = [];
        
        // Find all AXLayoutItem elements
        for (let el of allElements) {
            try {
                if (el.role() === "AXLayoutItem") {
                    allLayoutItems.push(el);
                    
                    // Check description for track pattern
                    try {
                        const desc = el.attributes["AXDescription"].value();
                        // Pattern: "Track N \"name\"" or just contains "Track"
                        if (desc.includes("Track")) {
                            trackLayoutItems.push({
                                element: el,
                                description: desc
                            });
                        }
                    } catch (e) {
                        // Try other attributes if description fails
                        try {
                            const value = el.attributes["AXValue"].value();
                            if (value && value.includes("Track")) {
                                trackLayoutItems.push({
                                    element: el,
                                    value: value
                                });
                            }
                        } catch (e2) {}
                    }
                }
            } catch (e) {
                // Skip elements that throw errors
            }
        }
        
        let output = `Total AXLayoutItem elements found: ${allLayoutItems.length}\n`;
        output += `Track-related AXLayoutItem elements: ${trackLayoutItems.length}\n\n`;
        
        if (trackLayoutItems.length > 0) {
            output += "Track names found:\n";
            for (let i = 0; i < trackLayoutItems.length; i++) {
                const item = trackLayoutItems[i];
                if (item.description) {
                    output += `  ${i + 1}. ${item.description}\n`;
                } else if (item.value) {
                    output += `  ${i + 1}. Value: ${item.value}\n`;
                }
            }
        } else if (allLayoutItems.length > 0) {
            output += "\nNo track names found, but here are the first few AXLayoutItem descriptions:\n";
            for (let i = 0; i < Math.min(10, allLayoutItems.length); i++) {
                try {
                    const desc = allLayoutItems[i].attributes["AXDescription"].value();
                    output += `  ${i + 1}. ${desc}\n`;
                } catch (e) {
                    output += `  ${i + 1}. [No description available]\n`;
                }
            }
        }
        
        // Also try to find parent containers of AXLayoutItems
        if (trackLayoutItems.length === 0) {
            output += "\nLooking for parent containers of AXLayoutItems...\n";
            for (let layoutItem of allLayoutItems.slice(0, 5)) {
                try {
                    const parent = layoutItem.attributes["AXParent"].value();
                    const parentRole = parent.role();
                    const parentDesc = parent.attributes["AXDescription"].value();
                    output += `  Parent: [${parentRole}] "${parentDesc}"\n`;
                } catch (e) {}
            }
        }
        
        return output;
    } catch (e) {
        return "Error: " + e.toString();
    }
}

// Also search for any element containing track names, not just AXLayoutItem
function findAnyTrackNames() {
    const sf = Application("System Events");
    const logic = sf.processes["Logic Pro"];
    
    try {
        const window = logic.windows[0];
        const allElements = window.entireContents();
        
        let trackElements = [];
        
        // Pattern to match "Track N \"name\"" format
        const trackPattern = /Track\s+\d+\s+"[^"]+"/;
        
        for (let el of allElements) {
            try {
                // Check all text attributes
                const attrs = ["AXDescription", "AXValue", "AXTitle", "AXHelp"];
                
                for (let attr of attrs) {
                    try {
                        const value = el.attributes[attr].value();
                        if (value && (trackPattern.test(value) || value.includes("kick"))) {
                            trackElements.push({
                                element: el,
                                role: el.role(),
                                attribute: attr,
                                value: value
                            });
                        }
                    } catch (e) {}
                }
            } catch (e) {}
        }
        
        let output = "\n\nSearching all elements for track name patterns:\n";
        output += `Found ${trackElements.length} elements with track-like names:\n`;
        
        // Remove duplicates and show unique values
        const seen = new Set();
        for (let item of trackElements) {
            if (!seen.has(item.value)) {
                seen.add(item.value);
                output += `  [${item.role}] ${item.attribute}: "${item.value}"\n`;
            }
        }
        
        return output;
    } catch (e) {
        return "\nError in general search: " + e.toString();
    }
}

// Run both searches
let result = findTrackNamesInLayoutItems();
result += findAnyTrackNames();
result;
EOF

echo
echo "=== Search complete ==="
