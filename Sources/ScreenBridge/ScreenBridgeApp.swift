import SwiftUI

/// menu-bar 전용 앱. main window scene 없이 (Settings로 trick) — dock에 안 보이고
/// NSStatusItem + global hotkey로만 동작. 실제 윈도우는 AppDelegate가 NSWindow로
/// 직접 띄운다 (SwiftUI WindowGroup은 menu-bar HUD 패턴에 안 맞음).
@main
struct ScreenBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // menu-bar 앱은 보일 main scene이 없다. Settings scene은 ⌘, 로만 열리는
        // 빈 placeholder (없으면 SwiftUI App이 컴파일 안 됨).
        Settings {
            EmptyView()
        }
    }
}
