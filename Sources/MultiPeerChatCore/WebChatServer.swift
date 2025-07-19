// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import Network
import Combine
import DogTagKit

public class WebChatServer: ObservableObject, WebServerDelegate {
    @Published public var isRunning = false
    @Published public var connectedUsers = 0
    @Published public var totalRooms = 0
    
    private var webServer: WebServer
    private var rooms: [String: Room] = [:]
    private var users: [String: WebSocketClient] = [:]
    private var userRooms: [String: String] = [:] // userId -> roomId
    private var inviteLinks: [String: ChatLink] = [:]
    private var roomMessages: [String: [ChatMessage]] = [:] // roomId -> messages
    private var userEmojis: [String: String] = [:] // username -> emoji
    
    private var cancellables = Set<AnyCancellable>()
    private let persistenceManager = PersistenceManager.shared
    private let rpId: String
    private let webAuthnProtocol: WebAuthnProtocol
    private let storageBackend: WebAuthnStorageBackend
    private let adminUsername: String
    private var port: UInt16?
    
    
    public init(rpId: String, adminUsername: String = "XCF Admin", webAuthnProtocol: WebAuthnProtocol = .fido2CBOR, storageBackend: WebAuthnStorageBackend = .json("")) {
        self.rpId = rpId
        self.adminUsername = adminUsername
        self.webAuthnProtocol = webAuthnProtocol
        self.storageBackend = storageBackend
        self.webServer = WebServer(rpId: rpId, adminUsername: adminUsername, storageBackend: storageBackend)
        webServer.delegate = self
        
        // Observe webServer's running state
        webServer.$isRunning.sink { [weak self] running in
            DispatchQueue.main.async {
                self?.isRunning = running
            }
        }.store(in: &cancellables)
        
        // Observe webServer's connected clients
        webServer.$connectedClients.sink { [weak self] clients in
            DispatchQueue.main.async {
                self?.connectedUsers = clients
            }
        }.store(in: &cancellables)
        
        // Load persisted data
        loadPersistedData()
        
        // Create default Lobby room if it doesn't exist
        if !rooms.values.contains(where: { $0.name == "Lobby" }) {
            let systemUser = User(username: "System")
            let lobbyRoom = Room(name: "Lobby", createdBy: systemUser)
            rooms[lobbyRoom.id.uuidString] = lobbyRoom
            roomMessages[lobbyRoom.id.uuidString] = []
            
            // Save to persistence
            persistenceManager.saveRoom(lobbyRoom)
            
            DispatchQueue.main.async {
                self.totalRooms = self.rooms.count
            }
        }
    }
    
    private func loadPersistedData() {
        // Load rooms
        let persistedRooms = persistenceManager.loadRooms()
        for room in persistedRooms {
            rooms[room.id.uuidString] = room
        }
        
        // Load chat links
        let persistedLinks = persistenceManager.loadChatLinks()
        for link in persistedLinks {
            if !link.isExpired {
                inviteLinks[link.inviteCode] = link
            }
        }
        
        // Load messages for each room
        for room in persistedRooms {
            let messages = persistenceManager.loadMessages(for: room.id)
            roomMessages[room.id.uuidString] = messages
        }
        
        // Cleanup expired links
        persistenceManager.cleanupExpiredLinks()
        
        DispatchQueue.main.async {
            self.totalRooms = self.rooms.count
        }
    }
    
    public func start(on port: UInt16) {
        // Store the port and recreate WebServer with port for proper icon URLs
        self.port = port
        
        // Get the existing WebAuthn manager to reuse it (avoid double initialization)
        let existingWebAuthnManager = webServer.webAuthnManager
        
        webServer.stop() // Stop the old one
        webServer = WebServer(rpId: rpId, port: port, adminUsername: adminUsername, storageBackend: storageBackend, existingWebAuthnManager: existingWebAuthnManager)
        webServer.delegate = self
        
        webServer.start(on: port)
        
        // Explicitly set running state
        DispatchQueue.main.async {
            self.isRunning = true
            self.totalRooms = self.rooms.count
            self.connectedUsers = self.users.count
        }
    }
    
