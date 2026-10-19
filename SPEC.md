# SwitchClatter — specification

**Tagline:** Plays satisfying mechanical keyboard click sounds as you type on any Mac keyboard.

**Category:** Audio

**Inspired by (paid):** Klack ($4.99 one-time)

**Frameworks:** SwiftUI, AppKit, AVFoundation, CoreGraphics, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Klack is a menu bar app that plays mechanical switch sounds whenever you press a key on any keyboard, with several switch types, volume and spatial effects. It is sold on the Mac App Store for 4.99 dollars one-time, after launching at 3.99, and was covered by 9to5Mac, Creative Bloq, MacSales and Podfeet, which shows strong enthusiasm for such a small utility. Our clean-room SwitchClatter implements the same core experience with sounds we synthesize ourselves, so there are no audio assets to license.

Feature set: global key listening, a down click sound and a softer release sound, three synthesized switch profiles (Linear thock, Clicky, Soft tactile) generated at launch from shaped noise bursts and decaying sine bodies, separate sounds for space, return, delete and modifier keys, a volume slider, pitch variation randomization so rapid typing feels natural, optional stereo panning based on the key position on the keyboard, and a mute while a screen is locked or when a specific app is frontmost. About 300 to 450 lines.

UI spec: a MenuBarExtra with a keyboard icon. The menu shows an on and off toggle, profile picker, and volume slider, plus Settings and Quit. Settings window fields: profile, volume, pitch variance amount, stereo spread toggle, mute in these apps list with an add button that picks from running apps, play release sounds toggle, launch at login. Empty state: before permission is granted, the menu shows a prominent button that explains the need for Input Monitoring and opens the correct privacy pane. The menu bar icon dims while permission is missing.

Technical approach: listen for key events using a CGEventTap with the listen-only option on key down and key up events, which requires the Input Monitoring permission. Check with CGPreflightListenEventAccess and request with CGRequestListenEventAccess, then poll briefly after the user returns from Settings to start the tap. Never inspect or store key characters, only the key code, to keep this clearly privacy safe, and state this in the About section. Build sounds with AVAudioEngine: create PCM buffers procedurally for each profile and key class, attach a pool of AVAudioPlayerNode instances through an AVAudioMixerNode, and schedule a buffer on a free player node per key event so overlapping sounds work. Vary pitch with an AVAudioUnitVarispeed or by choosing among several pre-generated variants. Pan with the node pan property. Keep latency low by using a small buffer size and starting the engine at launch. Persist settings with AppStorage and use SMAppService for launch at login. Watch for NSWorkspace frontmost application changes to apply the mute list.

Edge cases: the event tap can be disabled by the system on timeout, so handle the tapDisabledByTimeout event by re-enabling it. Ignore key repeat events so holding a key does not spam sounds, using the autorepeat field. Handle audio device changes, since AVAudioEngine stops on configuration change, by restarting it on the configuration change notification. Secure text fields such as password inputs do not deliver events to taps, which is acceptable and good. Avoid playing sounds for pure modifier changes unless the option is on. If the engine fails to start, show a clear error row in the menu.
