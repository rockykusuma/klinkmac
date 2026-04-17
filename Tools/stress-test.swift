#!/usr/bin/env swift
// Stress-test: injects keystrokes at ~150 WPM via CGEvent for 5 minutes.
// Requires Accessibility permission for the Terminal / Swift process.
// Run: chmod +x Tools/stress-test.swift && ./Tools/stress-test.swift
import CoreGraphics
import Foundation

// 150 WPM ≈ 12.5 characters/second → 80 ms per keypress (down + up).
let wpm: Double       = 150
let cps               = wpm * 5 / 60          // chars per second (avg 5 chars/word)
let intervalSec       = 1.0 / cps             // seconds between characters
let durationSec: Double = 5 * 60             // 5 minutes
let totalEvents       = Int(durationSec / intervalSec)

// A representative set of keycodes (alpha + common punctuation).
let keycodes: [UInt16] = [
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  // a–j
    10, 11, 12, 13, 14, 15, 16, 17, 18, 19, // k–t
    20, 21, 22, 23, 24, 25,                  // u–z
    49,                                       // space
    36,                                       // return
    51,                                       // backspace
]

var errorCount  = 0
var eventCount  = 0
let start       = Date()

print("Stress test: \(totalEvents) keystrokes at ~\(Int(wpm)) WPM over \(Int(durationSec / 60)) minutes.")
print("Press ^C to abort early.\n")

for i in 0..<totalEvents {
    let kc = keycodes[i % keycodes.count]

    guard let src = CGEventSource(stateID: .hidSystemState) else { errorCount += 1; continue }
    guard let down = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: true),
          let up   = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: false) else {
        errorCount += 1; continue
    }

    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    eventCount += 1

    // Sleep for the inter-keystroke interval minus the time we already spent.
    Thread.sleep(forTimeInterval: intervalSec)

    if i % 500 == 0 {
        let elapsed = Date().timeIntervalSince(start)
        let remaining = durationSec - elapsed
        print(String(format: "  %5d / %d keystrokes  elapsed %.0fs  remaining %.0fs  errors %d",
                     eventCount, totalEvents, elapsed, remaining, errorCount))
    }
}

let elapsed = Date().timeIntervalSince(start)
print(String(format: "\nDone. %d keystrokes in %.1f s. Errors: %d.", eventCount, elapsed, errorCount))
print("Check KlinkMac for audio dropouts and monitor CPU usage in Activity Monitor.")
