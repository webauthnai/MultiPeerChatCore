// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation

// MARK: - User Model
public struct User: Codable, Hashable, Identifiable {
    public let id: UUID
    public let username: String
    public let joinedAt: Date
    public let emoji: String
    
    public init(username: String, emoji: String = "👤") {
        self.id = UUID()
        self.username = username
        self.joinedAt = Date()
        self.emoji = emoji
    }
    
    public init(id: UUID, username: String, joinedAt: Date, emoji: String = "👤") {
        self.id = id
        self.username = username
        self.joinedAt = joinedAt
        self.emoji = emoji
    }
}

// MARK: - Admin User Model for Admin Management
public struct AdminUser: Codable, Identifiable {
    public let id: UUID
    public let username: String
    public let credentialId: String
    public let publicKey: String
    public let signCount: UInt32
    public let createdAt: Date
    public let lastLoginAt: Date?
    public let lastLoginIP: String?
    public let isEnabled: Bool
    public let userNumber: Int
    public let emoji: String
    
    public init(
        username: String,
        credentialId: String,
        publicKey: String,
        signCount: UInt32 = 0,
        lastLoginIP: String? = nil,
        userNumber: Int,
        emoji: String = "👤"
    ) {
        self.id = UUID()
        self.username = username
        self.credentialId = credentialId
        self.publicKey = publicKey
        self.signCount = signCount
        self.createdAt = Date()
        self.lastLoginAt = nil
        self.lastLoginIP = lastLoginIP
        self.isEnabled = true
        self.userNumber = userNumber
        self.emoji = emoji
    }
    
    public func updatedWithLogin(ip: String?, signCount: UInt32) -> AdminUser {
        return AdminUser(
            id: self.id,
            username: self.username,
            credentialId: self.credentialId,
            publicKey: self.publicKey,
            signCount: signCount,
            createdAt: self.createdAt,
            lastLoginAt: Date(),
            lastLoginIP: ip,
            isEnabled: self.isEnabled,
            userNumber: self.userNumber,
            emoji: self.emoji
        )
    }
    
    public func withEnabledStatus(_ enabled: Bool) -> AdminUser {
        return AdminUser(
            id: self.id,
            username: self.username,
            credentialId: self.credentialId,
            publicKey: self.publicKey,
            signCount: self.signCount,
            createdAt: self.createdAt,
            lastLoginAt: self.lastLoginAt,
            lastLoginIP: self.lastLoginIP,
            isEnabled: enabled,
            userNumber: self.userNumber,
            emoji: self.emoji
        )
    }
    
    public func withEmoji(_ newEmoji: String) -> AdminUser {
        return AdminUser(
            id: self.id,
            username: self.username,
            credentialId: self.credentialId,
            publicKey: self.publicKey,
            signCount: self.signCount,
            createdAt: self.createdAt,
            lastLoginAt: self.lastLoginAt,
            lastLoginIP: self.lastLoginIP,
            isEnabled: self.isEnabled,
            userNumber: self.userNumber,
            emoji: newEmoji
        )
    }
    
    private init(
        id: UUID,
        username: String,
        credentialId: String,
        publicKey: String,
        signCount: UInt32,
        createdAt: Date,
        lastLoginAt: Date?,
        lastLoginIP: String?,
        isEnabled: Bool,
        userNumber: Int,
        emoji: String
    ) {
        self.id = id
        self.username = username
        self.credentialId = credentialId
        self.publicKey = publicKey
        self.signCount = signCount
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.lastLoginIP = lastLoginIP
        self.isEnabled = isEnabled
        self.userNumber = userNumber
        self.emoji = emoji
    }
}

// MARK: - Room Model
public struct Room: Codable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public var participants: Set<User>
    public let createdBy: User
    
    public init(name: String, createdBy: User) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.participants = [createdBy]
        self.createdBy = createdBy
    }
    
    public init(id: UUID, name: String, createdAt: Date, createdBy: User) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.participants = [createdBy]
        self.createdBy = createdBy
    }
    
    public mutating func addParticipant(_ user: User) {
        participants.insert(user)
    }
    
    public mutating func removeParticipant(_ user: User) {
        participants.remove(user)
    }
}

// MARK: - File Attachment Model
public struct FileAttachment: Codable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let originalFileName: String
    public let mimeType: String
    public let fileSize: Int64
    public let filePath: String
    public let uploadedAt: Date
    public let isImage: Bool
    public let thumbnailPath: String?
    
    public init(fileName: String, originalFileName: String, mimeType: String, fileSize: Int64, filePath: String, thumbnailPath: String? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.filePath = filePath
        self.uploadedAt = Date()
        self.isImage = mimeType.hasPrefix("image/")
        self.thumbnailPath = thumbnailPath
    }
    
    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Message Model
public struct ChatMessage: Codable, Identifiable {
    public let id: UUID
    public let content: String
    public let sender: User
    public let roomId: UUID
    public let timestamp: Date
    public let messageType: MessageType
    public let attachment: FileAttachment?
    
    public enum MessageType: String, Codable {
        case text
        case image
        case file
        case userJoined
        case userLeft
        case roomCreated
    }
    
    public init(content: String, sender: User, roomId: UUID, messageType: MessageType = .text, attachment: FileAttachment? = nil) {
        self.id = UUID()
        self.content = content
        self.sender = sender
        self.roomId = roomId
        self.timestamp = Date()
        self.messageType = messageType
        self.attachment = attachment
    }
    
    public init(id: UUID, content: String, sender: User, roomId: UUID, timestamp: Date, messageType: MessageType = .text, attachment: FileAttachment? = nil) {
        self.id = id
        self.content = content
        self.sender = sender
        self.roomId = roomId
        self.timestamp = timestamp
        self.messageType = messageType
        self.attachment = attachment
    }
    
    // Convenience initializer for file messages
    public init(attachment: FileAttachment, sender: User, roomId: UUID, caption: String = "") {
        self.id = UUID()
        self.content = caption.isEmpty ? attachment.originalFileName : caption
        self.sender = sender
        self.roomId = roomId
        self.timestamp = Date()
        self.messageType = attachment.isImage ? .image : .file
        self.attachment = attachment
    }
}

// MARK: - Chat Link Model
public struct ChatLink: Codable {
    public let roomId: UUID
    public let roomName: String
    public let inviteCode: String
    public let createdBy: User
    public let expiresAt: Date?
    
    public init(room: Room, expiresIn: TimeInterval? = nil) {
        self.roomId = room.id
        self.roomName = room.name
        self.inviteCode = Self.generateInviteCode()
        self.createdBy = room.createdBy
        self.expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
    }
    
    private static func generateInviteCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<8).map { _ in characters.randomElement()! })
    }
    
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    public func generateShareableLink() -> String {
        return "multipeer-chat://join?code=\(inviteCode)&room=\(roomName)"
    }
}

// MARK: - Network Message Protocol
public enum NetworkMessage: Codable {
    case chatMessage(ChatMessage)
    case userJoined(User, UUID) // User, RoomId
    case userLeft(User, UUID)   // User, RoomId
    case roomCreated(Room)
    case roomList([Room])
    case joinRoom(UUID, User)   // RoomId, User
    case leaveRoom(UUID, User)  // RoomId, User
    case ping
    case pong
    
    public var data: Data? {
        try? JSONEncoder().encode(self)
    }
    
    public static func from(data: Data) -> NetworkMessage? {
        try? JSONDecoder().decode(NetworkMessage.self, from: data)
    }
}

