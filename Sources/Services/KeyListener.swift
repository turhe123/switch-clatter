import CoreGraphics
import Foundation

/// A single key transition. Deliberately carries only the hardware key code — never characters.
struct KeyEventInfo {
    let keyCode: Int64
    let isDown: Bool
    let isModifier: Bool
}

/// Owns a listen-only `CGEventTap` for key down/up and modifier changes and forwards
/// privacy-safe `KeyEventInfo` values. Requires the Input Monitoring permission.
final class KeyListener {
    var onKey: ((KeyEventInfo) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var heldModifiers = Set<Int64>()

    private static let capsLockCode: Int64 = 57
    private static let modifierMasks: [Int64: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand,
        56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate,
        59: .maskControl, 62: .maskControl,
        63: .maskSecondaryFn,
    ]

    var isRunning: Bool { tap != nil }

    /// Creates and enables the tap. Returns `false` when the system refuses (e.g. no permission).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                Unmanaged<KeyListener>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        source = newSource
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        heldModifiers.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disables slow taps; simply turn ours back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            emit(code(of: event), down: true, modifier: false)
        case .keyUp:
            emit(code(of: event), down: false, modifier: false)
        case .flagsChanged:
            let keyCode = code(of: event)
            let down: Bool
            if keyCode == Self.capsLockCode {
                down = true
            } else if let mask = Self.modifierMasks[keyCode], !event.flags.contains(mask) {
                down = false
                heldModifiers.remove(keyCode)
            } else if heldModifiers.contains(keyCode) {
                down = false
                heldModifiers.remove(keyCode)
            } else {
                down = true
                heldModifiers.insert(keyCode)
            }
            emit(keyCode, down: down, modifier: true)
        default:
            break
        }
    }

    private func code(of event: CGEvent) -> Int64 {
        event.getIntegerValueField(.keyboardEventKeycode)
    }

    private func emit(_ keyCode: Int64, down: Bool, modifier: Bool) {
        onKey?(KeyEventInfo(keyCode: keyCode, isDown: down, isModifier: modifier))
    }
}

/// Maps ANSI key codes to a horizontal position (0 = far left, 1 = far right) for stereo panning.
enum KeyLayout {
    private static let rows: [[Int64]] = [
        [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51],
        [48, 12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
        [57, 0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 36],
        [56, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 60],
        [63, 59, 58, 55, 49, 54, 61, 123, 125, 124],
    ]

    private static let positions: [Int64: Double] = {
        var map: [Int64: Double] = [:]
        for row in rows {
            for (index, code) in row.enumerated() where map[code] == nil {
                map[code] = Double(index) / Double(max(row.count - 1, 1))
            }
        }
        map[49] = 0.5 // space bar sits in the middle
        map[62] = 1.0
        return map
    }()

    static func position(for keyCode: Int64) -> Double {
        positions[keyCode] ?? 0.5
    }
}
