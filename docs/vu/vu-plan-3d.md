# 3D TEAC VU Meter Implementation Plan

## 1. Project Overview

**Goal:** Create a photorealistic 3D TEAC VU meter using SceneKit that will dynamically display audio levels in the Control Room app.

**Success Criteria:**
- Visually accurate representation of the vintage TEAC VU meter
- Realistic materials, textures, and lighting
- Physics-accurate needle movement with proper ballistics
- Smooth performance with minimal resource usage
- Integration with OSC audio level data

## 2. Technical Approach

### 2.1 Technology Stack
- **Primary Framework:** SceneKit
- **Support Frameworks:** 
  - Metal for additional rendering capabilities
  - Core Animation for transitions
  - Swift/SwiftUI for integration

### 2.2 Implementation Strategy
1. **3D Modeling Phase:** Create accurate 3D model of the TEAC meter
2. **Materials & Textures:** Apply physically-based rendering (PBR) materials
3. **Animation System:** Implement physics-based needle movement
4. **SwiftUI Integration:** Create framework for embedding in Control Room app

## 3. Detailed Task Breakdown

### Phase 1: Research & Analysis (1 week)
| Task ID | Description | Details |
|---------|-------------|---------|
| R-01 | TEAC Meter Measurements | Determine precise dimensions and proportions of the meter |
| R-02 | Material Analysis | Identify exact textures and material properties |
| R-03 | VU Meter Ballistics | Research standard VU meter attack/release times |
| R-04 | Performance Benchmarking | Establish baseline performance targets |

### Phase 2: 3D Modeling (2 weeks)
| Task ID | Description | Details |
|---------|-------------|---------|
| M-01 | Housing Model | Create detailed model of the meter case |
| M-02 | Face/Dial Design | Model the meter face with precise scale markings |
| M-03 | Needle Assembly | Create needle with proper pivot point and mass |
| M-04 | Glass Cover | Model the glass with appropriate thickness and edge bevels |
| M-05 | Complete Model Assembly | Combine all components with proper hierarchy |

### Phase 3: Materials & Textures (1.5 weeks)
| Task ID | Description | Details |
|---------|-------------|---------|
| T-01 | UV Mapping | Create proper UV layout for all components |
| T-02 | Texture Creation | Generate high-res textures for meter face and markings |
| T-03 | Metal Material Setup | Configure PBR materials for housing |
| T-04 | Glass Material | Create physically accurate glass with proper refraction |
| T-05 | Material Optimization | Ensure efficient rendering while maintaining quality |

### Phase 4: Animation System (2 weeks)
| Task ID | Description | Details |
|---------|-------------|---------|
| A-01 | Needle Physics | Implement mass/inertia properties for needle |
| A-02 | Spring Dynamics | Create proper spring and damping system |
| A-03 | Response Curve | Implement dB to rotation conversion with VU ballistics |
| A-04 | Calibration | Fine-tune needle animation to match real VU meters |
| A-05 | Performance Optimization | Ensure animations run efficiently |

### Phase 5: SceneKit Integration (1.5 weeks)
| Task ID | Description | Details |
|---------|-------------|---------|
| S-01 | Scene Setup | Configure camera, lighting, and environment |
| S-02 | Rendering Pipeline | Configure Metal renderer for optimal quality |
| S-03 | Node Management | Implement efficient node hierarchy |
| S-04 | Level Data Binding | Create system to feed audio level data to model |
| S-05 | Performance Testing | Benchmark and optimize rendering |

### Phase 6: SwiftUI Component (1 week)
| Task ID | Description | Details |
|---------|-------------|---------|
| U-01 | UIViewRepresentable Wrapper | Create SwiftUI wrapper for SceneKit view |
| U-02 | Property Bindings | Implement bindings for level data |
| U-03 | Control API | Design simple API for controlling the meter |
| U-04 | Stereo Configuration | Setup for dual meter stereo display |
| U-05 | Responsive Layout | Ensure proper scaling on different devices |

### Phase 7: OSC Integration & Tracking UI (1 week)
| Task ID | Description | Details |
|---------|-------------|---------|
| O-01 | OSC Data Pipeline | Connect OSC level data to meter animation |
| O-02 | Track Switching | Implement logic for changing monitored track |
| O-03 | Track Label UI | Create dynamic track label display |
| O-04 | Smooth Transitions | Add animations for track switching |
| O-05 | Final Integration | Connect all components into Control Room app |

## 4. Technical Implementation Details

