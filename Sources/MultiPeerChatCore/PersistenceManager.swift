// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import DogTagKit

public class PersistenceManager {
    public static let shared = PersistenceManager()
    
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let rooms = "MultiPeerChat_Rooms"
        static let messages = "MultiPeerChat_Messages"
        static let chatLinks = "MultiPeerChat_ChatLinks"
        static let adminUsers = "MultiPeerChat_AdminUsers"
    }
    
    private init() {}
    
    // MARK: - Room Persistence
    
    public func saveRoom(_ room: Room) {
        var rooms = loadRooms()
        
        // Remove existing room with same ID if it exists
        rooms.removeAll { $0.id == room.id }
        
        // Add the new/updated room
        rooms.append(room)
        
        saveRooms(rooms)
    }
    
    public func loadRooms() -> [Room] {
        guard let data = userDefaults.data(forKey: Keys.rooms),
              let rooms = try? JSONDecoder().decode([Room].self, from: data) else {
            return []
        }
        return rooms
    }
    
    private func saveRooms(_ rooms: [Room]) {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        userDefaults.set(data, forKey: Keys.rooms)
    }
    
    public func deleteRoom(_ roomId: UUID) {
        var rooms = loadRooms()
        rooms.removeAll { $0.id == roomId }
        saveRooms(rooms)
        
        // Also delete all messages for this room
        clearMessages(for: roomId)
    }
    
    // MARK: - Message Persistence
    
    public func saveMessage(_ message: ChatMessage) {
        var allMessages = loadAllMessages()
        allMessages.append(message)
        saveAllMessages(allMessages)
    }
    
    public func loadMessages(for roomId: UUID) -> [ChatMessage] {
        let allMessages = loadAllMessages()
        return allMessages.filter { $0.roomId == roomId }.sorted { $0.timestamp < $1.timestamp }
    }
    
    public func clearMessages(for roomId: UUID) {
        var allMessages = loadAllMessages()
        allMessages.removeAll { $0.roomId == roomId }
        saveAllMessages(allMessages)
    }
    
    private func loadAllMessages() -> [ChatMessage] {
        guard let data = userDefaults.data(forKey: Keys.messages),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return messages
    }
    
    private func saveAllMessages(_ messages: [ChatMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        userDefaults.set(data, forKey: Keys.messages)
    }
    
    // MARK: - Chat Link Persistence
    
    public func saveChatLink(_ chatLink: ChatLink) {
        var chatLinks = loadChatLinks()
        
        // Remove existing link with same invite code if it exists
        chatLinks.removeAll { $0.inviteCode == chatLink.inviteCode }
        
        // Add the new link
        chatLinks.append(chatLink)
        
        saveChatLinks(chatLinks)
    }
    
    public func loadChatLinks() -> [ChatLink] {
        guard let data = userDefaults.data(forKey: Keys.chatLinks),
              let chatLinks = try? JSONDecoder().decode([ChatLink].self, from: data) else {
            return []
        }
        return chatLinks
    }
    
    private func saveChatLinks(_ chatLinks: [ChatLink]) {
        guard let data = try? JSONEncoder().encode(chatLinks) else { return }
        userDefaults.set(data, forKey: Keys.chatLinks)
    }
    
    public func deleteChatLink(_ inviteCode: String) {
        var chatLinks = loadChatLinks()
        chatLinks.removeAll { $0.inviteCode == inviteCode }
        saveChatLinks(chatLinks)
    }
    
    public func cleanupExpiredLinks() {
        var chatLinks = loadChatLinks()
        let originalCount = chatLinks.count
        
        chatLinks.removeAll { $0.isExpired }
        
        if chatLinks.count != originalCount {
            saveChatLinks(chatLinks)
        }
    }
    
    // MARK: - Utility Methods
    
    public func clearAllData() {
        userDefaults.removeObject(forKey: Keys.rooms)
        userDefaults.removeObject(forKey: Keys.messages)
        userDefaults.removeObject(forKey: Keys.chatLinks)
        userDefaults.removeObject(forKey: Keys.adminUsers)
    }
    
    // MARK: - File Attachment Management
    
    public func getAllAttachments() -> [FileAttachment] {
        let allMessages = loadAllMessages()
        let messageAttachments = allMessages.compactMap { $0.attachment }
        
        // Also load standalone attachments
        let standaloneAttachments = loadStandaloneAttachments()
        
        return messageAttachments + standaloneAttachments
    }
    
    public func saveStandaloneAttachment(_ attachment: FileAttachment) {
        var attachments = loadStandaloneAttachments()
        
        // Remove existing attachment with same ID if it exists
        attachments.removeAll { $0.id == attachment.id }
        
        // Add the new attachment
        attachments.append(attachment)
        
        saveStandaloneAttachments(attachments)
    }
    
    private func loadStandaloneAttachments() -> [FileAttachment] {
        guard let data = userDefaults.data(forKey: "MultiPeerChat_StandaloneAttachments"),
              let attachments = try? JSONDecoder().decode([FileAttachment].self, from: data) else {
            return []
        }
        return attachments
    }
    
    private func saveStandaloneAttachments(_ attachments: [FileAttachment]) {
        guard let data = try? JSONEncoder().encode(attachments) else { return }
        userDefaults.set(data, forKey: "MultiPeerChat_StandaloneAttachments")
    }
    
    public func cleanupOrphanedFiles() {
        let validAttachments = getAllAttachments()
        ChatFileManager.shared.cleanupOrphanedFiles(validAttachments: validAttachments)
        
        // Also cleanup standalone attachments that are older than 1 hour
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var standaloneAttachments = loadStandaloneAttachments()
        standaloneAttachments.removeAll { $0.uploadedAt < oneHourAgo }
        saveStandaloneAttachments(standaloneAttachments)
    }
    
    public func deleteMessagesWithAttachment(_ attachment: FileAttachment) {
        var allMessages = loadAllMessages()
        allMessages.removeAll { $0.attachment?.id == attachment.id }
        saveAllMessages(allMessages)
        
        // Delete the actual file
        ChatFileManager.shared.deleteFile(attachment)
    }
    
    // MARK: - Admin User Management
    
    public func saveAdminUser(_ adminUser: AdminUser) {
        var adminUsers = loadAdminUsers()
        
        print("[Persistence] 💾 Saving user '\(adminUser.username)' with enabled status: \(adminUser.isEnabled)")
        
        // Remove existing user with same ID or username if it exists
        adminUsers.removeAll { $0.id == adminUser.id || $0.username == adminUser.username }
        
        // Add the new/updated user
        adminUsers.append(adminUser)
        
        saveAdminUsers(adminUsers)
        
        // Verify the user was saved correctly by reloading
        let reloadedUsers = loadAdminUsers()
        if let savedUser = reloadedUsers.first(where: { $0.username == adminUser.username }) {
            print("[Persistence] ✅ Verified saved user '\(adminUser.username)' enabled status: \(savedUser.isEnabled)")
        } else {
            print("[Persistence] ❌ Failed to verify saved user '\(adminUser.username)'")
        }
    }
    
    public func loadAdminUsers() -> [AdminUser] {
        guard let data = userDefaults.data(forKey: Keys.adminUsers),
              let users = try? JSONDecoder().decode([AdminUser].self, from: data) else {
            return []
        }
        return users
    }
    
    private func saveAdminUsers(_ adminUsers: [AdminUser]) {
        guard let data = try? JSONEncoder().encode(adminUsers) else { return }
        userDefaults.set(data, forKey: Keys.adminUsers)
    }
    
    public func deleteAdminUser(_ userId: UUID) {
        let adminUsers = loadAdminUsers()
        if let userToDelete = adminUsers.first(where: { $0.id == userId }) {
            // Delete user's credentials from WebAuthnManager
            WebAuthnManager.shared.deleteUserCredentials(username: userToDelete.username)
            
            // Remove user from admin users list
            let updatedUsers = adminUsers.filter { $0.id != userId }
            saveAdminUsers(updatedUsers)
            print("[Persistence] ✅ Successfully deleted user: \(userToDelete.username)")
        }
    }
    
    public func getAdminUser(by username: String) -> AdminUser? {
        let users = loadAdminUsers()
        return users.first { $0.username == username }
    }
    
    public func getAdminUser(byCredentialId credentialId: String) -> AdminUser? {
        let users = loadAdminUsers()
        return users.first { $0.credentialId == credentialId }
    }
    
    public func getNextUserNumber() -> Int {
        let adminUsers = loadAdminUsers()
        let maxUserNumber = adminUsers.map { $0.userNumber }.max() ?? 0
        return maxUserNumber + 1
    }
    
    public func disableAdminUsersByIP(_ ipAddress: String) {
        let adminUsers = loadAdminUsers()
        let updatedUsers = adminUsers.map { user in
            if user.lastLoginIP == ipAddress {
                return user.withEnabledStatus(false)
            }
            return user
        }
        saveAdminUsers(updatedUsers)
    }
} 
