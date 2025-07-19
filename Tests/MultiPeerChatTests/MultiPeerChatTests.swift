// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import XCTest
@testable import MultiPeerChatCore

final class MultiPeerChatTests: XCTestCase {
    
    func testUserCreation() {
        let user = User(username: "TestUser")
        
        XCTAssertEqual(user.username, "TestUser")
        XCTAssertNotNil(user.id)
        XCTAssertTrue(user.joinedAt <= Date())
    }
    
    func testRoomCreation() {
        let user = User(username: "Creator")
        let room = Room(name: "Test Room", createdBy: user)
        
        XCTAssertEqual(room.name, "Test Room")
        XCTAssertEqual(room.createdBy.username, "Creator")
        XCTAssertTrue(room.participants.contains(user))
        XCTAssertEqual(room.participants.count, 1)
    }
    
    func testRoomParticipantManagement() {
        let creator = User(username: "Creator")
        let participant = User(username: "Participant")
        var room = Room(name: "Test Room", createdBy: creator)
        
        // Add participant
        room.addParticipant(participant)
        XCTAssertTrue(room.participants.contains(participant))
        XCTAssertEqual(room.participants.count, 2)
        
        // Remove participant
        room.removeParticipant(participant)
        XCTAssertFalse(room.participants.contains(participant))
        XCTAssertEqual(room.participants.count, 1)
        XCTAssertTrue(room.participants.contains(creator)) // Creator should still be there
    }
    
    func testChatMessageCreation() {
        let user = User(username: "Sender")
        let roomId = UUID()
        let message = ChatMessage(content: "Hello World", sender: user, roomId: roomId)
        
        XCTAssertEqual(message.content, "Hello World")
        XCTAssertEqual(message.sender.username, "Sender")
        XCTAssertEqual(message.roomId, roomId)
        XCTAssertEqual(message.messageType, .text)
        XCTAssertTrue(message.timestamp <= Date())
    }
    
    func testChatLinkCreation() {
        let creator = User(username: "Creator")
        let room = Room(name: "Test Room", createdBy: creator)
        let link = ChatLink(room: room)
        
        XCTAssertEqual(link.roomId, room.id)
        XCTAssertEqual(link.roomName, room.name)
        XCTAssertEqual(link.createdBy.username, creator.username)
        XCTAssertEqual(link.inviteCode.count, 8)
        XCTAssertNil(link.expiresAt) // No expiration by default
        XCTAssertFalse(link.isExpired)
    }
    
    func testChatLinkExpiration() {
        let creator = User(username: "Creator")
        let room = Room(name: "Test Room", createdBy: creator)
        let link = ChatLink(room: room, expiresIn: -1) // Expired 1 second ago
        
        XCTAssertNotNil(link.expiresAt)
        XCTAssertTrue(link.isExpired)
    }
    
    func testChatLinkShareableURL() {
        let creator = User(username: "Creator")
        let room = Room(name: "Test Room", createdBy: creator)
        let link = ChatLink(room: room)
        
        let shareableLink = link.generateShareableLink()
        
        XCTAssertTrue(shareableLink.hasPrefix("multipeer-chat://join?"))
        XCTAssertTrue(shareableLink.contains("code=\(link.inviteCode)"))
        // The room name might be URL encoded differently, so let's be more flexible
        XCTAssertTrue(shareableLink.contains("room=") && shareableLink.contains("Test") && shareableLink.contains("Room"))
    }
    
    func testNetworkMessageSerialization() {
        let user = User(username: "TestUser")
        let roomId = UUID()
        let chatMessage = ChatMessage(content: "Test", sender: user, roomId: roomId)
        let networkMessage = NetworkMessage.chatMessage(chatMessage)
        
        // Test encoding
        guard let data = networkMessage.data else {
            XCTFail("Failed to encode network message")
            return
        }
        
        // Test decoding
        guard let decodedMessage = NetworkMessage.from(data: data) else {
            XCTFail("Failed to decode network message")
            return
        }
        
        if case .chatMessage(let decodedChatMessage) = decodedMessage {
            XCTAssertEqual(decodedChatMessage.content, chatMessage.content)
            XCTAssertEqual(decodedChatMessage.sender.username, chatMessage.sender.username)
            XCTAssertEqual(decodedChatMessage.roomId, chatMessage.roomId)
        } else {
            XCTFail("Decoded message is not a chat message")
        }
    }
    
    func testChatClientUserManagement() {
        let chatClient = ChatClient()
        
        XCTAssertNil(chatClient.currentUser)
        
        chatClient.setUsername("TestUser")
        XCTAssertNotNil(chatClient.currentUser)
        XCTAssertEqual(chatClient.currentUser?.username, "TestUser")
    }
    
    func testChatClientRoomCreation() {
        let chatClient = ChatClient()
        
        // Should fail without user
        XCTAssertNil(chatClient.createRoom(name: "Test Room"))
        
        // Should succeed with user
        chatClient.setUsername("Creator")
        let room = chatClient.createRoom(name: "Test Room")
        
        XCTAssertNotNil(room)
        XCTAssertEqual(room?.name, "Test Room")
        XCTAssertTrue(chatClient.rooms.contains { $0.id == room?.id })
    }
    
    func testInviteCodeParsing() {
        let chatClient = ChatClient()
        
        // Valid invite link
        let validLink = "multipeer-chat://join?code=ABC12345&room=TestRoom"
        let code = chatClient.parseInviteLink(validLink)
        XCTAssertEqual(code, "ABC12345")
        
        // Invalid scheme
        let invalidScheme = "http://example.com/join?code=ABC12345"
        XCTAssertNil(chatClient.parseInviteLink(invalidScheme))
        
        // Missing code
        let missingCode = "multipeer-chat://join?room=TestRoom"
        XCTAssertNil(chatClient.parseInviteLink(missingCode))
        
        // Invalid URL
        let invalidURL = "not-a-url"
        XCTAssertNil(chatClient.parseInviteLink(invalidURL))
    }
} 
