## 2025-04-26  ·  v0.5  “Kick-drum PID probe”
**Goal**   Prove AppleScript fader control + OSC RMS feedback loop within **±0.1 dB**.  
**Scope**  AppleScriptService, OSC plumbing, stub AIplayer telemetry, basic PID controller.  
**Exit criteria**  Chat command `kick –3 dB` converges in ≤ 3 cycles; unit tests green.  
**Result**  ✅ Passed on Logic 10.8 (M1 Pro). -- Average OSC round-trip ≈ 180 ms.  

**Next → v0.6**   Generalise track↔UUID mapping and add auto-solo “follow” VU meters.

