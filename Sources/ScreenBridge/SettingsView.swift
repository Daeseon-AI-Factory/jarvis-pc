//
//  SettingsView.swift
//  ScreenBridge — v0.3 환경설정 SwiftUI view
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: PrivacySettings = .shared
    @State private var showRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    privacySection
                    regionsSection
                    downloadSection
                    aboutSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 440, idealWidth: 520, minHeight: 420, idealHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("재시작 필요", isPresented: $showRestartAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Privacy mode 변경은 ScreenBridge 재시작 후 적용됩니다.\nv0.4에서 runtime swap 박을 예정.")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("환경설정")
                .font(.title2.weight(.semibold))
            Spacer()
            Text("v0.3")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.green)
                Text("Privacy Mode")
                    .font(.headline)
            }

            ForEach(PrivacyMode.allCases) { mode in
                modeRow(mode)
            }

            Text("변경 시 ScreenBridge 재시작 필요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func modeRow(_ mode: PrivacyMode) -> some View {
        Button {
            let changed = settings.mode != mode
            settings.mode = mode
            if changed { showRestartAlert = true }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: settings.mode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(settings.mode == mode ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.mode == mode ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var regionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.dashed")
                    .foregroundStyle(.orange)
                Text("민감 영역 (Layer 3)")
                    .font(.headline)
                Spacer()
                Button("편집...") {
                    RegionEditorWindow.shared.present()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            let total = settings.sensitiveRegionsAll.values.reduce(0) { $0 + $1.count }
            if total == 0 {
                Text("박힌 영역 없음 — '편집...' 박은 후 드래그로 박음.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("박힌 영역 \(total)개 — capture 시 검은 사각형으로 덮음, 외부 LLM 안 봄.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("모두 지우기") {
                    settings.sensitiveRegionsAll.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.purple)
                Text("Local Model")
                    .font(.headline)
            }
            ModelDownloadView()
                .padding(.horizontal, -12)   // ModelDownloadView 자체 padding 24
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("About")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ScreenBridge")
                    .font(.callout.weight(.semibold))
                Text("AI 추상 지시 → 화면 정확 박는 번역기 (macOS native)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⌥+Space: trigger / ⌥⌘I: Session Inspector")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
