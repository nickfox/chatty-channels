# Chatty Channels — Risk‑Driven Engineering Plan

> **Purpose**  This living document explains *what we will build first* and *why*, based on a strict "kill the biggest unknowns early" principle.  All lower‑risk polish (UI candy, extra AI personas, etc.) waits until the pillars below are proved.

---

## 1 · System snapshot

| Layer | Role | Tech |
|-------|------|------|
|AIplayer (AU) | Per‑track **sensor** (FFT + RMS) | JUCE 7, C++, oscpack |
|Control Room app | **Producer / controller / UI** | Swift 5.10 + SwiftUI, OSC, AppleScript, virtual MIDI |
|Remote LLM | Brains / conversation | OpenAI o4-mini (current) |
|Logic Pro | Audio host | AppleScript target |

**Invariant**  Plugins never touch Logic parameters directly; Control Room issues AppleScript/MIDI, then uses plugin telemetry to verify (PID).

---

## 2 · High‑risk matrix

| Rank | Risk area | Reason it can block project | Mitigation task IDs | Status |
|------|-----------|-----------------------------|--------------------|--------|
| H1 | AppleScript mix control | Underdocumented; may fail during playback or on internationalised Logic installs | T‑01, T‑02 | ✅ Resolved |
| H2 | Track UUID ↔ track‑name mapping | If wrong, every command acts on the wrong fader | T‑03 | ✅ Basic mapping implemented |
| H3 | OSC latency / loss | PID loop stability & UI responsiveness | T‑04 … T‑06 | ✅ Optimized (182ms RTT) |
| H4 | PID convergence maths | Needs <3 steps, <±0.3 dB | T‑07 | ✅ Converges in 2 steps, ±0.12 dB |
| H5 | Telemetry scaling (FFT) | 100 tracks × FFT could starve CPU/UDP | T‑08, T‑09 | Planned for v0.8 |
| H6 | LLM structured replies | JSON schema violations break automation | T‑10 | Planned for v0.9 |
| H7 | Cross‑track masking algorithm | Psycho‑acoustic tuning unknown | T‑11 | Planned for v1.0 |
| L* | UI polish (VU, heat‑map, etc.) | Nice‑to‑have, not project‑threatening | T‑20+ | Planned for v0.6+ |

---

## 3 · Ordered backlog (only first ten shown)

| ID | Title | Dep | Risk | Definition of Done | Status |
|----|-------|-----|------|-------------------|--------|
| T‑01 | AppleScriptService → basic `get/set volume` | – | H1 | Function returns current dB, sets ±3 dB, throws error codes, unit‑tested with mocked `osascript`. | ✅ Complete |
| T‑02 | Playback‑safe AS executor | T‑01 | H1 | Executes while Logic is playing; RTT logged <250 ms. | ✅ Complete |
| T‑03 | Handshake + mapping UI | T‑02 | H2 | Plugins send UUID; Swift fetches track names; user confirm list; stored plist. | ✅ Basic mapping done |
| T‑04 | OSCService low‑latency path | – | H3 | End‑to‑end RTT <200 ms with 60 mock senders. | ✅ Complete (182ms) |
| T‑05 | UDP retry & order guarantees | T‑04 | H3 | Duplicate suppression, sequence ID, resend after 1 lost packet. | Planned for v0.7 |
| T‑06 | Telemetry ring‑buffer | T‑04 | H3 | Stores last 80 packets per track with ≤0.5 MB RAM. | ✅ Complete |
| T‑07 | Simple P‑controller | T‑03,T‑04 | H4 | Converges on –3 dB target in max 3 steps in unit test. | ✅ Complete (2 steps) |
| T‑08 | Lazy FFT compute thread | T‑04 | H5 | Average CPU <1 % per plugin at 44.1 kHz, 128 buffer. | Planned for v0.8 |
| T‑09 | Band‑energy telemetry v1.1 | T‑08 | H5 | 4‑band payload <32 B, loss <0.1 %. | Planned for v0.8 |
| T‑10 | LLM JSON schema validator | – | H6 | Invalid payload triggers retry with "STRICT" system prompt. | Planned for v0.9 |

*Complete backlog at bottom of file; IDs continue T‑11…*

---

## 4 · Coding & QA conventions

* **Test‑first** – Every high‑risk task ships with XCTests / C++ Catch2 tests.
* **Logging** – `os_log` (Swift) & `juce::Logger` (C++) with `subsystem = "chatty"`.
* **CI** – GitHub Actions: build plugins, run unit‑tests, run AS smoke test via headless Logic stub.
* **Doc** – Inline DocC (Swift) + Doxygen (C++).  README badges show coverage.

---

## 5 · Current sprint focus  (2024‑05‑12 → v0.6)

T‑03 (enhanced track mapping), UI-VU-01 (auto-solo VU meters) – full multi-track monitoring and selection.

---

## 6 · Milestone ladder (snapshot)
*Only top-level goals shown – detailed scope captured in* **iterations.md**.

| Version | Headline goal | Key new items | Status |
|---------|---------------|---------------|--------|
| **v0.5** *(DEV)* | Kick‑track PID loop proven | T‑01…T‑07 | ✅ Completed Apr 27, 2025 |
| **v0.6** | Track‑UUID mapping, auto‑follow VU meters | T‑03, T‑08, UI‑VU‑01 | Next sprint |
| **v0.7** | Multi‑track OSC stress‑test (64 ch), retry logic hardened | T‑05, T‑06, Net‑Bench‑02 | Planned |
| **v0.8** | Telemetry v1.1 (band‑energy) + Lazy FFT | T‑08, T‑09 | Planned |
| **v0.9** | LLM JSON schema enforcement & prompt templates | T‑10, AI‑Prompt‑02 | Planned |
| **v1.0** *(ALPHA)* | Full NVFE EQ/Compression cycle on demo project | Backlog T‑11…T‑18 | Planned |

> **Note**  First milestone successfully completed. Planning v0.6 for May 12, 2025.

---

## 7 · Plan maintenance protocol
1. **After every merged PR** that closes a `T‑nn` issue, update the Risk matrix (section 2) and tick the backlog item.
2. **If a new blocker emerges**, insert it in section 2 with an `H` rank, then create a next available `T‑id` in the backlog.
3. **Monthly pruning** – archive completed low‑risk polish tasks to `/docs/archive/backlog‑done.md`.
4. **CI gate** – fail build if `plan.md` or `iterations.md` are edited but risk matrix/backlog counts don't reconcile (`./Scripts/check‑plan.py`).

---

*(End of document)*
