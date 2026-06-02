//
//  ModelDownloadView.swift
//  ScreenBridge — v0.3 SwiftUI download progress view
//

import SwiftUI

struct ModelDownloadView: View {
    @ObservedObject var progress: ModelDownloadProgress = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            body_
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 240, idealHeight: 280)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.title)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("보안 모드 준비 중")
                    .font(.title2.weight(.semibold))
                Text("Qwen2.5-VL-3B — Mac에서만 작동")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var body_: some View {
        switch progress.status {
        case .idle:
            idleView
        case .downloading(let fraction):
            downloadingView(fraction)
        case .finished:
            finishedView
        case .failed(let reason):
            failedView(reason)
        }
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("아직 다운로드 시작 안 했어요.")
                .font(.callout)
            Text("⌥+Space로 첫 호출 시 자동 다운로드 — 한 번만, 약 2GB.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func downloadingView(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)

            HStack {
                Text("\(Int(fraction * 100))%")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                Spacer()
                if let eta = etaText {
                    Text(eta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("이 화면 닫아도 다운로드 계속됩니다.\n다 받은 후 ScreenBridge가 100% Mac에서만 작동.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var finishedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("다운로드 완료 ✓")
                    .font(.headline)
                Text("이제 ⌥+Space 누르면 Mac 안에서만 작동해요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failedView(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("다운로드 실패")
                    .font(.headline)
            }
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text("⌥+Space 다시 누르면 재시도. 또는 환경설정에서 Cloud 모드로.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var etaText: String? {
        guard let started = progress.startedAt else { return nil }
        guard case .downloading(let fraction) = progress.status, fraction > 0.02 else { return nil }
        let elapsed = Date().timeIntervalSince(started)
        let totalEstimate = elapsed / fraction
        let remaining = max(0, totalEstimate - elapsed)
        let mins = Int(remaining / 60)
        let secs = Int(remaining.truncatingRemainder(dividingBy: 60))
        return "약 \(mins)분 \(secs)초 남음"
    }
}
