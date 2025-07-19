// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import Network
import Combine

public class ChatClient: ObservableObject, NetworkManagerDelegate {
    @Published public var currentUser: User?
    @Published public var rooms: [Room] = []
    @Published public var currentRoom: Room?
    @Published public var messages: [ChatMessage] = []
    @Published public var isConnected = false
    @Published public var connectionStatus = "Disconnected"
    @Published public var inviteLinks: [ChatLink] = []
    
    private let networkManager = NetworkManager()
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        networkManager.delegate = self
        
        // Observe network manager state
        networkManager.$isListening
            .sink { [weak self] isListening in
                self?.isConnected = isListening || !(self?.networkManager.connectedPeers.isEmpty ?? true)
                self?.updateConnectionStatus()
            }
            .store(in: &cancellables)
        
        networkManager.$connectedPeers
            .sink { [weak self] peers in
                self?.isConnected = !peers.isEmpty || (self?.networkManager.isListening ?? false)
                self?.updateConnectionStatus()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - User Management
    
    public func setUsername(_ username: String) {
        currentUser = User(username: username)
    }
    
    // MARK: - Room Management
    
    public func createRoom(name: String) -> Room? {
        guard let user = currentUser else { return nil }
        
        let room = Room(name: name, createdBy: user)
        rooms.append(room)
        
        // Broadcast room creation
        networkManager.sendMessage(.roomCreated(room))
        
        // Add system message
        let systemMessage = ChatMessage(
            content: "Room '\(name)' created",
            sender: user,
            roomId: room.id,
            messageType: .roomCreated
        )
        messages.append(systemMessage)
        
        return room
    }
    
    public func joinRoom(_ room: Room) {
        guard let user = currentUser else { return }
        
        currentRoom = room
        
        // Add user to room if not already present
        if !room.participants.contains(user) {
            if let index = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[index].addParticipant(user)
            }
            
            // Broadcast join
            networkManager.sendMessage(.joinRoom(room.id, user))
            
            // Add system message
            let systemMessage = ChatMessage(
                content: "\(user.username) joined the room",
                sender: user,
                roomId: room.id,
                messageType: .userJoined
            )
            messages.append(systemMessage)
        }
        
        // Filter messages for current room
        filterMessagesForCurrentRoom()
    }
    
    public func leaveRoom() {
        guard let user = currentUser, let room = currentRoom else { return }
        
        // Remove user from room
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index].removeParticipant(user)
        }
        
        // Broadcast leave
        networkManager.sendMessage(.leaveRoom(room.id, user))
        
        // Add system message
        let systemMessage = ChatMessage(
            content: "\(user.username) left the room",
            sender: user,
            roomId: room.id,
            messageType: .userLeft
        )
        messages.append(systemMessage)
        
        currentRoom = nil
        messages.removeAll()
    }
    
    // MARK: - Message Management
    
    public func sendMessage(_ content: String) {
        guard let user = currentUser, let room = currentRoom else { return }
        
        let message = ChatMessage(content: content, sender: user, roomId: room.id)
        messages.append(message)
        
        // Broadcast message
        networkManager.sendMessage(.chatMessage(message))
    }
    
    private func filterMessagesForCurrentRoom() {
        guard let roomId = currentRoom?.id else {
            messages.removeAll()
            return
        }
        
        messages = messages.filter { $0.roomId == roomId }
    }
    
    // MARK: - Invite Link Management
    
    public func createInviteLink(for room: Room, expiresIn: TimeInterval? = nil) -> ChatLink {
        let link = ChatLink(room: room, expiresIn: expiresIn)
        inviteLinks.append(link)
        return link
    }
    
    public func joinRoomWithInviteCode(_ code: String) -> Bool {
        guard let link = inviteLinks.first(where: { $0.inviteCode == code && !$0.isExpired }),
              let room = rooms.first(where: { $0.id == link.roomId }) else {
            return false
        }
        
        joinRoom(room)
        return true
    }
    
    public func parseInviteLink(_ urlString: String) -> String? {
        guard let url = URL(string: urlString),
              url.scheme == "multipeer-chat",
              url.host == "join",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let code = queryItems.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        
        return code
    }
    
    // MARK: - Network Management
    
    public func startHosting(on port: UInt16 = 0) {
        networkManager.startListening(on: port)
    }
    
    public func stopHosting() {
        networkManager.stopListening()
    }
    
    public func connectToPeer(host: String, port: UInt16) {
        networkManager.connectToPeer(host: host, port: port)
    }
    
    public func discoverPeers() {
        networkManager.discoverAndConnect()
    }
    
    public var listeningPort: UInt16? {
        return networkManager.listeningPort
    }
    
    private func updateConnectionStatus() {
        if networkManager.isListening {
            connectionStatus = "Hosting on port \(networkManager.listeningPort ?? 0)"
        } else if !networkManager.connectedPeers.isEmpty {
            connectionStatus = "Connected to \(networkManager.connectedPeers.count) peer(s)"
        } else {
            connectionStatus = "Disconnected"
        }
    }
    
    // MARK: - NetworkManagerDelegate
    
    public func networkManager(_ manager: NetworkManager, didReceiveMessage message: NetworkMessage, from peer: NWConnection) {
        switch message {
        case .chatMessage(let chatMessage):
            // Only add message if it's for the current room or if we don't have a current room
            if currentRoom?.id == chatMessage.roomId || currentRoom == nil {
                messages.append(chatMessage)
            }
            
        case .userJoined(let user, let roomId):
            if let index = rooms.firstIndex(where: { $0.id == roomId }) {
                rooms[index].addParticipant(user)
            }
            
        case .userLeft(let user, let roomId):
            if let index = rooms.firstIndex(where: { $0.id == roomId }) {
                rooms[index].removeParticipant(user)
            }
            
        case .roomCreated(let room):
            if !rooms.contains(where: { $0.id == room.id }) {
                rooms.append(room)
            }
            
        case .roomList(let roomList):
            // Merge with existing rooms
            for room in roomList {
                if !rooms.contains(where: { $0.id == room.id }) {
                    rooms.append(room)
                }
            }
            
        case .joinRoom(let roomId, let user):
            if let index = rooms.firstIndex(where: { $0.id == roomId }) {
                rooms[index].addParticipant(user)
            }
            
        case .leaveRoom(let roomId, let user):
            if let index = rooms.firstIndex(where: { $0.id == roomId }) {
                rooms[index].removeParticipant(user)
            }
            
        case .ping:
            manager.sendMessage(.pong, to: peer)
            
        case .pong:
            // Handle pong if needed
            break
        }
    }
    
    public func networkManager(_ manager: NetworkManager, didConnectToPeer peer: NWConnection) {
        // Send current room list to new peer
        if !rooms.isEmpty {
            manager.sendMessage(.roomList(rooms), to: peer)
        }
        
        // Send current user info if in a room
        if let user = currentUser, let room = currentRoom {
            manager.sendMessage(.joinRoom(room.id, user), to: peer)
        }
    }
    
    public func networkManager(_ manager: NetworkManager, didDisconnectFromPeer peer: NWConnection) {
        // Handle peer disconnection
    }
    
    public func networkManager(_ manager: NetworkManager, didStartListening on: NWListener) {
        // Handle listening started
    }
    
    public func networkManager(_ manager: NetworkManager, didFailWithError error: Error) {
        print("🔴 Network error: \(error)")
    }
} 
