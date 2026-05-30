//
//  AXService.swift
//  ScreenBridge — Phase 6.2
//
//  macOS Accessibility API wrapper. NSWorkspace.runningApplications 순회 + AX tree walk.
//  Swift 6 strict concurrency: kAXRoleAttribute 등 extern var 거부 → string literal 대체
//  (Phase 3.1 verify fix lesson 동일 패턴).
//
//  화이트리스트 roles: clickable + visible elements. Dock 아이콘 (AXDockItem) 포함.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

protocol AXService: Sendable {
    func queryAllElements() async throws -> [AXElement]
}

enum AXError: Error, Sendable {
    case permissionDenied
    case queryFailed(String)
}

struct LiveAXService: AXService {

    /// AX attribute keys — Swift 6 strict concurrency가 extern var 거부 → string literal.
    /// Apple HIServices/AXUIElement.h의 const string과 동일.
    private static let roleAttr = "AXRole"
    private static let titleAttr = "AXTitle"
    private static let descriptionAttr = "AXDescription"
    private static let valueAttr = "AXValue"
    private static let positionAttr = "AXPosition"
    private static let sizeAttr = "AXSize"
    private static let childrenAttr = "AXChildren"

    /// Clickable + visible roles. 화면에 박스 표시할 가치 있는 element만.
    /// Dock 아이콘 (AXDockItem)이 핵심 — Slack 같은 case 풀음.
    private static let clickableRoles: Set<String> = [
        "AXButton",
        "AXLink",
        "AXMenuItem",
        "AXMenuButton",
        "AXMenuBarItem",
        "AXDockItem",            // ★ Dock 아이콘 — icon-only UI 핵심
        "AXImage",
        "AXStaticText",
        "AXTextField",
        "AXTextArea",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXTab",
        "AXCell",
        "AXOutlineCell",         // VS Code sidebar 항목
        "AXRow",
    ]

    private static let maxDepth = 8

    func queryAllElements() async throws -> [AXElement] {
        guard Permissions.hasAccessibility() else {
            Log.dispatcher.notice("[ax] no Accessibility permission — skipping AX matcher")
            throw AXError.permissionDenied
        }

        // Background thread — AX API는 sync, 일부 호출 느림.
        return try await Task(priority: .userInitiated) {
            try Task.checkCancellation()
            return Self.queryAllSync()
        }.value
    }

    @MainActor
    private static func runningAppsSnapshot() -> [(pid: pid_t, name: String?)] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                // 일반 앱 + Dock 자체 (Dock이 모든 아이콘 가짐)
                app.activationPolicy == .regular || app.bundleIdentifier == "com.apple.dock"
            }
            .map { ($0.processIdentifier, $0.localizedName) }
    }

    private static func queryAllSync() -> [AXElement] {
        // NSWorkspace는 main thread 권장 — sync DispatchQueue로 hop.
        let apps: [(pid: pid_t, name: String?)] = DispatchQueue.main.sync {
            runningAppsSnapshotMainOnly()
        }

        var elements: [AXElement] = []
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.pid)
            walkTree(element: appElement, appName: app.name, depth: 0, results: &elements)
        }
        // Dock items 명시 log — 디버그 시 "Chrome이 Dock에 있나" 즉시 확인 가능.
        let dockItems = elements.filter { $0.role == "AXDockItem" }
        let dockTexts = dockItems.map { $0.text }.joined(separator: ", ")
        Log.dispatcher.info(
            "[ax] queried \(elements.count, privacy: .public) elements from \(apps.count, privacy: .public) apps · dock=[\(dockTexts, privacy: .public)]"
        )
        return elements
    }

    /// `runningAppsSnapshot`을 main에서 호출하기 위한 thin wrapper (nonisolated 호출 위해).
    nonisolated private static func runningAppsSnapshotMainOnly() -> [(pid: pid_t, name: String?)] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular || app.bundleIdentifier == "com.apple.dock"
            }
            .map { ($0.processIdentifier, $0.localizedName) }
    }

    private static func walkTree(
        element: AXUIElement,
        appName: String?,
        depth: Int,
        results: inout [AXElement]
    ) {
        guard depth < maxDepth else { return }

        // role 추출
        let role = stringAttribute(element, attr: roleAttr) ?? ""

        if clickableRoles.contains(role) {
            // text 합본: title + description + value
            let title = stringAttribute(element, attr: titleAttr) ?? ""
            let description = stringAttribute(element, attr: descriptionAttr) ?? ""
            let value = stringAttribute(element, attr: valueAttr) ?? ""
            let combinedText = [title, description, value]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // position + size
            let position = pointAttribute(element, attr: positionAttr) ?? .zero
            let size = sizeAttribute(element, attr: sizeAttr) ?? .zero

            if !combinedText.isEmpty, size.width > 0, size.height > 0 {
                results.append(AXElement(
                    text: combinedText,
                    rectInLogicalPt: CGRect(origin: position, size: size),
                    role: role,
                    appName: appName
                ))
            }
        }

        // 자식 재귀
        var childrenRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element, childrenAttr as CFString, &childrenRef
        )
        guard status == .success, let children = childrenRef as? [AXUIElement] else {
            return
        }
        for child in children {
            walkTree(element: child, appName: appName, depth: depth + 1, results: &results)
        }
    }

    // MARK: - AX attribute extractors

    private static func stringAttribute(_ element: AXUIElement, attr: String) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        guard status == .success else { return nil }
        return ref as? String
    }

    private static func pointAttribute(_ element: AXUIElement, attr: String) -> CGPoint? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        guard status == .success, let value = ref else { return nil }
        var point = CGPoint.zero
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, attr: String) -> CGSize? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        guard status == .success, let value = ref else { return nil }
        var size = CGSize.zero
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}
