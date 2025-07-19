// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import Network

public protocol NetworkManagerDelegate: AnyObject {
    func networkManager(_ manager: NetworkManager, didReceiveMessage message: NetworkMessage, from peer: NWConnection)
    func networkManager(_ manager: NetworkManager, didConnectToPeer peer: NWConnection)
    func networkManager(_ manager: NetworkManager, didDisconnectFromPeer peer: NWConnection)
    func networkManager(_ manager: NetworkManager, didStartListening on: NWListener)
    func networkManager(_ manager: NetworkManager, didFailWithError error: Error)
}

public class NetworkManager: ObservableObject {
    public weak var delegate: NetworkManagerDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "NetworkManager", qos: .userInitiated)
    private let serviceName = "multipeer-chat"
    private let serviceType = "_multipeer-chat._tcp"
    
    @Published public var isListening = false
    @Published public var connectedPeers: [String] = []
    
    public init() {}
    
    // MARK: - Server Functions
    
    public func startListening(on port: UInt16 = 0) {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            // Enable Bonjour for service discovery
            let tcpOptions = NWProtocolTCP.Options()
            parameters.defaultProtocolStack.transportProtocol = tcpOptions
            
            if port == 0 {
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            }
            
            listener?.service = NWListener.Service(name: serviceName, type: serviceType)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.delegate?.networkManager(self, didStartListening: self.listener!)
                        print("🟢 Server listening on port: \(self.listener?.port?.rawValue ?? 0)")
                    case .failed(let error):
                        self.isListening = false
                        self.delegate?.networkManager(self, didFailWithError: error)
                        print("🔴 Server failed: \(error)")
                    case .cancelled:
                        self.isListening = false
                        print("🟡 Server cancelled")
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: queue)
            
        } catch {
            delegate?.networkManager(self, didFailWithError: error)
            print("🔴 Failed to start listener: \(error)")
        }
    }
    
    public func stopListening() {
        listener?.cancel()
        listener = nil
        
        // Close all connections
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        DispatchQueue.main.async {
            self.isListening = false
            self.connectedPeers.removeAll()
        }
    }
    
    // MARK: - Client Functions
    
    public func connectToPeer(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let parameters = NWParameters.tcp
        
        let connection = NWConnection(to: endpoint, using: parameters)
        setupConnection(connection)
        connection.start(queue: queue)
    }
    
    public func discoverAndConnect() {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)
        
        browser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) in
            for result in results {
                if case .service(let name, let type, let domain, _) = result.endpoint {
                    print("🔍 Found service: \(name) of type: \(type) in domain: \(domain)")
                    
                    // Connect to the first available service
                    let connection = NWConnection(to: result.endpoint, using: .tcp)
                    self?.setupConnection(connection)
                    connection.start(queue: self?.queue ?? DispatchQueue.global())
                    break
                }
            }
        }
        
        browser.stateUpdateHandler = { (state: NWBrowser.State) in
            switch state {
            case .ready:
                print("🔍 Browser ready")
            case .failed(let error):
                print("🔴 Browser failed: \(error)")
            default:
                break
            }
        }
        
        browser.start(queue: queue)
    }
    
    // MARK: - Message Sending
    
    public func sendMessage(_ message: NetworkMessage, to connection: NWConnection? = nil) {
        guard let data = message.data else {
            print("🔴 Failed to encode message")
            return
        }
        
        let messageData = withUnsafeBytes(of: UInt32(data.count).bigEndian) { Data($0) } + data
        
        if let connection = connection {
            sendData(messageData, to: connection)
        } else {
            // Broadcast to all connections
            for connection in connections {
                sendData(messageData, to: connection)
            }
        }
    }
    
    private func sendData(_ data: Data, to connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("🔴 Failed to send data: \(error)")
            }
        })
    }
    
    // MARK: - Connection Management
    
    private func handleNewConnection(_ connection: NWConnection) {
        setupConnection(connection)
        connection.start(queue: queue)
    }
    
    private func setupConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.delegate?.networkManager(self, didConnectToPeer: connection)
                    self.updateConnectedPeers()
                    print("🟢 Connected to peer: \(connection.endpoint)")
                case .failed(let error):
                    self.removeConnection(connection)
                    self.delegate?.networkManager(self, didFailWithError: error)
                    self.updateConnectedPeers()
                    print("🔴 Connection failed: \(error)")
                case .cancelled:
                    self.removeConnection(connection)
                    self.delegate?.networkManager(self, didDisconnectFromPeer: connection)
                    self.updateConnectedPeers()
                    print("🟡 Connection cancelled: \(connection.endpoint)")
                default:
                    break
                }
            }
        }
        
        receiveMessage(from: connection)
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
    
    private func receiveMessage(from connection: NWConnection) {
        // First, receive the message length (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("🔴 Error receiving message length: \(error)")
                return
            }
            
            guard let data = data, data.count == 4 else {
                print("🔴 Invalid message length data")
                return
            }
            
            let messageLength = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // Now receive the actual message
            connection.receive(minimumIncompleteLength: Int(messageLength), maximumLength: Int(messageLength)) { messageData, _, isComplete, error in
                if let error = error {
                    print("🔴 Error receiving message: \(error)")
                    return
                }
                
                guard let messageData = messageData,
                      let message = NetworkMessage.from(data: messageData) else {
                    print("🔴 Failed to decode message")
                    return
                }
                
                DispatchQueue.main.async {
                    self.delegate?.networkManager(self, didReceiveMessage: message, from: connection)
                }
                
                // Continue receiving messages
                self.receiveMessage(from: connection)
            }
        }
    }
    
    private func updateConnectedPeers() {
        connectedPeers = connections.map { "\($0.endpoint)" }
    }
    
    public var listeningPort: UInt16? {
        return listener?.port?.rawValue
    }
} 
