import Carbon.HIToolbox
import AppKit
import OSLog

/// Carbon RegisterEventHotKey wrapper. Carbon은 deprecated이지만 global hotkey엔
/// 여전히 표준 + 의존성 0 (MASShortcut 등 안 끌어옴). ⌥+Space 고정 (v0.2에 설정 UI).
///
/// Carbon 콜백은 C function pointer라 Swift closure를 직접 못 쓴다. Unmanaged로
/// self 포인터를 userData에 넘겨 콜백 안에서 복원하는 표준 패턴.
@MainActor
final class HotKeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                // 콜백은 main run loop에서 발화. onTrigger도 main.
                Task { @MainActor in manager.onTrigger?() }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )
        if installStatus != noErr {
            Log.hotkey.error("InstallEventHandler failed: OSStatus=\(installStatus, privacy: .public)")
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("SCRB"), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus == noErr {
            Log.hotkey.info("registered ⌥+Space")
        } else {
            Log.hotkey.error("RegisterEventHotKey failed: OSStatus=\(registerStatus, privacy: .public) — 다른 앱(Alfred/Raycast/Klack/한영 전환 등)이 ⌥+Space 점유 가능")
        }
    }

    /// 명시적 정리. HotKeyManager는 앱 lifetime 내내 살아있어 보통 안 불림 —
    /// process 종료 시 OS가 global hotkey 자동 해제. deinit에서 @MainActor
    /// property 접근이 Swift 6 strict concurrency에 막혀서 별도 method로.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

/// 'SCRB' 같은 4글자 → OSType (FourCharCode). Carbon signature용.
private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + FourCharCode(scalar.value & 0xFF)
    }
    return result
}
