# /Users/nickfox137/Documents/chatty-channel/docs/vu/vu_plan.md
# Consolidated VU Meter & Neve Console UI Plan (v0.6 and Beyond)

## 1. Overview & Goals

The primary goal was to implement a functional and visually appealing stereo VU meter component within the ChattyChannels app (v0.6), styled to evoke a vintage 1970s Neve 1073 console aesthetic.

**Key Requirements:**
- Stereo VU meters (Left/Right channels) based on a TEAC reference image.
- Positioned at the top of the app.
- Realistic VU meter ballistics (300ms attack/release).
- Peak LED indicator (activates >= 0dB, holds 1.5s).
- Display current track name below meters.
- Neve-inspired styling:
    - Wooden strip above the meters.
    - Horizontal divider below the meters.
    - Correct track label styling and positioning.
- Efficient performance and smooth animation (target 60fps).

## 2. v0.6 Implementation (2D Image-Based)

### 2.1 Architecture

- **Model:** `AudioLevel.swift` (Handles level data, dB conversion, peak detection).
- **Service:** `LevelMeterService.swift` (Manages audio levels via `ObservableObject`, handles track name, intended to connect to `OSCService`).
- **View Components:**
    - `VUMeterView.swift`: Main container for stereo meters, track label, and divider. Positioned by `ContentView`.
    - `SingleMeterView.swift`: Renders individual meter face image, handles ballistics logic.
    - `NeedleView.swift`: Renders the rotating needle overlay.
    - `PeakIndicatorView.swift`: Renders the peak LED.
    - `NeveHorizontalDividerView.swift`: Renders the metallic divider line.
    - `ContentView.swift`: Integrates the `VUMeterView` and the `WoodenStripView` (implemented as a `Rectangle` with styling).

### 2.2 Key Features & Styling

- **VU Ballistics:** Implemented using a simplified physics model (`needleRotation += (needleTarget - needleRotation) * 0.15`) targeting 300ms response. dB values (-20 to +3) mapped non-linearly to needle rotation (-45° to +45°).
- **Peak Indication:** Red circle LED appears when level >= 0dB, holds for 1.5s.
- **Track Label:** Displayed and centered below the meter pair.
- **Wooden Strip:** Implemented as a `Rectangle` in `ContentView` with a solid dark reddish-brown fill and subtle border, positioned above `VUMeterView`. Height set to 25px. A subtle grain effect is simulated using a `Canvas` overlay drawing 6 thin horizontal lines.
- **Horizontal Divider:** Implemented using `NeveHorizontalDividerView` with a metallic gradient effect, positioned below the main meter area in `VUMeterView`.
- **Meter Positioning:** Meters are positioned towards the right side of the `VUMeterView` container.

### 2.3 Status (as of end of v0.6 UI Fixes)

- **Functionality:** VU meter components (needle, peak LED, ballistics) are implemented. Uses **simulated** audio data for v0.6.
- **Layout:** Wooden strip, VU meters, track label, and divider are positioned correctly. Meter size adjusted to prevent cutoff.
- **Styling:** Wooden strip has a matte reddish-brown appearance with subtle grain. Divider has a metallic look. Track label styled appropriately.
- **Resolved Issues:** Initial problems with wooden strip visibility (due to layout structure, Z-index, and brace issues) have been fixed.

## 3. Testing Plan Summary

- **Unit Tests:** Cover `AudioLevel`, `LevelMeterService`, `VUMeterView` (dB mapping, ballistics).
- **Integration Tests:** Verify interactions between components.
- **UI Tests:** Validate layout (height constraints, positioning), visibility, and stability within the app.
- **Performance Tests:** Ensure smooth animation and acceptable resource usage.
- **Success Criteria:** All tests passing, accurate display, smooth animation, meets layout requirements.

## 4. Future Plans

### 4.1 Immediate Next Steps (Post v0.6)

- **OSC Integration:** Connect `LevelMeterService` to `OSCService` to process real-time audio level data from Logic Pro. Requires parsing specific OSC messages.
- **Track Mapping:** Integrate with a track mapping service to display accurate track names dynamically.

### 4.2 Longer-Term Enhancement (3D SceneKit Implementation)

- **Goal:** Replace the 2D image-based meter with a photorealistic 3D model using SceneKit.
- **Approach:**
    - Model TEAC meter components (housing, face, needle, glass).
    - Apply PBR materials and textures (metal, paper grain, glass).
    - Implement physics-based needle animation (SCNPhysicsBody, spring joint, damping).
    - Integrate SceneKit view into SwiftUI using `UIViewRepresentable`.
    - Optimize rendering (LOD, baked lighting, Metal shaders).
- **Detailed Plan:** A separate, detailed plan exists outlining research, modeling, texturing, animation, integration, testing, and risk assessment for the 3D version.