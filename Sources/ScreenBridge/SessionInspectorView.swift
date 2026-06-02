//
//  SessionInspectorView.swift
//  ScreenBridge — v0.3 Session Inspector SwiftUI view
//

import SwiftUI

struct SessionInspectorView: View {
    @ObservedObject var state: InspectorState
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 380, idealWidth: 440, minHeight: 420, idealHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header (status + privacy mode + dispatcher)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("세션 진행 보기")
                    .font(.headline)
                Spacer()
                privacyBadge
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 8, height: 8)
                Text(phaseLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.dispatcherName)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
    }

    private var privacyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: privacyIcon)
            Text(privacyLabel)
        }
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(privacyColor.opacity(0.16))
        .foregroundStyle(privacyColor)
        .clipShape(Capsule())
    }

    private var privacyIcon: String {
        switch state.privacyMode {
        case "localOnly": return "lock.shield.fill"
        case "blocked": return "shield.slash.fill"
        default: return "cloud.fill"
        }
    }
    private var privacyLabel: String {
        switch state.privacyMode {
        case "localOnly": return "On-device"
        case "blocked": return "차단"
        default: return "Cloud"
        }
    }
    private var privacyColor: Color {
        switch state.privacyMode {
        case "localOnly": return .green
        case "blocked": return .red
        default: return .blue
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .idle: return .gray
        case .analyzing: return .orange
        case .waitingForUserClick: return .blue
        case .completed: return .green
        case .cancelled, .failed: return .red
        }
    }

    private var phaseLabel: String {
        switch state.phase {
        case .idle: return "대기 중"
        case .analyzing(let i): return "분석 중... (step \(i + 1))"
        case .waitingForUserClick(let i): return "step \(i) — 사용자 클릭 대기"
        case .completed: return "끝났어요 ✓"
        case .cancelled: return "취소됨"
        case .failed(let r): return "실패: \(r)"
        }
    }

    // MARK: - Content (instruction + steps list + cancel)

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            instructionBlock
            stepsList
            Spacer(minLength: 0)
            cancelButton
        }
        .padding(16)
    }

    @ViewBuilder
    private var instructionBlock: some View {
        if let inst = state.instruction {
            VStack(alignment: .leading, spacing: 4) {
                Text("Task")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                Text(inst)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        } else {
            Text("⌥+Space → instruction 입력 → 진행 봄")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
        }
    }

    private var stepsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(state.steps) { step in
                    StepRow(step: step)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var cancelButton: some View {
        switch state.phase {
        case .analyzing, .waitingForUserClick:
            Button(role: .destructive, action: onCancel) {
                Label("현재 세션 취소", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        default:
            EmptyView()
        }
    }
}

private struct StepRow: View {
    let step: InspectorState.StepView

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 28, height: 28)
                Text("\(step.stepNumber)")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(step.targetText)
                        .font(.callout.weight(.semibold))
                    if step.irreversible {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Text("\(String(format: "%.1f", step.elapsedSec))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(step.nextAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(step.sourceTag)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
