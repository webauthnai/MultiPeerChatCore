// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public class ChatFileManager {
    public static let shared = ChatFileManager()
    
    private let fileManager = FileManager.default
    private let uploadsDirectory: URL
    private let thumbnailsDirectory: URL
    
    // Maximum file size: 50MB
    public static let maxFileSize: Int64 = 50 * 1024 * 1024
    
    // Allowed file types
    public static let allowedImageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]
    public static let allowedFileTypes = [
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "text/plain",
        "application/zip",
        "application/x-zip-compressed"
    ] + allowedImageTypes
    
    private init() {
        // Create uploads directory in the app's documents directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.uploadsDirectory = documentsPath.appendingPathComponent("uploads")
        self.thumbnailsDirectory = uploadsDirectory.appendingPathComponent("thumbnails")
        
        // Create directories if they don't exist
        try? fileManager.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - File Upload
    
    public func saveUploadedFile(data: Data, originalFileName: String, mimeType: String) throws -> FileAttachment {
        // Validate file size
        guard data.count <= Self.maxFileSize else {
            throw FileError.fileTooLarge
        }
        
        // Validate file type
        guard Self.allowedFileTypes.contains(mimeType) else {
            throw FileError.unsupportedFileType
        }
        
        // Generate unique filename
        let fileExtension = getFileExtension(for: mimeType, originalFileName: originalFileName)
        let uniqueFileName = "\(UUID().uuidString).\(fileExtension)"
        let filePath = uploadsDirectory.appendingPathComponent(uniqueFileName)
        
        // Save file
        try data.write(to: filePath)
        
        // Create thumbnail for images
        var thumbnailPath: String? = nil
        if mimeType.hasPrefix("image/") {
            thumbnailPath = try? createThumbnail(for: filePath, fileName: uniqueFileName)
        }
        
        return FileAttachment(
            fileName: uniqueFileName,
            originalFileName: originalFileName,
            mimeType: mimeType,
            fileSize: Int64(data.count),
            filePath: "uploads/\(uniqueFileName)",
            thumbnailPath: thumbnailPath
        )
    }
    
    // MARK: - File Serving
    
    public func getFileData(for attachment: FileAttachment) throws -> Data {
        let filePath = uploadsDirectory.appendingPathComponent(attachment.fileName)
        guard fileManager.fileExists(atPath: filePath.path) else {
            throw FileError.fileNotFound
        }
        return try Data(contentsOf: filePath)
    }
    
    public func getThumbnailData(for attachment: FileAttachment) throws -> Data? {
        guard let thumbnailPath = attachment.thumbnailPath else { return nil }
        let fullPath = uploadsDirectory.appendingPathComponent(thumbnailPath)
        guard fileManager.fileExists(atPath: fullPath.path) else { return nil }
        return try Data(contentsOf: fullPath)
    }
    
    public func getFileURL(for attachment: FileAttachment) -> URL {
        return uploadsDirectory.appendingPathComponent(attachment.fileName)
    }
    
    // MARK: - File Management
    
    public func deleteFile(_ attachment: FileAttachment) {
        let filePath = uploadsDirectory.appendingPathComponent(attachment.fileName)
        try? fileManager.removeItem(at: filePath)
        
        if let thumbnailPath = attachment.thumbnailPath {
            let thumbPath = uploadsDirectory.appendingPathComponent(thumbnailPath)
            try? fileManager.removeItem(at: thumbPath)
        }
    }
    
    public func cleanupOrphanedFiles(validAttachments: [FileAttachment]) {
        guard let files = try? fileManager.contentsOfDirectory(at: uploadsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        let validFileNames = Set(validAttachments.map { $0.fileName })
        let validThumbnailNames = Set(validAttachments.compactMap { $0.thumbnailPath?.components(separatedBy: "/").last })
        
        for file in files {
            let fileName = file.lastPathComponent
            if fileName != "thumbnails" && !validFileNames.contains(fileName) && !validThumbnailNames.contains(fileName) {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getFileExtension(for mimeType: String, originalFileName: String) -> String {
        // First try to get extension from original filename
        let originalExtension = (originalFileName as NSString).pathExtension.lowercased()
        if !originalExtension.isEmpty {
            return originalExtension
        }
        
        // Fallback to mime type mapping
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "application/pdf": return "pdf"
        case "application/msword": return "doc"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.ms-excel": return "xls"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "application/vnd.ms-powerpoint": return "ppt"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return "pptx"
        case "text/plain": return "txt"
        case "application/zip", "application/x-zip-compressed": return "zip"
        default: return "bin"
        }
    }
    
    private func createThumbnail(for imageURL: URL, fileName: String) throws -> String? {
        #if canImport(AppKit)
        
        guard let image = NSImage(contentsOf: imageURL) else { return nil }
        
        let thumbnailSize = NSSize(width: 200, height: 200)
        let thumbnail = NSImage(size: thumbnailSize)
        
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: NSPoint.zero, size: thumbnailSize),
                  from: NSRect(origin: NSPoint.zero, size: image.size),
                  operation: .copy,
                  fraction: 1.0)
        thumbnail.unlockFocus()
        
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        
        let thumbnailFileName = "thumb_\(fileName)"
        let thumbnailPath = thumbnailsDirectory.appendingPathComponent(thumbnailFileName)
        try jpegData.write(to: thumbnailPath)
        
        return "thumbnails/\(thumbnailFileName)"
        
        #elseif canImport(UIKit)
        
        guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }
        
        let thumbnailSize = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let thumbnail = thumbnail,
              let jpegData = thumbnail.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        let thumbnailFileName = "thumb_\(fileName)"
        let thumbnailPath = thumbnailsDirectory.appendingPathComponent(thumbnailFileName)
        try jpegData.write(to: thumbnailPath)
        
        return "thumbnails/\(thumbnailFileName)"
        
        #else
        return nil
        #endif
    }
}

// MARK: - File Errors

public enum FileError: Error, LocalizedError {
    case fileTooLarge
    case unsupportedFileType
    case fileNotFound
    case uploadFailed
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "File is too large. Maximum size is \(ChatFileManager.maxFileSize / (1024 * 1024))MB."
        case .unsupportedFileType:
            return "File type is not supported."
        case .fileNotFound:
            return "File not found."
        case .uploadFailed:
            return "File upload failed."
        case .invalidData:
            return "Invalid file data."
        }
    }
} 
