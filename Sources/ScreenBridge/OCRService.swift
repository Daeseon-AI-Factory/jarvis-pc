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
        try await Task.detached(priority: .userInitiated) {
            try Self.recognizeSync(pngData: pngData, sentSize: sentSize)
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

        // 지원 언어 사전 확인 — ko-KR 없으면 en-US만 (SCRATCHPAD 기록 후 dev)
        let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequestRevision3
        )) ?? []
        var langs: [String] = []
        if supported.contains("ko-KR") {
            langs.append("ko-KR")
        }
        langs.append("en-US")
        request.recognitionLanguages = langs

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
            // → sent image px, top-left origin. Y-flip: `(1 - maxY) * h`.
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
