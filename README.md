# MultiPeerChatCore

[![Swift Package Manager compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-iOS%2017+-blue.svg?style=flat)](https://developer.apple.com/ios/)
[![Platform](https://img.shields.io/badge/platform-macOS%2014+-blue.svg?style=flat)](https://developer.apple.com/macos/)

A comprehensive Swift framework for building secure, peer-to-peer chat applications with advanced features including WebAuthn authentication, file sharing, and web-based administration.

## 🚀 Features

### Core Chat Features
- **Peer-to-peer messaging** with real-time communication
- **Room-based chat** with user management
- **File sharing** with automatic thumbnails for images
- **Invite link system** with expiration support
- **User presence tracking** and connection status

### Security & Authentication  
- **WebAuthn integration** using DogTagKit for passwordless authentication
- **Admin management** with session-based security
- **Secure file uploads** with type validation and size limits
- **IP tracking** and session management

### Web Interface
- **Full-featured web server** with WebSocket support
- **Admin dashboard** for user and system management
- **Real-time chat interface** accessible via web browser
- **File upload/download** through web interface

### Network & Storage
- **TCP-based networking** with Bonjour service discovery
- **Persistent storage** with WebAuthn credential management
- **Connection pooling** and automatic reconnection
- **Multi-platform support** (iOS 17+, macOS 14+)

## 📋 Requirements

- **Swift 5.9+**
- **iOS 17.0+** / **macOS 14.0+**
- **Xcode 15.0+**

## 📦 Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/MultiPeerChatCore.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Select version requirements

## 🛠 Quick Start

### Basic Chat Setup

```swift
import MultiPeerChatCore

// Initialize the chat client
let chatClient = ChatClient()

// Set up the user
chatClient.setUsername("Alice")

// Start networking
chatClient.startListening() // Start as server
// or
chatClient.connectToHost("192.168.1.100", port: 8080) // Connect as client

// Create and join a room
if let room = chatClient.createRoom(name: "General") {
    chatClient.joinRoom(room)
}

// Send messages
chatClient.sendMessage("Hello everyone!")

// Listen for connection status
chatClient.$isConnected
    .sink { isConnected in
        print("Connection status: \(isConnected)")
    }
    .store(in: &cancellables)

// Listen for new messages
chatClient.$messages
    .sink { messages in
        for message in messages {
            print("\(message.sender.username): \(message.content)")
        }
    }
    .store(in: &cancellables)
```

### Room Management

```swift
// Create a room
let room = chatClient.createRoom(name: "Project Discussion")

// Join an existing room
chatClient.joinRoom(room)

// Create invite links
let inviteLink = chatClient.createInviteLink(for: room, expiresIn: 3600) // 1 hour
print("Invite code: \(inviteLink.inviteCode)")

// Join with invite code
let success = chatClient.joinRoomWithInviteCode("ABC123")

// Leave room
chatClient.leaveRoom()
```

### File Sharing

```swift
// Send a file
let fileURL = URL(fileURLWithPath: "/path/to/document.pdf")
try chatClient.sendFile(fileURL)

// Handle file uploads via web interface
let fileManager = ChatFileManager.shared

// Save uploaded file data
let attachment = try fileManager.saveUploadedFile(
    data: fileData,
    originalFileName: "document.pdf",
    mimeType: "application/pdf"
)

// Retrieve file data
let data = try fileManager.getFileData(for: attachment)
```

## 🌐 Web Server Integration

### Basic Web Server Setup

```swift
// Initialize web server with WebAuthn
let webServer = WebServer(
    rpId: "localhost",
    port: 8080,
    adminUsername: "admin"
)

// Start the server
webServer.start(on: 8080)

// Check server status
webServer.$isRunning
    .sink { isRunning in
        print("Web server running: \(isRunning)")
    }
    .store(in: &cancellables)

// Monitor connected clients
webServer.$connectedClients
    .sink { count in
        print("Connected clients: \(count)")
    }
    .store(in: &cancellables)
```

### WebAuthn Authentication

```swift
// The WebAuthn system is automatically configured
// Users can register and authenticate through the web interface

// Access admin interface
// Navigate to: http://localhost:8080/admin

// For programmatic access to WebAuthn manager:
let webAuthnManager = webServer.webAuthnManager

// Check if admin user exists
let hasAdmin = webAuthnManager.hasAdminUser()

// List registered users
let users = webAuthnManager.listUsers()
```

## 🔧 Advanced Configuration

### Network Manager

```swift
let networkManager = NetworkManager()

// Start listening on specific port
networkManager.startListening(on: 8080)

// Connect to specific host
networkManager.connectToHost("192.168.1.100", port: 8080)

// Handle network events
class MyNetworkDelegate: NetworkManagerDelegate {
    func networkManager(_ manager: NetworkManager, didReceiveMessage message: NetworkMessage, from peer: NWConnection) {
        // Handle incoming messages
    }
    
    func networkManager(_ manager: NetworkManager, didConnectToPeer peer: NWConnection) {
        print("Connected to peer")
    }
    
    func networkManager(_ manager: NetworkManager, didDisconnectFromPeer peer: NWConnection) {
        print("Disconnected from peer")
    }
}

networkManager.delegate = MyNetworkDelegate()
```

### Persistence Management

```swift
let persistenceManager = PersistenceManager.shared

// Save and retrieve messages
persistenceManager.saveMessage(message)
let savedMessages = persistenceManager.fetchMessages()

// WebAuthn credential storage
persistenceManager.saveCredential(credential, for: "username")
let credential = persistenceManager.getCredential(for: "username")
```

### File Management Configuration

```swift
let fileManager = ChatFileManager.shared

// Supported file types and limits
print("Max file size: \(ChatFileManager.maxFileSize / 1024 / 1024) MB")
print("Allowed image types: \(ChatFileManager.allowedImageTypes)")
print("All allowed types: \(ChatFileManager.allowedFileTypes)")

// Handle file operations
do {
    let attachment = try fileManager.saveUploadedFile(
        data: fileData,
        originalFileName: "image.jpg",
        mimeType: "image/jpeg"
    )
    
    // Get thumbnail for images
    if let thumbnailData = try fileManager.getThumbnailData(for: attachment) {
        // Use thumbnail data
    }
} catch FileError.fileTooLarge {
    print("File exceeds size limit")
} catch FileError.unsupportedFileType {
    print("File type not supported")
}
```

## 🏗 Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ChatClient    │    │   WebServer     │    │ NetworkManager  │
│                 │    │                 │    │                 │
│ • User mgmt     │    │ • HTTP server   │    │ • TCP/Bonjour   │
│ • Room mgmt     │    │ • WebSocket     │    │ • Peer-to-peer  │
│ • Messages      │    │ • WebAuthn      │    │ • Connection    │
│ • File sharing  │    │ • Admin UI      │    │   management    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │ PersistenceManager │
                    │                 │
                    │ • Data storage  │
                    │ • WebAuthn creds│
                    │ • Message history│
                    └─────────────────┘
```

## 🔒 Security Features

- **WebAuthn passwordless authentication** using FIDO2 standards
- **Session management** with configurable timeouts
- **IP tracking** and access logging
- **File type validation** and size restrictions
- **Secure credential storage** with encryption
- **Admin privilege separation**

## 🌐 Web Interface

The framework includes a complete web interface accessible at `http://localhost:port/`:

- **`/`** - Main chat interface
- **`/admin`** - Administrative dashboard (requires WebAuthn)
- **`/api/webauthn/*`** - WebAuthn authentication endpoints
- **`/uploads/*`** - File serving endpoints

## 🧪 Testing

```bash
# Run all tests
swift test

# Run specific test targets
swift test --filter MultiPeerChatTests
swift test --filter WebAuthnIntegrationTests
```

## 📖 API Reference

### Core Classes

- **`ChatClient`** - Main client interface for chat functionality
- **`WebServer`** - HTTP/WebSocket server with admin interface  
- **`NetworkManager`** - Low-level networking and peer management
- **`AdminManager`** - Administrative functions and security
- **`ChatFileManager`** - File upload, storage, and serving
- **`PersistenceManager`** - Data persistence and WebAuthn storage

### Key Models

- **`User`** - Represents a chat user with ID, username, and emoji
- **`Room`** - Chat room with participants and metadata
- **`ChatMessage`** - Individual message with sender, content, and type
- **`FileAttachment`** - File metadata with path and thumbnail info
- **`ChatLink`** - Invite link with expiration and access control

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/MultiPeerChatCore.git
cd MultiPeerChatCore

# Open in Xcode
open Package.swift
```

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

## 🙏 Acknowledgments

- [DogTagKit](https://github.com/webauthnai/DogTagKit) - WebAuthn implementation
- Swift NIO for networking foundations
- The Swift Package Manager community

---

**MultiPeerChatCore** - Building the future of decentralized communication 🚀
