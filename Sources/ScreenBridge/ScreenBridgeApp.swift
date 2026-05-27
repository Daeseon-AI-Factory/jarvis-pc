import SwiftUI

/// v0.1 Phase 0.2 Swift scaffold — 단순 SwiftUI App. dev `swift run`으로
/// 띄움. 다음 phase에서:
///   - NSApplicationDelegateAdaptor로 AppDelegate 연결
///   - LSUIElement=true (menu bar only, dock 숨김) — Info.plist 추가 필요
///   - NSStatusItem tray
///   - NSWindow native HUD overlay (transparent + click-through +
///     collectionBehavior=[.moveToActiveSpace])
///   - Carbon RegisterEventHotKey global ⌥+Space
///
/// 이 phase는 *빌드와 실행만 가능*이 목표. WindowGroup가 dock에 보이는
/// 일반 윈도우 만들고 종료하면 앱 끝남.
@main
struct ScreenBridgeApp: App {
    var body: some Scene {
        WindowGroup("ScreenBridge") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("ScreenBridge")
                .font(.title)
                .fontWeight(.semibold)
            Text("v0.1 (Swift native) — Phase 0.2 scaffold")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("다음 단계: AppDelegate + NSStatusItem + global hotkey")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 480, height: 200)
    }
}

#Preview {
    ContentView()
}
