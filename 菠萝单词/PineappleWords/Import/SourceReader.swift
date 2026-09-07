import Foundation
import PDFKit
import Vision
import UIKit
import PineappleCore

enum SourceReader {
    static func read(_ url: URL) throws -> (text: String, fileExtension: String) {
        let data = try BackupService.readFile(url)
        guard data.count <= 30 * 1024 * 1024 else { throw AppError.invalidData("词书资料最大为 30 MB，请分册导入。") }
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "pdf" { return (try pdfText(data), fileExtension) }
        guard ["txt", "csv", "json"].contains(fileExtension) else { throw AppError.invalidData("目前支持 TXT、CSV、JSON 和 PDF。") }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { text = String(data: data, encoding: .utf16) }
        else { text = String(data: data, encoding: .utf8) }
        guard let text else { throw AppError.invalidData("文本编码无法识别，请另存为 UTF-8 后再导入。") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.emptyBook }
        guard text.count <= 500_000 else { throw AppError.invalidData("资料超过 50 万字，请分册导入。") }
        return (text, fileExtension)
    }

    private static func pdfText(_ data: Data) throws -> String {
        guard let document = PDFDocument(data: data), !document.isLocked else { throw AppError.invalidData("PDF 无法打开或已加密。") }
        guard document.pageCount > 0, document.pageCount <= 200 else { throw AppError.invalidData("每次支持最多 200 页 PDF，请先分册。") }
        var pages: [String] = []
        var characters = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw AppError.invalidData("PDF 第 \(index + 1) 页读取失败。") }
            var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                text = try autoreleasepool {
                    let thumbnail = page.thumbnail(of: CGSize(width: 1536, height: 2048), for: .mediaBox)
                    guard let image = thumbnail.cgImage else { throw AppError.invalidData("PDF 第 \(index + 1) 页无法识别。") }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["en-US", "zh-Hans"]
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                }
            }
            guard !text.isEmpty else { throw AppError.invalidData("PDF 第 \(index + 1) 页没有可识别文字，请检查扫描清晰度。") }
            characters += text.count
            guard characters <= 500_000 else { throw AppError.invalidData("PDF 提取文字超过 50 万字，请分册导入。") }
            pages.append("[资料第 \(index + 1) 页]\n" + text)
        }
        return pages.joined(separator: "\n\n")
    }
}
