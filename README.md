# MultiPeerChatCore

MultiPeerChatCore is a Swift-based peer-to-peer chat and file sharing framework that provides secure, decentralized communication capabilities.

## Features

- Peer-to-peer chat functionality
- Secure file sharing
- WebAuthn authentication
- Web-based admin interface
- Persistent message storage
- Network management

## Requirements

- Swift 5.5+
- iOS 14.0+ / macOS 11.0+
- Xcode 13.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/MultiPeerChatCore.git", from: "1.0.0")
]
```

## Usage

### Basic Chat Client Setup

```swift
import MultiPeerChatCore

// Initialize the chat client
let chatClient = ChatClient()

// Connect to the network
chatClient.connect()

// Send a message
chatClient.sendMessage("Hello, peer network!")

// Receive messages
chatClient.onMessageReceived { message in
    print("Received message: \(message)")
}
```

### File Sharing

```swift
// Send a file to peers
let fileURL = URL(fileURLWithPath: "/path/to/file")
chatClient.sendFile(fileURL)

// Handle incoming files
chatClient.onFileReceived { fileURL in
    print("Received file at: \(fileURL)")
}
```

### WebAuthn Authentication

```swift
// Perform WebAuthn registration
let adminManager = AdminManager()
adminManager.registerWebAuthnCredential { result in
    switch result {
    case .success(let credential):
        print("Registered credential: \(credential)")
    case .failure(let error):
        print("Registration failed: \(error)")
    }
}
```

### Web Admin Interface

The framework includes a web-based admin interface for managing chat settings and monitoring network activity. Access it through the provided web server.

```swift
let webServer = WebServer()
webServer.start()
// Access admin interface at http://localhost:8080/admin
```

## Advanced Configuration

### Network Configuration

```swift
let networkManager = NetworkManager()
networkManager.configureNetwork(
    serviceType: "chat-service",
    discoveryInfo: ["username": "CurrentUser"]
)
```

### Persistence

```swift
let persistenceManager = PersistenceManager()
persistenceManager.saveMessage(message)
let messages = persistenceManager.fetchMessages()
```

## Security

- Utilizes WebAuthn for secure authentication
- Peer-to-peer encryption
- Secure file transfer mechanisms

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

Distributed under the MIT License. See `LICENSE` for more information.