    public func stop() {
        webServer.stop()
        
        // Reset all states
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedUsers = 0
            self.totalRooms = 0
            
            // Clear rooms and users
            self.rooms.removeAll()
            self.users.removeAll()
            self.userRooms.removeAll()
            self.inviteLinks.removeAll()
        }
    }
    
    // MARK: - WebServerDelegate
    
    public func webServer(_ server: WebServer, didReceiveMessage message: String, from client: WebSocketClient) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "join":
            handleUserJoin(json, client: client)
        case "createRoom":
            handleCreateRoom(json, client: client)
        case "joinRoom":
            handleJoinRoom(json, client: client)
        case "leaveRoom":
            handleLeaveRoom(json, client: client)
        case "sendMessage":
            handleSendMessage(json, client: client)
        case "sendFileMessage":
            handleSendFileMessage(json, client: client)
        case "createInvite":
            handleCreateInvite(json, client: client)
        case "clearChatHistory":
            handleClearChatHistory(json, client: client)
        case "removeRoom":
            handleRemoveRoom(json, client: client)
        case "ping":
            handlePing(json, client: client)
        case "pong":
            handlePong(json, client: client)
        case "updateEmoji":
            handleUpdateEmoji(json, client: client)
        default:
            break
        }
    }
    
    public func webServer(_ server: WebServer, clientDidConnect client: WebSocketClient) {
        DispatchQueue.main.async {
            self.connectedUsers = self.users.count
        }
    }
    
    public func webServer(_ server: WebServer, clientDidDisconnect client: WebSocketClient) {
        // Remove user from tracking
        if let username = client.username {
            users.removeValue(forKey: username)
            
            // Leave current room if any
            if let roomId = userRooms[username] {
                leaveUserFromRoom(username: username, roomId: roomId)
                userRooms.removeValue(forKey: username)
            }
        }
        
        DispatchQueue.main.async {
            self.connectedUsers = self.users.count
        }
        
        broadcastUserCount()
    }
    
    // MARK: - Message Handlers
    
    private func handleUserJoin(_ json: [String: Any], client: WebSocketClient) {
        guard let username = json["username"] as? String else { return }
        let emoji = (json["emoji"] as? String) ?? "👤"
        let isReconnecting = (json["isReconnecting"] as? Bool) ?? false
        
        client.username = username
        
        // Get stored emoji from database, or use provided emoji if no stored one
        let storedEmoji = webServer.webAuthnManager.getUserEmoji(username: username) ?? emoji
        userEmojis[username] = storedEmoji
        
        // If the provided emoji is different from stored, update the database
        if emoji != "👤" && emoji != storedEmoji {
            let _ = webServer.webAuthnManager.updateUserEmoji(username: username, emoji: emoji)
            userEmojis[username] = emoji
        }
        
        users[username] = client
        
        // Send current rooms list with admin status
        let isAdmin = (username == adminUsername)
        sendToClient(client, message: [
            "type": "roomList",
            "rooms": rooms.values.map { roomToDict($0) },
            "isAdmin": isAdmin,
            "userEmoji": userEmojis[username] ?? "👤"
        ])
        
        // Only auto-join Lobby for new connections, not reconnections
        // Let the frontend handle room rejoining for reconnections
        if !isReconnecting {
            if let lobby = rooms.values.first(where: { $0.name == "Lobby" }) {
                handleJoinRoom(["roomId": lobby.id.uuidString], client: client)
            }
        }
        
        DispatchQueue.main.async {
            self.connectedUsers = self.users.count
        }
        
        broadcastUserCount()
    }
    
    private func handleCreateRoom(_ json: [String: Any], client: WebSocketClient) {
        guard let roomName = json["name"] as? String,
              let username = client.username else { return }
        
        // Check if room name already exists (case-insensitive)
        let duplicateRoom = rooms.values.first { $0.name.lowercased() == roomName.lowercased() }
        
        if duplicateRoom != nil || roomName.lowercased() == "lobby" {
            // Send error message back to the client
            sendToClient(client, message: [
                "type": "error",
                "message": "A room with this name already exists"
            ])
            return
        }
        
        let user = User(username: username)
        let room = Room(name: roomName, createdBy: user)
        
        rooms[room.id.uuidString] = room
        roomMessages[room.id.uuidString] = []
        
        // Save to persistence
        persistenceManager.saveRoom(room)
        
        // Broadcast room creation to all users
        broadcast([
            "type": "roomCreated",
            "room": roomToDict(room)
        ]
        )
        
        DispatchQueue.main.async {
            self.totalRooms = self.rooms.count
        }
    }
    
    private func handleJoinRoom(_ json: [String: Any], client: WebSocketClient) {
        guard let roomId = json["roomId"] as? String,
              let username = client.username,
              var room = rooms[roomId] else { return }
        
        // Leave current room if any
        if let currentRoomId = userRooms[username] {
            leaveUserFromRoom(username: username, roomId: currentRoomId)
        }
        
        // Join new room
        let user = User(username: username)
        room.addParticipant(user)
        rooms[roomId] = room
        userRooms[username] = roomId
        client.currentRoom = roomId
        
        // Send message history to the joining user
        if let messages = roomMessages[roomId] {
            for message in messages {
                var messageDict: [String: Any] = [
                    "type": "chatMessage",
                    "message": [
                        "sender": message.sender.username,
                        "content": message.content,
                        "timestamp": ISO8601DateFormatter().string(from: message.timestamp),
                        "messageType": message.messageType.rawValue,
                        "emoji": message.sender.emoji
                    ]
                ]
                
                // Add attachment information if present
                if let attachment = message.attachment {
                    var attachmentDict: [String: Any] = [
                        "id": attachment.id.uuidString,
                        "fileName": attachment.fileName,
                        "originalFileName": attachment.originalFileName,
                        "name": attachment.originalFileName, // For client compatibility
                        "mimeType": attachment.mimeType,
                        "fileSize": attachment.fileSize,
                        "size": attachment.fileSize, // For client compatibility
                        "url": "/files/\(attachment.id.uuidString)/\(attachment.originalFileName)",
                        "isImage": attachment.isImage,
                        "filePath": attachment.filePath,
                        "thumbnailPath": attachment.thumbnailPath as Any
                    ]
                    
                    // Add thumbnail URL if available
                    if let thumbnailPath = attachment.thumbnailPath {
                        attachmentDict["thumbnailUrl"] = "/\(thumbnailPath)"
                    }
                    
                    messageDict["message"] = (messageDict["message"] as! [String: Any]).merging([
                        "attachment": attachmentDict
                    ]) { _, new in new }
                }
                
                sendToClient(client, message: messageDict)
            }
        }
        
        // Notify client of room join for UI update
        let isAdmin = (username == adminUsername)
        sendToClient(client, message: [
            "type": "roomJoined",
            "room": roomToDict(room),
            "isAdmin": isAdmin
        ])
    }
    
    private func handleLeaveRoom(_ json: [String: Any], client: WebSocketClient) {
        guard let roomId = json["roomId"] as? String,
              let username = client.username else { return }
        
        leaveUserFromRoom(username: username, roomId: roomId)
        userRooms.removeValue(forKey: username)
        client.currentRoom = nil
    }
    
    private func handleSendMessage(_ json: [String: Any], client: WebSocketClient) {
        guard let roomId = json["roomId"] as? String,
              let content = json["content"] as? String,
              let username = client.username,
              let room = rooms[roomId] else { return }
        
        // Use stored emoji, fallback to provided emoji, then fallback to default
        let storedEmoji = userEmojis[username] ?? webServer.webAuthnManager.getUserEmoji(username: username)
        let providedEmoji = (json["emoji"] as? String)
        let emoji = storedEmoji ?? providedEmoji ?? "👤"
        
        // Update stored emoji if a different one was provided
        if let providedEmoji = providedEmoji, providedEmoji != emoji {
            let _ = webServer.webAuthnManager.updateUserEmoji(username: username, emoji: providedEmoji)
            userEmojis[username] = providedEmoji
        }
        
        let user = User(username: username, emoji: emoji)
        let chatMessage = ChatMessage(content: content, sender: user, roomId: room.id)
        
        // Save message to persistence
        persistenceManager.saveMessage(chatMessage)
        
        // Add to in-memory storage
        if roomMessages[roomId] == nil {
            roomMessages[roomId] = []
        }
        roomMessages[roomId]?.append(chatMessage)
        
        let message = [
            "type": "chatMessage",
            "message": [
                "sender": username,
                "content": content,
                "timestamp": ISO8601DateFormatter().string(from: chatMessage.timestamp),
                "messageType": chatMessage.messageType.rawValue,
                "emoji": emoji
            ]
        ] as [String : Any]
        
        broadcastToRoom(roomId, message: message)
    }
    
    private func handleSendFileMessage(_ json: [String: Any], client: WebSocketClient) {
        guard let roomId = json["roomId"] as? String,
              let username = client.username,
              let room = rooms[roomId],
              let attachmentData = json["attachment"] as? [String: Any],
              let attachmentId = attachmentData["id"] as? String,
              let attachmentUUID = UUID(uuidString: attachmentId) else { 
            print("❌ Failed to parse file message: \(json)")
            return 
        }
        
        // Find the attachment from all stored attachments
        let allAttachments = persistenceManager.getAllAttachments()
        print("🔍 Looking for attachment \(attachmentUUID) in \(allAttachments.count) stored attachments")
        
        guard let attachment = allAttachments.first(where: { $0.id == attachmentUUID }) else { 
            print("❌ Attachment not found: \(attachmentUUID)")
            print("📋 Available attachments: \(allAttachments.map { $0.id })")
            return 
        }
        
        print("✅ Found attachment: \(attachment.originalFileName)")
        
        let caption = json["caption"] as? String ?? ""
        let emoji = userEmojis[username] ?? "👤"
        let user = User(username: username, emoji: emoji)
        let chatMessage = ChatMessage(attachment: attachment, sender: user, roomId: room.id, caption: caption)
        
        // Save message to persistence
        persistenceManager.saveMessage(chatMessage)
        
        // Add to in-memory storage
        if roomMessages[roomId] == nil {
            roomMessages[roomId] = []
        }
        roomMessages[roomId]?.append(chatMessage)
        
        var attachmentDict: [String: Any] = [
            "id": attachment.id.uuidString,
            "fileName": attachment.fileName,
            "originalFileName": attachment.originalFileName,
            "name": attachment.originalFileName, // For client compatibility
            "mimeType": attachment.mimeType,
            "fileSize": attachment.fileSize,
            "size": attachment.fileSize, // For client compatibility
            "url": "/files/\(attachment.id.uuidString)/\(attachment.originalFileName)",
            "isImage": attachment.isImage,
            "filePath": attachment.filePath,
            "thumbnailPath": attachment.thumbnailPath as Any
        ]
        
        // Add thumbnail URL if available
        if let thumbnailPath = attachment.thumbnailPath {
            attachmentDict["thumbnailUrl"] = "/\(thumbnailPath)"
        }
        
        let message = [
            "type": "chatMessage",
            "message": [
                "sender": username,
                "content": chatMessage.content,
                "timestamp": ISO8601DateFormatter().string(from: chatMessage.timestamp),
                "messageType": chatMessage.messageType.rawValue,
                "emoji": emoji,
                "attachment": attachmentDict
            ]
        ] as [String : Any]
        
        print("📤 Broadcasting file message to room \(roomId)")
        broadcastToRoom(roomId, message: message)
    }
    
    private func handleCreateInvite(_ json: [String: Any], client: WebSocketClient) {
        guard let roomId = json["roomId"] as? String,
              let room = rooms[roomId] else { return }
        
        let link = ChatLink(room: room, expiresIn: 3600) // 1 hour
        inviteLinks[link.inviteCode] = link
        
        // Save to persistence
        persistenceManager.saveChatLink(link)
        
        let inviteUrl = "http://\(getServerAddress())/join/\(link.inviteCode)"
        
        sendToClient(client, message: [
            "type": "inviteCreated",
            "link": inviteUrl
        ])
    }
    
    private func handleClearChatHistory(_ json: [String: Any], client: WebSocketClient) {
        guard client.username == adminUsername else {
            sendToClient(client, message: ["type": "error", "message": "Only an admin can clear history."])
            return
        }
        guard let roomId = json["roomId"] as? String,
              let roomUUID = UUID(uuidString: roomId) else { return }
        
        // Clear from persistence
        persistenceManager.clearMessages(for: roomUUID)
        
        // Clear from in-memory storage
        roomMessages.removeValue(forKey: roomId)
        
        let message = [
            "type": "chatHistoryCleared",
            "roomId": roomId
        ] as [String: Any]
        
        broadcastToRoom(roomId, message: message)
    }
    
    private func handleRemoveRoom(_ json: [String: Any], client: WebSocketClient) {
        guard client.username == adminUsername else {
            sendToClient(client, message: ["type": "error", "message": "Only an admin can remove rooms."])
            return
        }
        guard let roomId = json["roomId"] as? String,
              let room = rooms[roomId],
              room.name.lowercased() != "lobby" else {
            print("[RemoveRoom] Attempted to remove Lobby or invalid room.")
            return
        }
        print("[RemoveRoom] Removing room: \(room.name) (\(roomId))")
        // Remove from memory and persistence
        rooms.removeValue(forKey: roomId)
        roomMessages.removeValue(forKey: roomId)
        persistenceManager.deleteRoom(room.id)
        print("[RemoveRoom] Room removed from memory and persistence. Broadcasting...")
        // Broadcast to all clients
        broadcast([
            "type": "roomRemoved",
            "roomId": roomId
        ])
        print("[RemoveRoom] Broadcast sent.")
    }
    
    private func handlePing(_ json: [String: Any], client: WebSocketClient) {
        // Respond to client ping with pong
        sendToClient(client, message: ["type": "pong"])
    }
    
    private func handlePong(_ json: [String: Any], client: WebSocketClient) {
        // Client responded to our ping - connection is healthy
        // We could store last pong time here if we wanted to implement server-side health checks too
        // For now, just acknowledge that the client is responding
    }
    
    private func handleUpdateEmoji(_ json: [String: Any], client: WebSocketClient) {
        guard let username = client.username,
              let newEmoji = json["emoji"] as? String else { return }
        
        // Update stored emoji
        let success = webServer.webAuthnManager.updateUserEmoji(username: username, emoji: newEmoji)
        if success {
            userEmojis[username] = newEmoji
            
            // Send confirmation to client
            sendToClient(client, message: [
                "type": "emojiUpdated",
                "emoji": newEmoji,
                "success": true
            ])
            
            print("[WebChatServer] ✅ Updated emoji for \(username) to \(newEmoji)")
        } else {
            sendToClient(client, message: [
                "type": "emojiUpdated",
                "success": false,
                "error": "Failed to update emoji"
            ])
        }
    }
    
    // MARK: - Helper Methods
    
    private func leaveUserFromRoom(username: String, roomId: String) {
        guard var room = rooms[roomId] else { return }
        
        let user = User(username: username)
        room.removeParticipant(user)
        rooms[roomId] = room
    }
    
    private func broadcastToRoom(_ roomId: String, message: [String: Any], excludeUser: String? = nil) {
        let messageData = try! JSONSerialization.data(withJSONObject: message)
        let messageString = String(data: messageData, encoding: .utf8)!
        
        for (username, client) in users {
            if userRooms[username] == roomId && username != excludeUser {
                client.send(messageString)
            }
        }
    }
    
    private func broadcast(_ message: [String: Any]) {
        let messageData = try! JSONSerialization.data(withJSONObject: message)
        let messageString = String(data: messageData, encoding: .utf8)!
        
        webServer.broadcast(messageString)
    }
    
    private func sendToClient(_ client: WebSocketClient, message: [String: Any]) {
        let messageData = try! JSONSerialization.data(withJSONObject: message)
        let messageString = String(data: messageData, encoding: .utf8)!
        
        client.send(messageString)
    }
    
    private func broadcastUserCount() {
        broadcast([
            "type": "userCount",
            "count": users.count
        ])
    }
    
    private func roomToDict(_ room: Room) -> [String: Any] {
        return [
            "id": room.id.uuidString,
            "name": room.name,
            "createdAt": ISO8601DateFormatter().string(from: room.createdAt),
            "participantCount": room.participants.count,
            "createdBy": room.createdBy.username
        ]
    }
    
    private func getServerAddress() -> String {
        return rpId
    }
} 
