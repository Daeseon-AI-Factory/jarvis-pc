//
//  ScreenCapture.swift
//  ScreenBridge — Phase 3.1
//
//  사용자 화면 PNG 캡처 + 1568 다운스케일. hotkey 시점 cursor 있는 monitor (Layer 10 회피).
//  결과 = PNG Data + DisplayGeometry (역변환용).
//

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCapture {
    /// 다운스케일 cap. Gemini vision 1 tile + 토큰/시간 절감.
    static let maxDimension: CGFloat = 1568

    enum CaptureError: Error, Sendable {
        case permissionDenied
        case noScreen
        case displayNotFound
        case encodeFailed
    }

    /// hotkey 시점 cursor 있는 monitor 캡처. `LastTriggerContext.capture()` 이후 호출.
    static func captureCursorScreen() async throws -> (Data, DisplayGeometry) {
        guard Permissions.hasScreenRecording() else {
            Log.dispatcher.error("[capture] no Screen Recording permission")
            throw CaptureError.permissionDenied
        }

        // 1. trigger context (hotkey 시점) — 없으면 지금 cursor fallback
        let triggerInfo: (displayID: CGDirectDisplayID, frame: NSRect, scale: CGFloat)? = await MainActor.run {
            if let t = LastTriggerContext.current {
                return (t.screen.displayID, t.screen.frame, t.screen.backingScaleFactor)
            }
            let cursor = NSEvent.mouseLocation
            guard let s = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) })
                ?? NSScreen.main else { return nil }
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            return (id, s.frame, s.backingScaleFactor)
        }
        guard let info = triggerInfo else {
            throw CaptureError.noScreen
        }

        // 2. SCDisplay 매칭
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == info.displayID }) else {
            Log.dispatcher.error("[capture] SCDisplay not found for displayID=\(info.displayID, privacy: .public)")
            throw CaptureError.displayNotFound
        }

        // 3. SCStreamConfiguration — physical pixel 명시
        let config = SCStreamConfiguration()
        config.width = Int(info.frame.width * info.scale)
        config.height = Int(info.frame.height * info.scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.captureResolution = .best

        // 4. ContentFilter — display 전체, 가린 window 제외 안 함
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // 5. one-shot capture
        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            Log.dispatcher.error("[capture] SCScreenshotManager failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let physicalSize = CGSize(width: cgImage.width, height: cgImage.height)
        Log.dispatcher.info(
            "[capture] physical \(cgImage.width, privacy: .public)x\(cgImage.height, privacy: .public) scale=\(String(format: "%.1f", info.scale), privacy: .public)x display=\(info.displayID, privacy: .public)"
        )

        // 6. 다운스케일 1568 cap
        let downscaled = downscale(cgImage, maxDimension: maxDimension)
        let sentSize = CGSize(width: downscaled.width, height: downscaled.height)

        // 7. PNG encode
        let pngData = try pngData(from: downscaled)
        Log.dispatcher.info(
            "[capture] sent \(downscaled.width, privacy: .public)x\(downscaled.height, privacy: .public) (\(pngData.count, privacy: .public) bytes)"
        )

        let geometry = DisplayGeometry(
            displayID: info.displayID,
            screenFrame: info.frame,
            backingScaleFactor: info.scale,
            physicalSize: physicalSize,
            sentSize: sentSize
        )
        return (pngData, geometry)
    }

    /// 긴 변 maxDimension cap. 비율 유지. CGContext draw + .high interpolation.
    private static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let maxSide = max(w, h)
        if maxSide <= maxDimension { return image }

        let ratio = maxDimension / maxSide
        let newW = Int((w * ratio).rounded())
        let newH = Int((h * ratio).rounded())

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    /// CGImage → PNG Data.
    private static func pngData(from image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodeFailed
        }
        return data
    }
}
