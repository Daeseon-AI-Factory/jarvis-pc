//
//  OCRService.swift
//  ScreenBridge — Phase 6.1
//
//  Vision framework `VNRecognizeTextRequest` wrapper.
//  - recognitionLevel = .accurate (속도보다 정확도)
//  - languages = ko-KR + en-US (한국어/영어 혼합 화면 표준)
//  - revision = VNRecognizeTextRequestRevision3 (Apple의 안정 명시 — default는 시간 따라 변함, R9)
//  - Y-flip: Vision은 normalized bottom-left → sent image top-left 변환 한 곳 (Layer 핵심)
//

import CoreGraphics
import Foundation
import Vision

protocol OCRService: Sendable {
    func recognize(pngData: Data, sentSize: CGSize) async throws -> [OCRBox]
}

enum OCRError: Error, Sendable {
    case imageDecodeFailed
    case visionFailed(String)
}

struct VisionOCRService: OCRService {

    func recognize(pngData: Data, sentSize: CGSize) async throws -> [OCRBox] {
        // Vision은 sync API — background thread에서.
        // Task.detached → Task로 변경 (verify HIGH): parent actor isolation/priority 상속.
        // 단 Vision sync 자체 cancel 불가 (Apple SDK 한계) — Vision perform 중간엔 cancel 무시.
        // perform 시작 전 Task.checkCancellation으로 early-exit 가능.
        try await Task(priority: .userInitiated) {
            try Task.checkCancellation()
            return try Self.recognizeSync(pngData: pngData, sentSize: sentSize)
        }.value
    }

    private static func recognizeSync(pngData: Data, sentSize: CGSize) throws -> [OCRBox] {
        guard let provider = CGDataProvider(data: pngData as CFData),
              let cgImage = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw OCRError.imageDecodeFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3

        // 지원 언어 사전 확인 — request configure 후 instance method 사용
        // (type method `supportedRecognitionLanguages(for:revision:)`는 macOS 12+ deprecated, verify fix).
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        var langs: [String] = []
        if supported.contains("ko-KR") {
            langs.append("ko-KR")
        } else {
            Log.dispatcher.notice("[ocr] ko-KR not in supported list — falling back to en-US only (한국어 화면 인식 불가)")
        }
        langs.append("en-US")
        request.recognitionLanguages = langs

        // CGImage from PNG is top-left native → default .up orientation correct.
        // ⚠️ source가 CIImage(EXIF orientation 가질 수 있음) 또는 IOSurface로 바뀌면
        //    Y-flip 수학 (line 78-84) 재검증 필요 — OCRService.recognize의 좌표계 가정 깨짐.
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.visionFailed(error.localizedDescription)
        }

        guard let observations = request.results else { return [] }

        let w = sentSize.width
        let h = sentSize.height

        let boxes: [OCRBox] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            // Vision boundingBox: normalized 0..1, *bottom-left* origin.
            // → sent image px, top-left origin. Y-flip:
            //   bb.maxY = top edge (bottom-left에서 큰 y) → 1 - maxY = distance from top = top-left y.
            let bb = obs.boundingBox
            let rect = CGRect(
                x: bb.minX * w,
                y: (1.0 - bb.maxY) * h,
                width: bb.width * w,
                height: bb.height * h
            )
            return OCRBox(
                text: candidate.string,
                rectInSentImage: rect,
                confidence: candidate.confidence
            )
        }

        Log.dispatcher.info("[ocr] \(boxes.count, privacy: .public) text boxes recognized")
        return boxes
    }
}