### 4.1 SceneKit Scene Structure
```
rootNode
├── cameraNode
├── lightNodes
│   ├── mainLight
│   ├── fillLight
│   └── rimLight
├── meterNode
│   ├── housingNode
│   ├── faceNode
│   ├── needleNode (animated)
│   ├── glassNode
│   └── peakIndicatorNode (animated)
└── environmentNode
```

### 4.2 Needle Physics Model
The needle will use SCNPhysicsBody with:
- Custom inertia tensor
- Spring joint for proper VU ballistics
- Damping coefficient matching analog VU meters
- Physical constraints for movement range

### 4.3 Material Specifications
- **Housing:** Metal material with roughness map for brushed finish
- **Face:** Diffuse texture with subtle paper grain
- **Needle:** Metallic material with high specular component
- **Glass:** Physically-based glass with subtle smudges and reflections

### 4.4 SwiftUI Integration Approach
```swift
struct VUMeterView: View {
    @Binding var leftLevel: Float
    @Binding var rightLevel: Float
    @Binding var currentTrack: String
    
    var body: some View {
        VStack {
            HStack {
                // Left channel meter
                TEACVUMeter(level: $leftLevel, channel: .left)
                
                // Right channel meter
                TEACVUMeter(level: $rightLevel, channel: .right)
            }
            
            // Track label
            Text(currentTrack)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.9, opacity: 0.5))
                )
        }
    }
}
```

### 4.5 Core Performance Optimizations
- Use LOD (Level of Detail) for distant viewing
- Bake lighting where possible
- Use Metal shader functions for needle animation
- Implement occlusion culling
- Apply texture compression where appropriate

## 5. Development Schedule

| Week | Focus | Key Deliverables |
|------|-------|------------------|
| 1 | Research & Planning | Detailed specifications, Reference materials |
| 2-3 | 3D Modeling | Complete 3D model of TEAC VU meter |
| 4-5 | Materials & Animation | Physically accurate materials, Needle physics |
| 6-7 | SceneKit Integration | Functional SceneKit implementation |
| 8 | SwiftUI Component | SwiftUI wrapper with data binding |
| 9 | OSC Integration | Full integration with audio level data |
| 10 | Testing & Optimization | Performance tuning, Bug fixes |

## 6. Development Process

### 6.1 Iteration Strategy
Develop the VU meter in incremental steps:
1. Static model with basic materials
2. Basic needle animation
3. Full physics implementation
4. Material refinement
5. Integration with Control Room

### 6.2 Testing Approach
- **Visual Testing:** Compare against reference photos
- **Physics Testing:** Verify against known VU meter ballistics
- **Performance Testing:** Benchmark on target devices
- **Integration Testing:** Verify OSC data flow
- **Stress Testing:** Test with rapid level changes

### 6.3 Quality Standards
- Needle animation must appear physically authentic
- Materials must accurately represent vintage TEAC aesthetics
- Frame rate must remain above 60 FPS on target hardware
- Memory usage should not exceed 50MB per meter instance

## 7. Tools & Assets Required

### 7.1 Software
- 3D modeling software (Blender or Cinema 4D)
- Texture creation software (Substance Painter or Photoshop)
- Reference photo editing software

### 7.2 Assets to Create
- High-resolution textures for meter face
- Normal maps for housing details
- Reflection maps for materials
- Environment map for realistic reflections

### 7.3 Reference Materials
- Additional TEAC VU meter photos from different angles
- VU meter technical specifications
- Audio engineering documentation on VU ballistics

## 8. Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Performance issues on older devices | High | Medium | Progressive enhancement, LOD system |
| Physically inaccurate needle animation | Medium | Medium | Research proper VU meter ballistics, extensive testing |
| Visual quality compromises | Medium | Low | Invest in high-quality textures and materials |
| Integration challenges with existing app | Medium | Medium | Clear API design, encapsulation |
| Development time exceeds estimates | Medium | Medium | Focus on core functionality first, add refinements later |

## 9. Implementation Stages

### Stage 1: Proof of Concept
Implement basic 3D meter with simplified materials and animation to validate the approach.

### Stage 2: Core Functionality
Develop the complete model with proper physics but simplified materials.

### Stage 3: Visual Refinement
Improve materials, lighting, and rendering quality.

### Stage 4: Integration
Connect to OSC data and integrate with the Control Room app.

### Stage 5: Polish & Optimization
Fine-tune performance, add refinements and final visual touches.

## 10. Success Evaluation Criteria

1. **Visual Accuracy:** Side-by-side comparison with reference photo shows minimal differences
2. **Animation Quality:** Needle movement matches real VU meter ballistics in blind testing
3. **Performance:** Maintains 60+ FPS on target hardware
4. **Integration:** Seamlessly connects with OSC data pipeline
5. **User Feedback:** Positive response from audio professionals on realism
