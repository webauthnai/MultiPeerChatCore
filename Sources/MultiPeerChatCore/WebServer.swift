// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import Network
import CommonCrypto
import CoreGraphics
import CoreText
import ImageIO
import DogTagKit

// MARK: - String Extension for Regex Matching
extension String {
    func matches(_ pattern: String) -> Bool {
        return range(of: pattern, options: .regularExpression) != nil
    }
}

public protocol WebServerDelegate: AnyObject {
    func webServer(_ server: WebServer, didReceiveMessage message: String, from client: WebSocketClient)
    func webServer(_ server: WebServer, clientDidConnect client: WebSocketClient)
    func webServer(_ server: WebServer, clientDidDisconnect client: WebSocketClient)
}

public class WebServer: ObservableObject, AdminManagerDelegate {
    public weak var delegate: WebServerDelegate?
    
    private var listener: NWListener?
    private var clients: [WebSocketClient] = []
    private let queue = DispatchQueue(label: "WebServer", qos: .userInitiated)
    
    @Published public var isRunning = false
    @Published public var connectedClients: Int = 0
    
    private let rpId: String
    private let adminUsername: String
    public let webAuthnManager: WebAuthnManager // Changed from private to public
    private let webAuthnServer: WebAuthnServer
    private let port: UInt16?
    
    // Manager for admin operations
    private let adminManager: AdminManager
    private let webAuthAdminManager: WebAuthAdminManager
    
    public init(rpId: String, port: UInt16? = nil, adminUsername: String = "XCF Admin", storageBackend: WebAuthnStorageBackend = .json(""), existingWebAuthnManager: WebAuthnManager? = nil) {
        self.rpId = rpId
        self.adminUsername = adminUsername
        self.port = port
        
        // Use existing WebAuthn manager if provided, otherwise create a new one
        if let existingManager = existingWebAuthnManager {
            self.webAuthnManager = existingManager
            print("[WebServer] 🔄 Reusing existing WebAuthnManager (avoiding duplicate initialization)")
        } else {
            // Try using a publicly accessible icon for better compatibility
            // For localhost, include the port number in the URL
            let iconUrl: String
            if rpId.lowercased() == "localhost", let port = port {
                iconUrl = "http://localhost:\(port)/icon-192.png"
            } else {
                iconUrl = "https://ui-avatars.com/api/?name=💬Chat&background=007AFF&color=white&size=192&format=png"
            }
            
            self.webAuthnManager = WebAuthnManager(
                rpId: rpId,
                storageBackend: storageBackend,
                rpName: "Multi-Peer Chat",
                rpIcon: iconUrl,
                defaultUserIcon: nil, // Will use the automatic generation
                adminUsername: adminUsername,
                userManager: PersistenceManager.shared
            )
        }
        
        self.webAuthnServer = WebAuthnServer(manager: webAuthnManager)
        
        // Initialize managers
        self.adminManager = AdminManager(adminUsername: adminUsername)
        self.webAuthAdminManager = WebAuthAdminManager(webAuthnManager: webAuthnManager, adminUsername: adminUsername)
        
        // Set up admin manager delegation
        self.adminManager.delegate = self
        
        // Only bootstrap admin user when creating a fresh WebAuthn manager
        // This prevents duplicate admin checks when reusing an existing manager
        if existingWebAuthnManager == nil {
            webAuthAdminManager.bootstrapAdminUser()
        }
    }
    

    
    public func start(on port: UInt16) {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            // Set socket options for port reuse
            if let options = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                options.version = .v4
                options.hopLimit = 64
            }
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("🌐 Web server listening on port \(port)")
                    case .failed(let error):
                        self?.isRunning = false
                        if error == .posix(.EADDRINUSE) {
                            print("🔴 Port \(port) is already in use. Please choose a different port.")
                            exit(1)
                        } else {
                            print("🔴 Web server failed: \(error)")
                        }
                    case .cancelled:
                        self?.isRunning = false
                        print("🟡 Web server stopped")
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: queue)
            
            // Start periodic cleanup of expired admin sessions
            startPeriodicCleanup()
            
        } catch let error as NWError {
            if error == .posix(.EADDRINUSE) {
                print("🔴 Port \(port) is already in use. Please choose a different port.")
                exit(1)
            } else {
                print("🔴 Failed to start web server: \(error)")
            }
        } catch {
            print("🔴 Failed to start web server: \(error)")
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        
        for client in clients {
            client.disconnect()
        }
        clients.removeAll()
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
        }
    }
    
    public func broadcast(_ message: String) {
        for client in clients {
            client.send(message)
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        // Read the HTTP request headers first
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data else { return }
            
            // First check if this might be a binary upload by looking at the headers only
            let headerEndMarker = "\r\n\r\n".data(using: .utf8)!
            
            if let headerEndRange = data.range(of: headerEndMarker) {
                let headerData = data.subdata(in: 0..<headerEndRange.upperBound)
                if let headerString = String(data: headerData, encoding: .utf8) {
                    print("🔍 HEADER CHECK - Length: \(headerString.count)")
                    // Only check for uploads on POST requests with multipart data
                    if headerString.contains("POST /upload") || (headerString.contains("POST ") && headerString.lowercased().contains("multipart/form-data")) {
                        print("📤 Binary upload detected - using special binary handling")
                        self.handleFileUploadBinary(connection, initialData: data, headerString: headerString)
                        return
                    }
                }
            }
            
            let request = String(data: data, encoding: .utf8) ?? ""
            
            // Add comprehensive debugging for Cloudflare issues
            print("🔍 RAW REQUEST DATA (first 500 chars):")
            print(String(request.prefix(500)))
            print("🔍 REQUEST LENGTH: \(request.count)")
            
            // Parse request line to extract method and path
            let lines = request.components(separatedBy: "\r\n")
            let requestLine = lines.first ?? ""
            print("🔍 REQUEST LINE: '\(requestLine)'")
            let components = requestLine.components(separatedBy: " ")
            print("🔍 REQUEST COMPONENTS: \(components)")
            let method = components.count > 0 ? components[0] : ""
            let path = components.count > 1 ? components[1] : ""
            
            // Add logging for debugging Cloudflare issues
            print("🌐 Received request: \(method) \(path)")
            if method == "POST" && path == "/upload" {
                print("📤 Upload request detected - using special handling")
            }
            
            // Check for multipart upload regardless of path
            let isMultipartUpload = request.lowercased().contains("content-type: multipart/form-data")
            if isMultipartUpload {
                print("📤 Multipart upload detected by Content-Type")
            }
            
            if request.contains("Upgrade: websocket") {
                // Handle WebSocket upgrade
                self.handleWebSocketUpgrade(connection, request: request)
            } else if method == "OPTIONS" {
                // Handle CORS preflight
                self.handleCORSPreflight(connection, path: path)
            } else if request.starts(with: "POST") {
                // Handle POST requests: ensure we read the full body
                // Find Content-Length
                let lines = request.components(separatedBy: "\r\n")
                var contentLength: Int? = nil
                for line in lines {
                    if line.lowercased().hasPrefix("content-length:") {
                        let value = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).last?.trimmingCharacters(in: .whitespaces)
                        contentLength = Int(value ?? "")
                        break
                    }
                }
                guard let contentLength = contentLength else {
                    self.handleHTTPRequest(connection, request: request)
                    return
                }
                // Find where headers end
                guard let headerEndRange = data.range(of: "\r\n\r\n".data(using: .utf8)!) else {
                    self.handleHTTPRequest(connection, request: request)
                    return
                }
                let bodyStart = headerEndRange.upperBound
                let bodyBytesReceived = data.count - bodyStart
                if bodyBytesReceived >= contentLength {
                    // All body received
                    self.handleHTTPRequest(connection, request: request)
                } else {
                    // Need to read more
                    var fullData = data
                    func readMore() {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { moreData, _, _, _ in
                            if let moreData = moreData {
                                fullData.append(moreData)
                                let totalBodyBytes = fullData.count - bodyStart
                                if totalBodyBytes >= contentLength {
                                    let fullRequest = String(data: fullData, encoding: .utf8) ?? ""
                                    self.handleHTTPRequest(connection, request: fullRequest)
                                } else {
                                    readMore()
                                }
                            } else {
                                let fullRequest = String(data: fullData, encoding: .utf8) ?? ""
                                self.handleHTTPRequest(connection, request: fullRequest)
                            }
                        }
                    }
                    readMore()
                }
            } else {
                // Handle regular HTTP request
                self.handleHTTPRequest(connection, request: request)
            }
        }
    }
    
    private func handleHTTPRequest(_ connection: NWConnection, request: String) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let method = components[0]
        let path = components[1]
        
        let response: String
        let contentType: String
        var statusCode = "200 OK"
        
        switch (method, path) {
        case ("GET", "/"):
            response = generateIndexHTML()
            contentType = "text/html"
        case ("GET", "/chat.js"):
            response = generateChatJS()
            contentType = "application/javascript"
        case ("GET", "/webauthn.js"):
            response = generateWebAuthnJS()
            contentType = "application/javascript"
        case ("GET", "/webauthnui.js"):
            response = generateWebAuthnUIJS()
            contentType = "application/javascript"
        case ("GET", "/emoji.js"):
            response = generateEmojiJS()
            contentType = "application/javascript"
        case ("GET", "/style.css"):
            response = generateCSS()
            contentType = "text/css"
        case ("GET", "/webauthn.css"):
            response = generateWebAuthnCSS()
            contentType = "text/css"
        case ("GET", "/hybrid-webauthn-test.html"):
            response = generateHybridWebAuthnTestHTML()
            contentType = "text/html"
        case ("GET", "/webauthn-super-test.html"):
            response = generateWebAuthnSuperTestHTML()
            contentType = "text/html"
        case ("GET", "/webauthn-super-test.js"):
            response = generateWebAuthnSuperTestJS()
            contentType = "application/javascript"
        // Admin Routes - REQUIRES AUTHENTICATION
        case ("GET", "/admin/index.html"), ("GET", "/admin/"), ("GET", "/admin"):
            // ALWAYS show login page first - no exceptions
            response = generateAdminLoginHTML()
            contentType = "text/html"
        case ("GET", "/admin/panel.html"):
            // Only show admin panel if authenticated
            if adminManager.isValidAdminSession(request) {
                response = generateAdminIndexHTML()
                contentType = "text/html"
            } else {
                response = "404 Not Found"
                contentType = "text/plain"
                statusCode = "404 Not Found"
            }
        case ("GET", "/admin/login.html"):
            response = generateAdminLoginHTML()
            contentType = "text/html"
        case ("GET", "/admin/admin.css"):
            response = generateAdminCSS()
            contentType = "text/css"
        case ("GET", "/admin/admin.js"):
            if adminManager.isValidAdminSession(request) {
                response = generateAdminJS()
                contentType = "application/javascript"
            } else {
                response = "401 Unauthorized"
                contentType = "text/plain"
                statusCode = "401 Unauthorized"
            }
        case ("GET", "/admin/admin-login.js"):
            response = generateAdminLoginJS()
            contentType = "application/javascript"
        case ("POST", "/admin/api/login"):
            handleAdminLogin(connection, request: request)
            return
        case ("GET", "/admin/api/users"):
            if adminManager.isValidAdminSession(request) || adminManager.hasValidAdminSession(request) {
                handleAdminAPIUsers(connection, request: request)
                return
            } else {
                response = "401 Unauthorized"
                contentType = "text/plain"
                statusCode = "401 Unauthorized"
            }
        case ("POST", let path) where path.matches(#"/admin/api/users/[^/]+/toggle"#):
            if adminManager.isValidAdminSession(request) || adminManager.hasValidAdminSession(request) {
                handleAdminAPIToggleUser(connection, request: request, path: path)
                return
            } else {
                response = "404 Not Found"
                contentType = "text/plain"
                statusCode = "404 Not Found"
            }
        case ("DELETE", let path) where path.matches(#"/admin/api/users/[^/]+"#):
            if adminManager.isValidAdminSession(request) || adminManager.hasValidAdminSession(request) {
                handleAdminAPIDeleteUser(connection, request: request, path: path)
                return
            } else {
                response = "404 Not Found"
                contentType = "text/plain"
                statusCode = "404 Not Found"
            }
        case ("POST", "/admin/api/users/disable-by-ip"):
            if adminManager.isValidAdminSession(request) || adminManager.hasValidAdminSession(request) {
                handleAdminAPIDisableByIP(connection, request: request)
                return
            } else {
                response = "404 Not Found"
                contentType = "text/plain"
                statusCode = "404 Not Found"
            }
        case ("POST", let path) where path.matches(#"/admin/api/users/[^/]+/emoji"#):
            if adminManager.isValidAdminSession(request) || adminManager.hasValidAdminSession(request) {
                handleAdminAPIUpdateEmoji(connection, request: request, path: path)
                return
            } else {
                response = "404 Not Found"
                contentType = "text/plain"
                statusCode = "404 Not Found"
            }
        case ("POST", let path) where path.matches(#"/admin/api/users/[^/]+/admin"#):
            if adminManager.isValidAdminSession(request) || adminManager.hasValidAdminSession(request) {
                handleAdminAPIToggleAdmin(connection, request: request, path: path)
                return
            } else {
                response = "404 Not Found"
                contentType = "text/plain"
                statusCode = "404 Not Found"
            }
        case ("GET", "/manifest.json"):
            response = generateWebManifest()
            contentType = "application/json"
        case ("GET", "/browserconfig.xml"):
            response = generateBrowserConfig()
            contentType = "application/xml"
        case ("GET", "/favicon.ico"):
            handleFaviconRequest(connection)
            return
        case ("GET", "/favicon.png"):
            handleSimpleFaviconPNG(connection)
            return
        case ("GET", let path) where (path.hasPrefix("/favicon-") && path.hasSuffix(".png")) || (path.hasPrefix("/icons/favicon-") && path.hasSuffix(".png")):
            handleFaviconPNGRequest(connection, path: path)
            return
        case ("GET", "/icon-192.png"):
            handleIconPNGRequest(connection, size: 192)
            return
        case ("GET", "/icon-512.png"):
            handleIconPNGRequest(connection, size: 512)
            return
        case ("GET", "/icon-180.png"):
            handleIconPNGRequest(connection, size: 180)
            return
        case ("GET", "/icon-152.png"):
            handleIconPNGRequest(connection, size: 152)
            return
        case ("GET", "/icon-144.png"):
            handleIconPNGRequest(connection, size: 144)
            return
        case ("GET", "/icon-120.png"):
            handleIconPNGRequest(connection, size: 120)
            return
        case ("GET", "/icon-114.png"):
            handleIconPNGRequest(connection, size: 114)
            return
        case ("GET", "/icon-96.png"):
            handleIconPNGRequest(connection, size: 96)
            return
        case ("GET", "/icon-72.png"):
            handleIconPNGRequest(connection, size: 72)
            return
        case ("GET", "/icon-64.png"):
            handleIconPNGRequest(connection, size: 64)
            return
        case ("GET", "/icon-60.png"):
            handleIconPNGRequest(connection, size: 60)
            return
        case ("GET", "/icon-57.png"):
            handleIconPNGRequest(connection, size: 57)
            return
        case ("GET", "/icon-48.png"):
            handleIconPNGRequest(connection, size: 48)
            return
        case ("GET", "/icon-32.png"):
            handleIconPNGRequest(connection, size: 32)
            return
        case ("GET", "/chat-preview.png"):
            response = generatePreviewImageSVG()
            contentType = "image/svg+xml"
        case ("GET", let path) where path.hasPrefix("/icons/"):
            handleAppleIconRequest(connection, path: path)
            return
        case ("GET", let path) where path.hasPrefix("/files/"):
            handleFileServing(connection, path: path)
            return
        case ("GET", let path) where path.hasPrefix("/static/"):
            handleStaticFileServing(connection, path: path)
            return
        case ("GET", let path) where path.hasPrefix("/thumbnails/"):
            handleThumbnailServing(connection, path: path)
            return
        case ("POST", "/upload"):
            // Handle file uploads using WebAuthn-style processing 
            handleFileUploadSimple(connection, request: request)
            return
        case ("POST", let path) where path.hasPrefix("/webauthn/"):
            handleWebAuthnRequest(connection, request: request)
            return
        case ("POST", "/emoji/analyze"):
            handleEmojiColorAnalysis(connection, request: request)
            return
        default:
            response = "404 Not Found"
            contentType = "text/plain"
            statusCode = "404 Not Found"
        }
        
        let httpResponse = """
        HTTP/1.1 \(statusCode)\r
        Content-Type: \(contentType)\r
        Content-Length: \(response.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        \r
        \(response)
        """
        
        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // MARK: - WebAuthn Request Handler (using DogTagKit)
    
    private func handleWebAuthnRequest(_ connection: NWConnection, request: String) {
        // Parse the raw HTTP request using DogTagKit
        guard let httpRequest = WebAuthnServer.parseHTTPRequest(request, connection: connection) else {
            sendErrorResponse(connection, error: "Invalid HTTP request format")
            return
        }
        
        // Handle the request using DogTagKit WebAuthnServer
        let httpResponse = webAuthnServer.handleRequest(httpRequest)
        
        // Send the response
        let responseString = WebAuthnServer.formatHTTPResponse(httpResponse)
        connection.send(content: responseString.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    

    
    private func handleEmojiColorAnalysis(_ connection: NWConnection, request: String) {
        print("[EmojiColor] Processing emoji color analysis request")
        
        guard let bodyStart = request.range(of: "\r\n\r\n")?.upperBound else {
            sendErrorResponse(connection, error: "Invalid request format")
            return
        }
        
        let bodyString = String(request[bodyStart...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let emoji = json["emoji"] as? String else {
            sendErrorResponse(connection, error: "Invalid request body or missing emoji")
            return
        }
        
        print("[EmojiColor] Analyzing emoji: \(emoji)")
        
        // Analyze the emoji colors
        do {
            let colors = try analyzeEmojiColors(emoji: emoji)
            
            let response: [String: Any] = [
                "success": true,
                "emoji": emoji,
                "averageColor": colors.averageColor,
                "contrastColor": colors.contrastColor,
                "textColor": colors.textColor
            ]
            
            let responseData = try JSONSerialization.data(withJSONObject: response)
            sendJSONResponse(connection, json: String(data: responseData, encoding: .utf8) ?? "{}")
            
        } catch {
            print("[EmojiColor] Error analyzing emoji: \(error)")
            sendErrorResponse(connection, error: "Failed to analyze emoji colors: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Emoji Color Analysis
    
    struct EmojiColors {
        let averageColor: String
        let contrastColor: String
        let textColor: String
    }
    
    enum EmojiColorError: Error {
        case invalidEmoji
        case renderingFailed
        case colorAnalysisFailed
    }
    
    private func analyzeEmojiColors(emoji: String) throws -> EmojiColors {
        // Create a bitmap context to render the emoji
        let size: CGFloat = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: Int(size),
            height: Int(size),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw EmojiColorError.renderingFailed
        }
        
        // Set up the context
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0)) // Transparent background
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        
        // Create attributed string for the emoji
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, size * 0.7, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]
        let attributedString = NSAttributedString(string: emoji, attributes: attributes)
        
        // Create a line and draw it
        let line = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        
        // Center the emoji
        let x = (size - bounds.width) / 2 - bounds.origin.x
        let y = (size - bounds.height) / 2 - bounds.origin.y
        
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        
        // Get the image data
        guard let image = context.makeImage(),
              let dataProvider = image.dataProvider,
              let data = dataProvider.data else {
            throw EmojiColorError.renderingFailed
        }
        
        // Analyze the colors
        let pixelData = CFDataGetBytePtr(data)
        let bytesPerPixel = 4
        let totalPixels = Int(size * size)
        
        var totalRed: Int = 0
        var totalGreen: Int = 0
        var totalBlue: Int = 0
        var validPixels = 0
        
        for i in 0..<totalPixels {
            let pixelIndex = i * bytesPerPixel
            let alpha = pixelData?[pixelIndex + 3] ?? 0
            
            // Only count non-transparent pixels
            if alpha > 30 {
                let red = pixelData?[pixelIndex] ?? 0
                let green = pixelData?[pixelIndex + 1] ?? 0
                let blue = pixelData?[pixelIndex + 2] ?? 0
                
                totalRed += Int(red)
                totalGreen += Int(green)
                totalBlue += Int(blue)
                validPixels += 1
            }
        }
        
        guard validPixels > 0 else {
            throw EmojiColorError.colorAnalysisFailed
        }
        
        // Calculate average color
        let avgRed = totalRed / validPixels
        let avgGreen = totalGreen / validPixels
        let avgBlue = totalBlue / validPixels
        
        // Calculate brightness
        let brightness = (avgRed + avgGreen + avgBlue) / 3
        
        // Generate contrasting background color
        let contrastRed: Int
        let contrastGreen: Int
        let contrastBlue: Int
        
        if brightness > 128 {
            // Dark contrast for bright emojis
            contrastRed = max(0, avgRed - 100)
            contrastGreen = max(0, avgGreen - 100)
            contrastBlue = max(0, avgBlue - 100)
        } else {
            // Light contrast for dark emojis
            contrastRed = min(255, avgRed + 100)
            contrastGreen = min(255, avgGreen + 100)
            contrastBlue = min(255, avgBlue + 100)
        }
        
        // Determine text color (black or white) based on contrast background
        let contrastBrightness = (contrastRed + contrastGreen + contrastBlue) / 3
        let textColor = contrastBrightness > 128 ? "#000000" : "#FFFFFF"
        
        // Convert to hex strings
        let averageColor = String(format: "#%02X%02X%02X", avgRed, avgGreen, avgBlue)
        let contrastColor = String(format: "#%02X%02X%02X", contrastRed, contrastGreen, contrastBlue)
        
        print("[EmojiColor] Average: \(averageColor), Contrast: \(contrastColor), Text: \(textColor)")
        
        return EmojiColors(
            averageColor: averageColor,
            contrastColor: contrastColor,
            textColor: textColor
        )
    }
    
    private func handleFileUploadRequest(_ connection: NWConnection, initialData: Data, request: String) {
        print("📥 Received upload request")

        // Find where headers end in the initial data
        guard let headerEndRange = initialData.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            print("❌ Invalid HTTP request format (no header end)")
            sendErrorResponse(connection, error: "Invalid HTTP request format")
            return
        }

        let bodyData = initialData.subdata(in: headerEndRange.upperBound..<initialData.count)
        var allData = Data()
        allData.append(bodyData)
        
        // Get Content-Length from headers
        let contentLength: Int? = {
            let lines = request.components(separatedBy: "\r\n")
            for line in lines {
                if line.lowercased().hasPrefix("content-length:") {
                    let value = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).last?.trimmingCharacters(in: .whitespaces)
                    return Int(value ?? "")
                }
            }
            return nil
        }()
        
        // Get boundary from Content-Type
        let boundary: String? = {
            let lines = request.components(separatedBy: "\r\n")
            for line in lines {
                if line.lowercased().hasPrefix("content-type:") && line.contains("boundary=") {
                    if let b = line.components(separatedBy: "boundary=").last {
                        let extractedBoundary = b.trimmingCharacters(in: .whitespaces)
                        // The boundary in multipart data is just the extracted boundary, not with extra dashes
                        return extractedBoundary
                    }
                }
            }
            return nil
        }()
        
        print("📦 Content-Length:", contentLength ?? "none")
        print("🔍 Boundary:", boundary ?? "none")
        
        guard let expectedLength = contentLength, let boundary = boundary else {
            print("❌ Missing Content-Length or boundary")
            sendErrorResponse(connection, error: "Missing Content-Length or boundary")
            return
        }

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    allData.append(data)
                    print("📦 Received additional data:", data.count, "bytes")
                }
                
                if allData.count >= expectedLength {
                    print("📦 Total data received:", allData.count, "bytes")
                    
                    // Don't convert the entire data to string - it contains binary content
                    // Instead, find the boundary markers in the raw data
                    
                    let boundaryData = boundary.data(using: .utf8)!
                    print("🔍 EXTRACTED BOUNDARY: '\(boundary)'")
                    print("🔍 Looking for boundary in binary data...")
                    
                    // Find the first occurrence of the boundary
                    guard let firstBoundaryRange = allData.range(of: boundaryData) else {
                        print("❌ Could not find boundary in data")
                        self.sendErrorResponse(connection, error: "Invalid multipart format")
                        return
                    }
                    
                    print("✅ Found boundary at position \(firstBoundaryRange.lowerBound)")
                    
                    // Look for the form-data part after the first boundary
                    let afterFirstBoundary = allData[firstBoundaryRange.upperBound...]
                    
                    // Convert just the headers part to string to parse them
                    // Headers end at the first occurrence of \r\n\r\n
                    let headerEndMarker = "\r\n\r\n".data(using: .utf8)!
                    
                    guard let headerEndRange = afterFirstBoundary.range(of: headerEndMarker) else {
                        print("❌ Could not find end of headers")
                        self.sendErrorResponse(connection, error: "Invalid multipart headers")
                        return
                    }
                    
                    // Extract just the headers as string
                    let headerData = Data(afterFirstBoundary[..<headerEndRange.lowerBound])
                    guard let headerString = String(data: headerData, encoding: .utf8) else {
                        print("❌ Could not parse headers as UTF-8")
                        self.sendErrorResponse(connection, error: "Invalid header encoding")
                        return
                    }
                    
                    print("📄 Headers: \(headerString)")
                    
                    // Parse headers to extract filename and content type
                    var fileName: String?
                    var mimeType: String?
                    
                    if headerString.contains("Content-Disposition: form-data") {
                        // Extract filename
                        if let filenameMatch = headerString.range(of: "filename=\"") {
                            let fromFilename = headerString[filenameMatch.upperBound...]
                            if let endQuote = fromFilename.firstIndex(of: "\"") {
                                fileName = String(fromFilename[..<endQuote])
                                print("📄 Extracted filename: '\(fileName!)'")
                            }
                        }
                        
                        // Extract Content-Type - be more flexible with line endings
                        let contentTypePatterns = ["Content-Type: ", "content-type: "]
                        for pattern in contentTypePatterns {
                            if let contentTypeMatch = headerString.range(of: pattern, options: .caseInsensitive) {
                                let fromContentType = headerString[contentTypeMatch.upperBound...]
                                let mimeTypeString = String(fromContentType)
                                
                                // Try different line ending patterns
                                if let endLine = mimeTypeString.firstIndex(of: "\r") {
                                    mimeType = String(mimeTypeString[..<endLine])
                                } else if let endLine = mimeTypeString.firstIndex(of: "\n") {
                                    mimeType = String(mimeTypeString[..<endLine])
                                } else {
                                    // Take the whole remaining string if no line ending found
                                    mimeType = mimeTypeString.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                
                                if !mimeType!.isEmpty {
                                    print("📄 Extracted MIME type: '\(mimeType!)'")
                                    break
                                }
                            }
                        }
                        
                        // If still no MIME type found, try to infer from filename
                        if mimeType == nil || mimeType!.isEmpty {
                            print("⚠️ No MIME type found in headers, inferring from filename")
                            if let name = fileName {
                                let ext = (name as NSString).pathExtension.lowercased()
                                switch ext {
                                case "png": mimeType = "image/png"
                                case "jpg", "jpeg": mimeType = "image/jpeg"
                                case "gif": mimeType = "image/gif"
                                case "pdf": mimeType = "application/pdf"
                                case "txt": mimeType = "text/plain"
                                case "zip": mimeType = "application/zip"
                                default: mimeType = "application/octet-stream"
                                }
                                print("📄 Inferred MIME type: '\(mimeType!)'")
                            }
                        }
                    }
                    
                    // Extract the file data - it starts right after the header end marker
                    let fileDataStart = firstBoundaryRange.upperBound + headerData.count + headerEndMarker.count
                    
                    // Find the ending boundary
                    let endBoundaryPattern = "\r\n\(boundary)".data(using: .utf8)!
                    let fileDataSearchStart = fileDataStart
                    let remainingData = allData[fileDataSearchStart...]
                    
                    var fileData: Data
                    if let endBoundaryRange = remainingData.range(of: endBoundaryPattern) {
                        // Extract data up to the end boundary
                        fileData = Data(remainingData[..<endBoundaryRange.lowerBound])
                        print("📄 Extracted file data size: \(fileData.count) bytes (with end boundary)")
                    } else {
                        // No end boundary found, take all remaining data and trim manually
                        fileData = Data(remainingData)
                        
                        // Try to remove trailing boundary by looking at the end
                        if fileData.count > boundary.count + 10 {
                            let endPortion = Data(fileData.suffix(boundary.count + 10))
                            if let endString = String(data: endPortion, encoding: .utf8) {
                                if let lastBoundaryIndex = endString.lastIndex(of: "-") {
                                    let boundary_start = endString[..<lastBoundaryIndex].lastIndex(of: "\n") ?? endString.startIndex
                                    let trimLength = endString.distance(from: boundary_start, to: endString.endIndex)
                                    fileData = Data(fileData.dropLast(trimLength))
                                }
                            }
                        }
                        print("📄 Extracted file data size: \(fileData.count) bytes (manual trim)")
                    }
                    
                    guard let originalName = fileName,
                          let mime = mimeType,
                          !fileData.isEmpty else {
                        print("❌ Missing required file data - filename: \(fileName ?? "nil"), mimeType: \(mimeType ?? "nil"), dataSize: \(fileData.count)")
                        self.sendErrorResponse(connection, error: "Missing required file data")
                        return
                    }
                    
                    // Generate a unique filename
                    let fileExtension = (originalName as NSString).pathExtension
                    let uniqueFileName = "\(UUID().uuidString).\(fileExtension)"
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let uploadsPath = documentsPath.appendingPathComponent("uploads")
                    let filePath = uploadsPath.appendingPathComponent(uniqueFileName)
                    
                    print("💾 Saving file to:", filePath.path)
                    
                                            do {
                            print("✅ File data extracted, creating attachment with thumbnail...")
                            
                            // Create and save the attachment using ChatFileManager for thumbnail generation
                            let attachment = try ChatFileManager.shared.saveUploadedFile(
                                data: fileData,
                                originalFileName: originalName,
                                mimeType: mime
                            )
                        
                        // Save the attachment
                        PersistenceManager.shared.saveStandaloneAttachment(attachment)
                        print("✅ Attachment saved to persistence")
                        
                                                    // Return success response with thumbnail URL if available
                            var attachmentResponse: [String: Any] = [
                                "id": attachment.id.uuidString,
                                "fileName": attachment.fileName,
                                "originalFileName": attachment.originalFileName,
                                "name": attachment.originalFileName, // For client compatibility
                                "mimeType": attachment.mimeType,
                                "fileSize": attachment.fileSize,
                                "size": attachment.fileSize, // For client compatibility
                                "url": "/files/\(attachment.id.uuidString)/\(attachment.originalFileName)",
                                "isImage": attachment.isImage
                            ]
                            
                            // Add thumbnail URL if available
                            if let thumbnailPath = attachment.thumbnailPath {
                                attachmentResponse["thumbnailUrl"] = "/\(thumbnailPath)"
                            }
                            
                            let response: [String: Any] = [
                                "success": true,
                                "attachment": attachmentResponse
                            ]
                        
                        do {
                            let jsonData = try JSONSerialization.data(withJSONObject: response)
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                print("📤 Sending response:", jsonString)
                                self.sendJSONResponse(connection, json: jsonString)
                            } else {
                                print("❌ Failed to convert JSON to string")
                                self.sendErrorResponse(connection, error: "Failed to create response")
                            }
                        } catch {
                            print("❌ Failed to serialize JSON response")
                            self.sendErrorResponse(connection, error: "Failed to create response")
                        }
                    } catch {
                        print("❌ Failed to save file:", error)
                        self.sendErrorResponse(connection, error: "Failed to save file: \(error.localizedDescription)")
                    }
                } else if error == nil {
                    readMore()
                } else {
                    print("❌ Error during upload:", error?.localizedDescription ?? "unknown error")
                    self.sendErrorResponse(connection, error: "Upload failed: \(error?.localizedDescription ?? "unknown error")")
                }
            }
        }
        
        readMore()
    }
    
    private func handleFileUploadSimple(_ connection: NWConnection, request: String) {
        print("📥 Simple upload handler - received request")
        print("📦 Request length: \(request.count)")
        
        // For now, just return a success response to test if the route works
        let response: [String: Any] = [
            "success": true,
            "message": "Upload endpoint reached successfully",
            "requestLength": request.count
        ]
        
        do {
            let responseData = try JSONSerialization.data(withJSONObject: response)
            sendJSONResponse(connection, json: String(data: responseData, encoding: .utf8) ?? "{}")
        } catch {
            sendErrorResponse(connection, error: "Failed to create response")
        }
    }
    
    private func handleFileUploadBinary(_ connection: NWConnection, initialData: Data, headerString: String) {
        print("📥 Binary upload handler started")
        print("📦 Initial data length: \(initialData.count)")
        print("📦 Header length: \(headerString.count)")
        
        // Extract Content-Length from headers
        let contentLength: Int? = {
            let lines = headerString.components(separatedBy: "\r\n")
            for line in lines {
                if line.lowercased().hasPrefix("content-length:") {
                    let value = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).last?.trimmingCharacters(in: .whitespaces)
                    return Int(value ?? "")
                }
            }
            return nil
        }()
        
        print("📦 Expected content length: \(contentLength ?? -1)")
        
        // Find where headers end
        let headerEndMarker = "\r\n\r\n".data(using: .utf8)!
        guard let headerEndRange = initialData.range(of: headerEndMarker) else {
            print("❌ Could not find header end in binary data")
            sendErrorResponse(connection, error: "Invalid HTTP request format")
            return
        }
        
        let bodyStart = headerEndRange.upperBound
        let initialBodyData = initialData.subdata(in: bodyStart..<initialData.count)
        var allBodyData = Data()
        allBodyData.append(initialBodyData)
        
        print("📦 Initial body data length: \(initialBodyData.count)")
        
        // If we have a content length, read until we have all the data
        if let expectedLength = contentLength {
            func readMoreBinary() {
                if allBodyData.count >= expectedLength {
                    print("📦 All binary data received: \(allBodyData.count) bytes")
                    processBinaryUpload(connection, bodyData: allBodyData, headerString: headerString)
                    return
                }
                
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                    if let data = data, !data.isEmpty {
                        allBodyData.append(data)
                        print("📦 Received more binary data: \(data.count) bytes, total: \(allBodyData.count)")
                        readMoreBinary()
                    } else {
                        print("📦 Binary read complete with \(allBodyData.count) bytes")
                        self.processBinaryUpload(connection, bodyData: allBodyData, headerString: headerString)
                    }
                }
            }
            readMoreBinary()
        } else {
            print("❌ No content length found")
            sendErrorResponse(connection, error: "Missing Content-Length header")
        }
    }
    
    private func processBinaryUpload(_ connection: NWConnection, bodyData: Data, headerString: String) {
        print("📦 Processing binary upload: \(bodyData.count) bytes")
        
        // Get boundary from Content-Type header
        let boundary: String? = {
            let lines = headerString.components(separatedBy: "\r\n")
            for line in lines {
                if line.lowercased().hasPrefix("content-type:") && line.contains("boundary=") {
                    if let b = line.components(separatedBy: "boundary=").last {
                        let extractedBoundary = b.trimmingCharacters(in: .whitespaces)
                        return extractedBoundary
                    }
                }
            }
            return nil
        }()
        
        guard let boundary = boundary else {
            print("❌ Missing boundary in multipart data")
            sendErrorResponse(connection, error: "Missing boundary")
            return
        }
        
        print("🔍 EXTRACTED BOUNDARY: '\(boundary)'")
        
        // Simple file extraction - look for filename and file data
        let allData = bodyData
        let boundaryData = boundary.data(using: .utf8)!
        
        // Find the first occurrence of the boundary
        guard let firstBoundaryRange = allData.range(of: boundaryData) else {
            print("❌ Could not find boundary in data")
            sendErrorResponse(connection, error: "Invalid multipart format")
            return
        }
        
        // Look for the form-data part after the first boundary
        let afterFirstBoundary = allData[firstBoundaryRange.upperBound...]
        
        // Find headers end
        let headerEndMarker = "\r\n\r\n".data(using: .utf8)!
        guard let headerEndRange = afterFirstBoundary.range(of: headerEndMarker) else {
            print("❌ Could not find end of headers")
            sendErrorResponse(connection, error: "Invalid multipart headers")
            return
        }
        
        // Extract headers
        let headerData = Data(afterFirstBoundary[..<headerEndRange.lowerBound])
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            print("❌ Could not parse headers as UTF-8")
            sendErrorResponse(connection, error: "Invalid header encoding")
            return
        }
        
        print("📄 Headers: \(headerString)")
        
        // Parse filename and content type
        var fileName: String?
        var mimeType: String?
        
        if headerString.contains("Content-Disposition: form-data") {
            // Extract filename
            if let filenameMatch = headerString.range(of: "filename=\"") {
                let fromFilename = headerString[filenameMatch.upperBound...]
                if let endQuote = fromFilename.firstIndex(of: "\"") {
                    fileName = String(fromFilename[..<endQuote])
                    print("📄 Extracted filename: '\(fileName!)'")
                }
            }
            
            // Extract Content-Type
            if let contentTypeMatch = headerString.range(of: "Content-Type: ", options: .caseInsensitive) {
                let fromContentType = headerString[contentTypeMatch.upperBound...]
                let mimeTypeString = String(fromContentType)
                
                if let endLine = mimeTypeString.firstIndex(of: "\r") {
                    mimeType = String(mimeTypeString[..<endLine])
                } else if let endLine = mimeTypeString.firstIndex(of: "\n") {
                    mimeType = String(mimeTypeString[..<endLine])
                } else {
                    mimeType = mimeTypeString.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if !mimeType!.isEmpty {
                    print("📄 Extracted MIME type: '\(mimeType!)'")
                }
            }
        }
        
        // Extract file data
        let fileDataStart = firstBoundaryRange.upperBound + headerData.count + headerEndMarker.count
        let remainingData = allData[fileDataStart...]
        
        // Find ending boundary
        let endBoundaryPattern = "\r\n\(boundary)".data(using: .utf8)!
        var fileData: Data
        if let endBoundaryRange = remainingData.range(of: endBoundaryPattern) {
            fileData = Data(remainingData[..<endBoundaryRange.lowerBound])
            print("📄 Extracted file data size: \(fileData.count) bytes (with end boundary)")
        } else {
            fileData = Data(remainingData)
            // Try to remove trailing boundary manually
            if fileData.count > boundary.count + 10 {
                let endPortion = Data(fileData.suffix(boundary.count + 10))
                if let endString = String(data: endPortion, encoding: .utf8) {
                    if let lastBoundaryIndex = endString.lastIndex(of: "-") {
                        let boundary_start = endString[..<lastBoundaryIndex].lastIndex(of: "\n") ?? endString.startIndex
                        let trimLength = endString.distance(from: boundary_start, to: endString.endIndex)
                        fileData = Data(fileData.dropLast(trimLength))
                    }
                }
            }
            print("📄 Extracted file data size: \(fileData.count) bytes (manual trim)")
        }
        
        // Infer MIME type if missing
        if mimeType == nil || mimeType!.isEmpty {
            if let name = fileName {
                let ext = (name as NSString).pathExtension.lowercased()
                switch ext {
                case "png": mimeType = "image/png"
                case "jpg", "jpeg": mimeType = "image/jpeg"
                case "gif": mimeType = "image/gif"
                case "pdf": mimeType = "application/pdf"
                case "txt": mimeType = "text/plain"
                case "zip": mimeType = "application/zip"
                default: mimeType = "application/octet-stream"
                }
                print("📄 Inferred MIME type: '\(mimeType!)'")
            }
        }
        
        guard let originalName = fileName,
              let mime = mimeType,
              !fileData.isEmpty else {
            print("❌ Missing required file data - filename: \(fileName ?? "nil"), mimeType: \(mimeType ?? "nil"), dataSize: \(fileData.count)")
            sendErrorResponse(connection, error: "Missing required file data")
            return
        }
        
        // Generate unique filename and save
        let fileExtension = (originalName as NSString).pathExtension
        let uniqueFileName = "\(UUID().uuidString).\(fileExtension)"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let uploadsPath = documentsPath.appendingPathComponent("uploads")
        let filePath = uploadsPath.appendingPathComponent(uniqueFileName)
        
        print("💾 Saving file to:", filePath.path)
        
                    do {
                print("✅ File data extracted, creating attachment with thumbnail...")
                
                // Create and save the attachment using ChatFileManager for thumbnail generation
                let attachment = try ChatFileManager.shared.saveUploadedFile(
                    data: fileData,
                    originalFileName: originalName,
                    mimeType: mime
                )
            
            // Save the attachment
            PersistenceManager.shared.saveStandaloneAttachment(attachment)
            print("✅ Attachment saved to persistence")
            
                            // Return success response with thumbnail URL if available
                var attachmentResponse: [String: Any] = [
                    "id": attachment.id.uuidString,
                    "fileName": attachment.fileName,
                    "originalFileName": attachment.originalFileName,
                    "name": attachment.originalFileName, // For client compatibility
                    "mimeType": attachment.mimeType,
                    "fileSize": attachment.fileSize,
                    "size": attachment.fileSize, // For client compatibility
                    "url": "/files/\(attachment.id.uuidString)/\(attachment.originalFileName)",
                    "isImage": attachment.isImage
                ]
                
                // Add thumbnail URL if available
                if let thumbnailPath = attachment.thumbnailPath {
                    attachmentResponse["thumbnailUrl"] = "/\(thumbnailPath)"
                }
                
                let response: [String: Any] = [
                    "success": true,
                    "attachment": attachmentResponse
                ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: response)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("📤 Sending response:", jsonString)
                    self.sendJSONResponse(connection, json: jsonString)
                } else {
                    print("❌ Failed to convert JSON to string")
                    self.sendErrorResponse(connection, error: "Failed to create response")
                }
            } catch {
                print("❌ Failed to serialize JSON response")
                self.sendErrorResponse(connection, error: "Failed to create response")
            }
        } catch {
            print("❌ Failed to save file:", error)
            self.sendErrorResponse(connection, error: "Failed to save file: \(error.localizedDescription)")
        }
    }
    
    private func handleFileServing(_ connection: NWConnection, path: String) {
        let pathComponents = path.components(separatedBy: "/").filter { !$0.isEmpty }
        
        // Support both old format (/files/uuid.ext) and new format (/files/id/filename.ext)
        let allAttachments = PersistenceManager.shared.getAllAttachments()
        let attachment: FileAttachment?
        
        if pathComponents.count == 2 {
            // Old format: /files/filename
            let fileName = pathComponents[1]
            attachment = allAttachments.first(where: { $0.fileName == fileName })
        } else if pathComponents.count == 3 {
            // New format: /files/id/originalfilename
            let fileId = pathComponents[1]
            attachment = allAttachments.first(where: { $0.id.uuidString == fileId })
        } else {
            attachment = nil
        }
        
        guard let foundAttachment = attachment else {
            sendErrorResponse(connection, error: "File not found", statusCode: "404 Not Found")
            return
        }
        
        do {
            let fileData = try ChatFileManager.shared.getFileData(for: foundAttachment)
            sendFileResponse(connection, data: fileData, mimeType: foundAttachment.mimeType, fileName: foundAttachment.originalFileName)
        } catch {
            sendErrorResponse(connection, error: "Failed to read file", statusCode: "500 Internal Server Error")
        }
    }
    
    private func handleThumbnailServing(_ connection: NWConnection, path: String) {
        let thumbnailPath = String(path.dropFirst(1)) // Remove leading "/"
        
        // Find the attachment by thumbnail path
        let allAttachments = PersistenceManager.shared.getAllAttachments()
        guard let attachment = allAttachments.first(where: { $0.thumbnailPath == thumbnailPath }) else {
            sendErrorResponse(connection, error: "Thumbnail not found", statusCode: "404 Not Found")
            return
        }
        
        do {
            if let thumbnailData = try ChatFileManager.shared.getThumbnailData(for: attachment) {
                sendFileResponse(connection, data: thumbnailData, mimeType: "image/jpeg", fileName: "thumbnail.jpg")
            } else {
                sendErrorResponse(connection, error: "Thumbnail not available", statusCode: "404 Not Found")
            }
        } catch {
            sendErrorResponse(connection, error: "Failed to read thumbnail", statusCode: "500 Internal Server Error")
        }
    }
    
    private func handleStaticFileServing(_ connection: NWConnection, path: String) {
        // Remove /static/ prefix and get the actual file path
        let fileName = String(path.dropFirst("/static/".count))
        
        // Try various locations for the static file
        let possiblePaths = [
            "static/\(fileName)",
            "./static/\(fileName)",
            "../../static/\(fileName)",
            FileManager.default.currentDirectoryPath + "/static/\(fileName)"
        ]
        
        for staticFilePath in possiblePaths {
            if FileManager.default.fileExists(atPath: staticFilePath) {
                do {
                    let fileData = try Data(contentsOf: URL(fileURLWithPath: staticFilePath))
                    
                    // Determine MIME type based on file extension
                    let mimeType = getMimeType(for: fileName)
                    
                    print("📁 Serving static file: \(staticFilePath)")
                    sendFileResponse(connection, data: fileData, mimeType: mimeType, fileName: fileName)
                    return
                } catch {
                    print("❌ Failed to read static file \(staticFilePath): \(error)")
                    continue
                }
            }
        }
        
        // File not found
        print("❌ Static file not found: \(fileName)")
        sendErrorResponse(connection, error: "Static file not found: \(fileName)", statusCode: "404 Not Found")
    }
    
    private func getMimeType(for fileName: String) -> String {
        let pathExtension = (fileName as NSString).pathExtension.lowercased()
        
        switch pathExtension {
        case "html", "htm":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "application/javascript"
        case "json":
            return "application/json"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "ico":
            return "image/x-icon"
        case "txt":
            return "text/plain"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }
    
    private func sendJSONResponse(_ connection: NWConnection, json: String) {
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(json.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(json)
        """
        
        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendFileResponse(_ connection: NWConnection, data: Data, mimeType: String, fileName: String) {
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: \(mimeType)\r
        Content-Length: \(data.count)\r
        Content-Disposition: inline; filename="\(fileName)"\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        
        """
        
        var responseData = httpResponse.data(using: .utf8)!
        responseData.append(data)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendResponse(_ connection: NWConnection, statusCode: String, contentType: String, body: String) {
        let httpResponse = """
        HTTP/1.1 \(statusCode)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(body)
        """
        
        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendErrorResponse(_ connection: NWConnection, error: String, statusCode: String = "400 Bad Request") {
        let errorJSON = """
        {
            "success": false,
            "error": "\(error)"
        }
        """
        
        let httpResponse = """
        HTTP/1.1 \(statusCode)\r
        Content-Type: application/json\r
        Content-Length: \(errorJSON.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(errorJSON)
        """
        
        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func handleCORSPreflight(_ connection: NWConnection, path: String) {
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Content-Length\r
        Access-Control-Max-Age: 86400\r
        Content-Length: 0\r
        Connection: close\r
        \r
        
        """
        
        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func handleWebSocketUpgrade(_ connection: NWConnection, request: String) {
        // Extract WebSocket key for handshake
        let lines = request.components(separatedBy: "\r\n")
        var webSocketKey = ""
        
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                webSocketKey = String(line.dropFirst(18).trimmingCharacters(in: .whitespaces))
                break
            }
        }
        
        // Generate WebSocket accept key
        let acceptKey = generateWebSocketAcceptKey(webSocketKey)
        
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r
        
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            // Create WebSocket client
            let client = WebSocketClient(connection: connection)
            self.clients.append(client)
            
            DispatchQueue.main.async {
                self.connectedClients = self.clients.count
            }
            
            client.onMessage = { [weak self] message in
                self?.delegate?.webServer(self!, didReceiveMessage: message, from: client)
            }
            
            client.onDisconnect = { [weak self] in
                self?.clients.removeAll { $0 === client }
                DispatchQueue.main.async {
                    self?.connectedClients = self?.clients.count ?? 0
                }
                self?.delegate?.webServer(self!, clientDidDisconnect: client)
            }
            
            self.delegate?.webServer(self, clientDidConnect: client)
            client.startReceiving()
        })
    }
    
    private func generateWebSocketAcceptKey(_ key: String) -> String {
        let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magicString
        let hash = combined.data(using: .utf8)!.sha1()
        return hash.base64EncodedString()
    }
    
    private func setupRoutes() {
        // Routes are now handled in handleHTTPRequest
    }
    
    // MARK: - Asset Generation Functions
    
    private func handleFaviconRequest(_ connection: NWConnection) {
        // Serve a simple SVG favicon that Safari will accept
        let faviconData = generateSimpleFaviconSVG()
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: image/svg+xml\r
        Content-Length: \(faviconData.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: public, max-age=31536000\r
        \r
        """
        
        var responseData = Data()
        responseData.append(httpResponse.data(using: .utf8)!)
        responseData.append(faviconData)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func generateSimpleFaviconSVG() -> Data {
        // Generate a simple SVG favicon for Safari tabs
        let faviconSVG = """
        <svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <rect width="32" height="32" rx="6" fill="#007AFF"/>
          <circle cx="11" cy="14" r="6" fill="white" opacity="0.9"/>
          <circle cx="21" cy="18" r="4" fill="white" opacity="0.7"/>
          <circle cx="9" cy="14" r="1.5" fill="#007AFF"/>
          <circle cx="11" cy="14" r="1.5" fill="#007AFF"/>
          <circle cx="13" cy="14" r="1.5" fill="#007AFF"/>
        </svg>
        """
        
        return faviconSVG.data(using: .utf8) ?? Data()
    }
    
    private func handleSimpleFaviconPNG(_ connection: NWConnection) {
        // Create a simple base64 PNG data URL for maximum Safari compatibility
        let pngData = generateSimplePNGFavicon()
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: image/png\r
        Content-Length: \(pngData.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: public, max-age=31536000\r
        \r
        """
        
        var responseData = Data()
        responseData.append(httpResponse.data(using: .utf8)!)
        responseData.append(pngData)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func generateSimplePNGFavicon() -> Data {
        // For maximum compatibility, return a minimal PNG-like data structure
        // This is a simple blue square encoded as a small PNG
        let simplePNG = """
        <svg width="32" height="32" xmlns="http://www.w3.org/2000/svg">
          <rect width="32" height="32" fill="#007AFF"/>
          <text x="16" y="20" text-anchor="middle" fill="white" font-size="16">💬</text>
        </svg>
        """
        
        return simplePNG.data(using: .utf8) ?? Data()
    }
    
    private func handleFaviconPNGRequest(_ connection: NWConnection, path: String) {
        // Extract size from favicon-32x32.png or /icons/favicon-32x32.png format
        let filename = path.replacingOccurrences(of: "/icons/", with: "").replacingOccurrences(of: "/", with: "")
        let sizeStr: String
        if filename.contains("favicon-") {
            let parts = filename.replacingOccurrences(of: "favicon-", with: "")
                             .replacingOccurrences(of: ".png", with: "")
            sizeStr = parts.components(separatedBy: "x").first ?? "32"
        } else {
            sizeStr = "32"
        }
        
        let size = Int(sizeStr) ?? 32
        
        // Generate proper macOS-compatible favicon SVG (but serve as SVG for Safari)
        let iconData = generateMacOSFaviconSVG(size: size)
        
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: image/svg+xml\r
        Content-Length: \(iconData.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: public, max-age=31536000\r
        \r
        """
        
        var responseData = Data()
        responseData.append(httpResponse.data(using: .utf8)!)
        responseData.append(iconData)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func generateMacOSFaviconSVG(size: Int) -> Data {
        // Generate a macOS-specific favicon that looks like a proper app icon
        let gradientId = "macOSGrad\(size)" // Make ID unique per size
        let faviconSVG = """
        <svg width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="\(gradientId)" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#007AFF;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#0051D5;stop-opacity:1" />
            </linearGradient>
          </defs>
          
          <!-- macOS-style rounded rectangle background -->
          <rect width="\(size)" height="\(size)" rx="\(size/5)" fill="url(#\(gradientId))"/>
          
          <!-- Chat bubble icon optimized for small sizes -->
          <g transform="translate(\(size/2), \(size/2))">
            <!-- Main chat bubble -->
            <circle cx="-\(size/8)" cy="-\(size/16)" r="\(size/4)" fill="white" opacity="0.95"/>
            <!-- Smaller bubble -->
            <circle cx="\(size/8)" cy="\(size/16)" r="\(size/6)" fill="white" opacity="0.8"/>
            <!-- Chat dots -->
            <circle cx="-\(size/6)" cy="-\(size/16)" r="\(max(1, size/24))" fill="#007AFF"/>
            <circle cx="-\(size/8)" cy="-\(size/16)" r="\(max(1, size/24))" fill="#007AFF"/>
            <circle cx="-\(size/12)" cy="-\(size/16)" r="\(max(1, size/24))" fill="#007AFF"/>
          </g>
        </svg>
        """
        
        return faviconSVG.data(using: .utf8) ?? Data()
    }
    
    private func generateWebManifest() -> String {
        return """
        {
          "name": "XCF Chat - Secure Real-time Chat",
          "short_name": "XCF Chat",
          "description": "Secure real-time chat with emoji avatars and file sharing",
          "start_url": "/",
          "display": "standalone",
          "background_color": "#121212",
          "theme_color": "#007AFF",
          "orientation": "portrait-primary",
          "scope": "/",
          "icons": [
            {
              "src": "/favicon.ico",
              "sizes": "16x16 32x32",
              "type": "image/x-icon"
            },
            {
              "src": "/icons/favicon-16x16.png",
              "sizes": "16x16",
              "type": "image/png"
            },
            {
              "src": "/icons/favicon-32x32.png",
              "sizes": "32x32",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-57x57.png",
              "sizes": "57x57",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-60x60.png",
              "sizes": "60x60",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-72x72.png",
              "sizes": "72x72",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-76x76.png",
              "sizes": "76x76",
              "type": "image/png"
            },
            {
              "src": "/icons/favicon-96x96.png",
              "sizes": "96x96",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-114x114.png",
              "sizes": "114x114",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-120x120.png",
              "sizes": "120x120",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-144x144.png",
              "sizes": "144x144",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-152x152.png",
              "sizes": "152x152",
              "type": "image/png"
            },
            {
              "src": "/icons/apple-icon-180x180.png",
              "sizes": "180x180",
              "type": "image/png"
            },
            {
              "src": "/icons/android-icon-192x192.png",
              "sizes": "192x192",
              "type": "image/png",
              "purpose": "any maskable"
            },
            {
              "src": "/icons/android-icon-512x512.png",
              "sizes": "512x512",
              "type": "image/png",
              "purpose": "any maskable"
            }
          ],
          "categories": ["social", "communication"],
          "lang": "en-US"
        }
        """
    }
    
    private func generateBrowserConfig() -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <browserconfig>
          <msapplication>
            <tile>
              <square70x70logo src="/icons/ms-icon-70x70.png"/>
              <square150x150logo src="/icons/ms-icon-150x150.png"/>
              <square310x310logo src="/icons/ms-icon-310x310.png"/>
              <TileColor>#007AFF</TileColor>
            </tile>
          </msapplication>
        </browserconfig>
        """
    }
    
    private func generateFaviconICO() -> Data {
        // Create a proper ICO file with embedded PNG data for macOS compatibility
        // ICO format: header + directory + PNG data
        
        // Generate a 32x32 PNG icon
        let pngData = generateMacOSFaviconPNG()
        
        // ICO Header (6 bytes)
        var icoData = Data([
            0x00, 0x00, // Reserved (must be 0)
            0x01, 0x00, // Type (1 = ICO)
            0x01, 0x00  // Number of images
        ])
        
        // Directory Entry (16 bytes)
        let pngSize = UInt32(pngData.count)
        let offset = UInt32(22) // 6 + 16 = 22 bytes header + directory
        
        icoData.append(contentsOf: [
            32,    // Width (32 pixels)
            32,    // Height (32 pixels)
            0,     // Color count (0 for PNG)
            0,     // Reserved
            1, 0,  // Color planes (little endian)
            32, 0, // Bits per pixel (little endian)
        ])
        
        // PNG size (little endian)
        icoData.append(UInt8(pngSize & 0xFF))
        icoData.append(UInt8((pngSize >> 8) & 0xFF))
        icoData.append(UInt8((pngSize >> 16) & 0xFF))
        icoData.append(UInt8((pngSize >> 24) & 0xFF))
        
        // Offset to PNG data (little endian)
        icoData.append(UInt8(offset & 0xFF))
        icoData.append(UInt8((offset >> 8) & 0xFF))
        icoData.append(UInt8((offset >> 16) & 0xFF))
        icoData.append(UInt8((offset >> 24) & 0xFF))
        
        // Append PNG data
        icoData.append(pngData)
        
        return icoData
    }
    
    private func generateMacOSFaviconPNG() -> Data {
        // Create a simple PNG-like data for macOS favicon
        // Since we can't easily generate real PNG without external libraries,
        // we'll create a minimal data structure
        
        // For now, return a minimal SVG that many systems will accept
        let faviconSVG = """
        <svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <rect width="32" height="32" rx="6" fill="#007AFF"/>
          <g transform="translate(16, 16)">
            <circle cx="-4" cy="-2" r="6" fill="white" opacity="0.9"/>
            <circle cx="3" cy="2" r="4" fill="white" opacity="0.7"/>
            <circle cx="-5" cy="-2" r="1" fill="#007AFF"/>
            <circle cx="-3" cy="-2" r="1" fill="#007AFF"/>
            <circle cx="-1" cy="-2" r="1" fill="#007AFF"/>
          </g>
        </svg>
        """
        
        return faviconSVG.data(using: .utf8) ?? Data()
    }
    
    private func generatePreviewImageSVG() -> String {
        return """
        <svg width="1200" height="630" viewBox="0 0 1200 630" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <!-- Exact dark mode gradient from CSS -->
            <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#4a5568;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#2d3748;stop-opacity:1" />
            </linearGradient>
            
            <!-- Dark modal backdrop -->
            <filter id="blur">
              <feGaussianBlur in="SourceGraphic" stdDeviation="2"/>
            </filter>
          </defs>
          
          <!-- Background - exact gradient from CSS -->
          <rect width="1200" height="630" fill="url(#bg)"/>
          
          <!-- Header - matches .header styling -->
          <rect x="50" y="50" width="1100" height="70" rx="12" fill="rgba(30, 30, 30, 0.95)" filter="url(#blur)"/>
          <text x="80" y="95" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="24" font-weight="600" fill="#cbd5e0">💬 XCF Chat</text>
          <!-- Fixed positioning for right-side text -->
          <text x="1050" y="78" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="14" font-weight="500" fill="#30D158" text-anchor="end">✅ Connected</text>
          <text x="1050" y="98" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" fill="#cbd5e0" text-anchor="end">3 users online</text>
          
          <!-- Main chat container - dark mode styling -->
          <rect x="50" y="140" width="1100" height="420" rx="15" fill="#1e1e1e" stroke="#2d3748" stroke-width="1"/>
          
          <!-- Sidebar - dark background -->
          <rect x="70" y="160" width="300" height="380" rx="12" fill="#121212"/>
          
          <!-- FIXED: User info section - proper emoji and text alignment -->
          <rect x="90" y="180" width="260" height="65" rx="8" fill="rgba(0,122,255,0.2)" stroke="#2d3748" stroke-width="1"/>
          <text x="110" y="218" font-size="20" fill="#e2e8f0" dominant-baseline="middle">👤</text>
          <text x="145" y="218" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="16" font-weight="600" fill="#e2e8f0" dominant-baseline="middle">You</text>
          
          <!-- Rooms section header -->
          <text x="110" y="280" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="18" font-weight="600" fill="#cbd5e0">Rooms</text>
          
          <!-- Active room (Lobby) - blue active state -->
          <rect x="90" y="295" width="260" height="45" rx="8" fill="#007AFF"/>
          <text x="110" y="323" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="16" font-weight="500" fill="white">Lobby</text>
          
          <!-- Inactive rooms - dark styling -->
          <rect x="90" y="350" width="260" height="45" rx="8" fill="#1e1e1e" stroke="#2d3748" stroke-width="1"/>
          <text x="110" y="378" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="14" fill="#e2e8f0">General</text>
          
          <rect x="90" y="405" width="260" height="45" rx="8" fill="#1e1e1e" stroke="#2d3748" stroke-width="1"/>
          <text x="110" y="433" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="14" fill="#e2e8f0">Random</text>
          
          <!-- Chat area - dark background -->
          <rect x="390" y="160" width="740" height="380" rx="12" fill="#1e1e1e"/>
          
          <!-- Chat header - dark styling -->
          <rect x="390" y="160" width="740" height="60" rx="12" fill="#1e1e1e" stroke="#2d3748" stroke-width="0 0 1 0"/>
          <text x="410" y="195" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="18" font-weight="600" fill="#e2e8f0">Lobby</text>
          
          <!-- Messages area with correct dark mode styling -->
          <g transform="translate(410, 240)">
            <!-- Message 1 - Other user (.message.other) - black background -->
            <rect x="0" y="0" width="300" height="50" rx="12" fill="#000000"/>
            <text x="15" y="20" font-size="14" fill="#e2e8f0">🐶</text>
            <text x="40" y="20" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="600" fill="#e2e8f0">Alice</text>
            <text x="220" y="20" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="10" fill="#d1d5db">2:30 PM</text>
            <text x="15" y="40" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" fill="#e2e8f0">Hey everyone!</text>
            
            <!-- Message 2 - Own message (.message.own) - correct blue -->
            <rect x="420" y="60" width="280" height="50" rx="12" fill="#0a84ff"/>
            <text x="435" y="80" font-size="14" fill="white">👤</text>
            <text x="460" y="80" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="600" fill="white">You</text>
            <text x="620" y="80" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="10" fill="rgba(255,255,255,0.8)">2:31 PM</text>
            <text x="435" y="100" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" fill="white">Hello! How's it going?</text>
            
            <!-- Message 3 - Other user -->
            <rect x="0" y="120" width="320" height="50" rx="12" fill="#000000"/>
            <text x="15" y="140" font-size="14" fill="#e2e8f0">🦊</text>
            <text x="40" y="140" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="600" fill="#e2e8f0">Bob</text>
            <text x="240" y="140" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="10" fill="#d1d5db">2:32 PM</text>
            <text x="15" y="160" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" fill="#e2e8f0">Great! Love this chat app</text>
          </g>
          
          <!-- Message input area - 40px height -->
          <rect x="410" y="485" width="600" height="40" rx="20" fill="#2d3748" stroke="#2d3748" stroke-width="1"/>
          <text x="430" y="509" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" fill="#9ca3af">Type a message...</text>
          
          <!-- FIXED: Send button with properly aligned text -->
          <rect x="1020" y="485" width="100" height="40" rx="20" fill="#007AFF"/>
          <text x="1070" y="505" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="14" font-weight="500" fill="white" text-anchor="middle" dominant-baseline="central">Send</text>
          
          <!-- Title - repositioned to bottom -->
          <text x="600" y="600" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="28" font-weight="700" fill="white" text-anchor="middle">Secure Real-time Chat</text>
          
          <!-- Subtitle at very bottom -->
          <text x="600" y="620" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="14" fill="rgba(255,255,255,0.8)" text-anchor="middle">Anonymous • Passwordless • Emoji Avatars • WebAuthn FIDO2 Passkeys</text>
        </svg>
        """
    }
    
    private func generateIconSVG(for path: String) -> String {
        // Extract size from path (e.g., "/icons/apple-icon-60x60.png" -> "60")
        let components = path.components(separatedBy: "/")
        let filename = components.last ?? ""
        let sizeStr = filename.components(separatedBy: "-").last?.components(separatedBy: "x").first ?? "32"
        let size = Int(sizeStr) ?? 32
        
        return """
        <svg width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="iconGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#007AFF;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#0056CC;stop-opacity:1" />
            </linearGradient>
          </defs>
          
          <!-- Background Circle -->
          <circle cx="\(size/2)" cy="\(size/2)" r="\(size/2 - 1)" fill="url(#iconGrad)"/>
          
          <!-- Chat Emoji 💬 -->
          <text x="\(size/2)" y="\(size/2 + size/8)" font-size="\(size * 3/4)" text-anchor="middle" dominant-baseline="middle">💬</text>
        </svg>
        """
    }
    
    private func handleIconPNGRequest(_ connection: NWConnection, size: Int) {
        // Generate a simple PNG icon data
        let iconData = generateAppIconPNG(size: size)
        
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: image/svg+xml\r
        Content-Length: \(iconData.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: public, max-age=31536000\r
        \r
        """
        
        var responseData = Data()
        responseData.append(httpResponse.data(using: .utf8)!)
        responseData.append(iconData)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func generateAppIconPNG(size: Int) -> Data {
        // Create a minimal PNG with a blue background and chat emoji
        // This is a simplified approach - in production you'd use a proper PNG library
        
        // For now, let's generate an SVG and indicate it's a PNG
        let svgIcon = """
        <svg width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="iconGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#007AFF;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#0056CC;stop-opacity:1" />
            </linearGradient>
          </defs>
          
          <!-- Background Circle -->
          <circle cx="\(size/2)" cy="\(size/2)" r="\(size/2 - 2)" fill="url(#iconGrad)" stroke="#0056CC" stroke-width="2"/>
          
          <!-- Chat Emoji -->
          <text x="\(size/2)" y="\(size/2 + size/8)" font-size="\(size * 3/4)" text-anchor="middle" dominant-baseline="middle">💬</text>
        </svg>
        """
        
        return svgIcon.data(using: .utf8) ?? Data()
    }
    
    private func handleAppleIconRequest(_ connection: NWConnection, path: String) {
        // Extract size from path (e.g. "/icons/apple-icon-180x180.png" -> "180")
        let filename = path.components(separatedBy: "/").last ?? ""
        
        // Extract size from various Apple icon formats
        let sizeStr: String
        if filename.contains("apple-icon-") {
            // Extract from apple-icon-180x180.png
            let parts = filename.replacingOccurrences(of: "apple-icon-", with: "")
                             .replacingOccurrences(of: ".png", with: "")
            sizeStr = parts.components(separatedBy: "x").first ?? "180"
        } else if filename.contains("android-icon-") {
            // Extract from android-icon-192x192.png
            let parts = filename.replacingOccurrences(of: "android-icon-", with: "")
                             .replacingOccurrences(of: ".png", with: "")
            sizeStr = parts.components(separatedBy: "x").first ?? "192"
        } else if filename.contains("ms-icon-") {
            // Extract from ms-icon-144x144.png
            let parts = filename.replacingOccurrences(of: "ms-icon-", with: "")
                             .replacingOccurrences(of: ".png", with: "")
            sizeStr = parts.components(separatedBy: "x").first ?? "144"
        } else if filename.contains("favicon-") {
            // Extract from favicon-32x32.png
            let parts = filename.replacingOccurrences(of: "favicon-", with: "")
                             .replacingOccurrences(of: ".png", with: "")
            sizeStr = parts.components(separatedBy: "x").first ?? "32"
        } else {
            sizeStr = "180" // Default size
        }
        
        let size = Int(sizeStr) ?? 180
        
        // Generate a proper app icon for Apple Passwords
        let iconData = generateAppleAppIconData(size: size)
        
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: image/png\r
        Content-Length: \(iconData.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: public, max-age=31536000\r
        \r
        """
        
        var responseData = Data()
        responseData.append(httpResponse.data(using: .utf8)!)
        responseData.append(iconData)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func generateAppleAppIconData(size: Int) -> Data {
        // Create a minimal PNG data structure for the icon
        // This is a simplified approach - we'll create an SVG but serve it as PNG
        // Many systems accept SVG with PNG content-type
        
        let svgIcon = """
        <svg width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="iconGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#007AFF;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#0051D5;stop-opacity:1" />
            </linearGradient>
            <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">
              <feDropShadow dx="0" dy="2" stdDeviation="4" flood-color="#000000" flood-opacity="0.3"/>
            </filter>
          </defs>
          
          <!-- Background with rounded corners for modern app icon look -->
          <rect x="0" y="0" width="\(size)" height="\(size)" rx="\(size/5)" ry="\(size/5)" fill="url(#iconGrad)" filter="url(#shadow)"/>
          
          <!-- Chat bubble icon centered -->
          <g transform="translate(\(size/2), \(size/2))">
            <!-- Main chat bubble -->
            <circle cx="-\(size/8)" cy="-\(size/12)" r="\(size/4)" fill="white" opacity="0.9"/>
            <!-- Smaller chat bubble -->
            <circle cx="\(size/8)" cy="\(size/12)" r="\(size/6)" fill="white" opacity="0.7"/>
            <!-- Chat dots -->
            <circle cx="-\(size/6)" cy="-\(size/12)" r="\(size/32)" fill="#007AFF"/>
            <circle cx="-\(size/8)" cy="-\(size/12)" r="\(size/32)" fill="#007AFF"/>
            <circle cx="-\(size/12)" cy="-\(size/12)" r="\(size/32)" fill="#007AFF"/>
          </g>
        </svg>
        """
        
        return svgIcon.data(using: .utf8) ?? Data()
    }
    
    // MARK: - Admin API Handlers (delegate to managers)
    
    private func handleAdminAPIUsers(_ connection: NWConnection, request: String) {
        let usersData = webAuthAdminManager.getAllUsers()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: usersData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            sendJSONResponse(connection, json: jsonString)
        } catch {
            sendErrorResponse(connection, error: "Failed to serialize users data")
        }
    }
    
    private func handleAdminAPIToggleUser(_ connection: NWConnection, request: String, path: String) {
        // Extract credential ID from path /admin/api/users/{id}/toggle
        let pathComponents = path.components(separatedBy: "/")
        guard pathComponents.count >= 5 else {
            sendErrorResponse(connection, error: "Invalid path")
            return
        }
        
        let rawCredentialId = pathComponents[4]
        guard let credentialId = rawCredentialId.removingPercentEncoding else {
            sendErrorResponse(connection, error: "Invalid credential ID encoding")
            return
        }
        
        // Extract request body
        guard let bodyStart = request.range(of: "\r\n\r\n")?.upperBound else {
            sendErrorResponse(connection, error: "Invalid request format")
            return
        }
        
        let bodyString = String(request[bodyStart...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let enabled = json["enabled"] as? Bool else {
            sendErrorResponse(connection, error: "Invalid request body")
            return
        }
        
        // Update user enabled status using WebAuthAdminManager
        let success = webAuthAdminManager.toggleUserStatus(credentialId: credentialId, enabled: enabled)
        
        if success {
            let response = "{\"success\":true,\"message\":\"User status updated successfully\"}"
            sendJSONResponse(connection, json: response)
        } else {
            sendErrorResponse(connection, error: "Failed to update user status")
        }
    }
    
    private func handleAdminAPIDeleteUser(_ connection: NWConnection, request: String, path: String) {
        // Extract credential ID from path /admin/api/users/{id}
        let pathComponents = path.components(separatedBy: "/")
        guard pathComponents.count >= 4 else {
            sendErrorResponse(connection, error: "Invalid path")
            return
        }
        
        let rawCredentialId = pathComponents[4]
        guard let credentialId = rawCredentialId.removingPercentEncoding else {
            sendErrorResponse(connection, error: "Invalid credential ID encoding")
            return
        }
        
        // Delete user using WebAuthAdminManager
        let success = webAuthAdminManager.deleteUser(credentialId: credentialId)
        
        if success {
            sendJSONResponse(connection, json: "{\"success\":true}")
        } else {
            sendErrorResponse(connection, error: "Failed to delete user")
        }
    }
    
    private func handleAdminAPIDisableByIP(_ connection: NWConnection, request: String) {
        // Extract request body
        guard let bodyStart = request.range(of: "\r\n\r\n")?.upperBound else {
            sendErrorResponse(connection, error: "Invalid request format")
            return
        }
        
        let bodyString = String(request[bodyStart...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let ipAddress = json["ipAddress"] as? String else {
            sendErrorResponse(connection, error: "Invalid request body")
            return
        }
        
        // Disable all users with the specified IP using WebAuthAdminManager
        let disabledCount = webAuthAdminManager.disableUsersByIP(ipAddress: ipAddress)
        
        let response = "{\"success\":true,\"disabledCount\":\(disabledCount)}"
        sendJSONResponse(connection, json: response)
    }
    
    private func handleAdminAPIUpdateEmoji(_ connection: NWConnection, request: String, path: String) {
        guard let bodyRange = request.range(of: "\r\n\r\n"),
              let bodyData = String(request[bodyRange.upperBound...]).data(using: .utf8),
              let requestData = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let newEmoji = requestData["emoji"] as? String else {
            sendResponse(connection, statusCode: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid request data\"}")
            return
        }
        
        // Extract credential ID from path /admin/api/users/{credentialId}/emoji
        let pathComponents = path.components(separatedBy: "/")
        guard pathComponents.count >= 5 else {
            sendResponse(connection, statusCode: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid path\"}")
            return
        }
        
        let rawCredentialId = pathComponents[4]
        guard let credentialId = rawCredentialId.removingPercentEncoding else {
            sendResponse(connection, statusCode: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid credential ID encoding\"}")
            return
        }
        
        // Update emoji using WebAuthAdminManager
        let success = webAuthAdminManager.updateUserEmoji(credentialId: credentialId, emoji: newEmoji)
        
        if success {
            let response = "{\"success\":true,\"message\":\"Emoji updated successfully\"}"
            sendResponse(connection, statusCode: "200 OK", contentType: "application/json", body: response)
        } else {
            sendResponse(connection, statusCode: "500 Internal Server Error", contentType: "application/json", body: "{\"error\":\"Failed to update emoji\"}")
        }
    }
    
    private func handleAdminAPIToggleAdmin(_ connection: NWConnection, request: String, path: String) {
        guard let bodyRange = request.range(of: "\r\n\r\n"),
              let bodyData = String(request[bodyRange.upperBound...]).data(using: .utf8),
              let requestData = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let newIsAdmin = requestData["isAdmin"] as? Bool else {
            sendResponse(connection, statusCode: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid request data\"}")
            return
        }
        
        // Extract credential ID from path /admin/api/users/{credentialId}/admin
        let pathComponents = path.components(separatedBy: "/")
        guard pathComponents.count >= 5 else {
            sendResponse(connection, statusCode: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid path\"}")
            return
        }
        
        let rawCredentialId = pathComponents[4]
        guard let credentialId = rawCredentialId.removingPercentEncoding else {
            sendResponse(connection, statusCode: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid credential ID encoding\"}")
            return
        }
        
        // Update admin status using WebAuthAdminManager
        let success = webAuthAdminManager.toggleUserAdminStatus(credentialId: credentialId, isAdmin: newIsAdmin)
        
        if success {
            let response = "{\"success\":true,\"message\":\"Admin role updated successfully\"}"
            sendResponse(connection, statusCode: "200 OK", contentType: "application/json", body: response)
        } else {
            sendResponse(connection, statusCode: "500 Internal Server Error", contentType: "application/json", body: "{\"error\":\"Failed to update admin role\"}")
        }
    }
    
    // MARK: - Admin Content Generation
    
    private func generateAdminIndexHTML() -> String {
        return WebAdminContent.generateAdminIndexHTML()
    }
    
    private func generateAdminCSS() -> String {
        return WebAdminContent.generateAdminCSS()
    }
    
    private func generateAdminJS() -> String {
        return WebAdminContent.generateAdminJS()
    }
    
    // MARK: - AdminManagerDelegate
    
    public func adminManager(_ manager: AdminManager, didAuthenticateUser username: String) -> Bool {
        // The WebAuthAdminManager already handled the actual authentication
        // This is just a final check that the user has admin privileges
        return webAuthAdminManager.verifyAdminAccess(username: username)
    }
    
    public func adminManager(_ manager: AdminManager, shouldAllowAdminAccess username: String) -> Bool {
        return webAuthAdminManager.shouldAllowAdminAccess(username: username)
    }
    
    // MARK: - Session Cleanup
    
    private func startPeriodicCleanup() {
        // Clean up expired sessions every 15 minutes
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 900) { [weak self] in
            self?.adminManager.cleanupExpiredSessions()
            self?.startPeriodicCleanup() // Schedule next cleanup
        }
    }
    
    // MARK: - WebAuthn Super Test Content Generation
    
    private func generateWebAuthnSuperTestHTML() -> String {
        // Try to read from static file first, otherwise return embedded content
        let staticPaths = [
            "static/webauthn-super-test.html",
            "./static/webauthn-super-test.html",
            FileManager.default.currentDirectoryPath + "/static/webauthn-super-test.html"
        ]
        
        for path in staticPaths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    let content = try String(contentsOfFile: path, encoding: .utf8)
                    print("📁 Serving webauthn-super-test.html from: \(path)")
                    return content
                } catch {
                    print("❌ Failed to read webauthn-super-test.html from \(path): \(error)")
                    continue
                }
            }
        }
        
        print("⚠️ Static webauthn-super-test.html not found, using embedded version")
        return getEmbeddedWebAuthnSuperTestHTML()
    }
    
    private func generateWebAuthnSuperTestJS() -> String {
        // Try to read from static file first, otherwise return embedded content
        let staticPaths = [
            "static/webauthn-super-test.js",
            "./static/webauthn-super-test.js",
            FileManager.default.currentDirectoryPath + "/static/webauthn-super-test.js"
        ]
        
        for path in staticPaths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    let content = try String(contentsOfFile: path, encoding: .utf8)
                    print("📁 Serving webauthn-super-test.js from: \(path)")
                    return content
                } catch {
                    print("❌ Failed to read webauthn-super-test.js from \(path): \(error)")
                    continue
                }
            }
        }
        
        print("⚠️ Static webauthn-super-test.js not found, using embedded version")
        return getEmbeddedWebAuthnSuperTestJS()
    }
    
    private func getEmbeddedWebAuthnSuperTestHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>🔐 WebAuthn Super Test - Complete FIDO1/FIDO2/Passkey Testing Lab</title>
            <style>
                * { box-sizing: border-box; }
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    margin: 0; padding: 20px;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    min-height: 100vh;
                }
                .container {
                    max-width: 1400px;
                    margin: 0 auto;
                    background: white;
                    border-radius: 12px;
                    box-shadow: 0 4px 20px rgba(0,0,0,0.15);
                    overflow: hidden;
                }
                .header {
                    background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
                    color: white;
                    padding: 30px;
                    text-align: center;
                }
                .header h1 { margin: 0; font-size: 2.5em; }
                .header p { margin: 10px 0 0 0; opacity: 0.9; }
                
                .main-content {
                    display: grid;
                    grid-template-columns: 300px 1fr;
                    min-height: 80vh;
                }
                
                .sidebar {
                    background: #f8f9fa;
                    border-right: 1px solid #dee2e6;
                    padding: 20px;
                    overflow-y: auto;
                }
                
                .content-area {
                    padding: 30px;
                    overflow-y: auto;
                }
                
                .section {
                    margin-bottom: 30px;
                    padding: 20px;
                    border: 1px solid #ddd;
                    border-radius: 8px;
                    background: #fafafa;
                }
                
                .section h3 {
                    margin: 0 0 15px 0;
                    color: #333;
                    border-bottom: 2px solid #007bff;
                    padding-bottom: 5px;
                }
                
                .form-group {
                    margin-bottom: 15px;
                }
                
                .form-group label {
                    display: block;
                    margin-bottom: 5px;
                    font-weight: 500;
                    color: #555;
                }
                
                .form-group select,
                .form-group input {
                    width: 100%;
                    padding: 8px 12px;
                    border: 1px solid #ddd;
                    border-radius: 4px;
                    font-size: 14px;
                }
                
                .checkbox-group {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 10px;
                    margin-top: 5px;
                }
                
                .checkbox-group label {
                    display: flex;
                    align-items: center;
                    margin: 0;
                    font-weight: normal;
                }
                
                .checkbox-group input {
                    width: auto;
                    margin-right: 5px;
                }
                
                button {
                    background: #007bff;
                    color: white;
                    border: none;
                    padding: 12px 24px;
                    border-radius: 6px;
                    cursor: pointer;
                    font-size: 14px;
                    margin: 5px 5px 5px 0;
                    transition: background 0.2s;
                }
                
                button:hover { background: #0056b3; }
                button:disabled { background: #6c757d; cursor: not-allowed; }
                
                .btn-large {
                    padding: 15px 30px;
                    font-size: 16px;
                    font-weight: 600;
                }
                
                .btn-success { background: #28a745; }
                .btn-success:hover { background: #1e7e34; }
                .btn-danger { background: #dc3545; }
                .btn-danger:hover { background: #c82333; }
                .btn-warning { background: #ffc107; color: #212529; }
                .btn-warning:hover { background: #e0a800; }
                
                .status {
                    margin: 15px 0;
                    padding: 12px;
                    border-radius: 6px;
                    font-weight: 500;
                    white-space: pre-wrap;
                }
                .status.info { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
                .status.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
                .status.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
                .status.warning { background: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
                
                .code-block {
                    background: #f8f9fa;
                    border: 1px solid #e9ecef;
                    border-radius: 6px;
                    padding: 15px;
                    font-family: 'Monaco', 'Consolas', monospace;
                    font-size: 12px;
                    max-height: 300px;
                    overflow-y: auto;
                    margin: 10px 0;
                }
                
                .debug-info {
                    background: #e9ecef;
                    border-radius: 6px;
                    padding: 15px;
                    margin: 10px 0;
                }
                
                .capabilities-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                    gap: 15px;
                    margin-top: 15px;
                }
                
                .capability-card {
                    background: white;
                    border: 1px solid #ddd;
                    border-radius: 6px;
                    padding: 15px;
                }
                
                .capability-card h4 {
                    margin: 0 0 10px 0;
                    color: #495057;
                }
                
                .nav-menu {
                    list-style: none;
                    padding: 0;
                    margin: 0;
                }
                
                .nav-menu li {
                    margin-bottom: 5px;
                }
                
                .nav-menu a {
                    display: block;
                    padding: 10px 15px;
                    color: #495057;
                    text-decoration: none;
                    border-radius: 4px;
                    transition: background 0.2s;
                }
                
                .nav-menu a:hover,
                .nav-menu a.active {
                    background: #007bff;
                    color: white;
                }
                
                .tab-content {
                    display: none;
                }
                
                .tab-content.active {
                    display: block;
                }
                
                .settings-export {
                    background: #e7f3ff;
                    border: 1px solid #b3d4fc;
                    border-radius: 6px;
                    padding: 15px;
                    margin: 20px 0;
                }
                
                @media (max-width: 1024px) {
                    .main-content {
                        grid-template-columns: 1fr;
                    }
                    .sidebar {
                        order: 2;
                        border-right: none;
                        border-top: 1px solid #dee2e6;
                    }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🔐 WebAuthn Super Test Lab</h1>
                    <p>Complete FIDO1/FIDO2/WebAuthn Testing & Troubleshooting Platform</p>
                    <p>🔬 Test Everything • 🐛 Debug Issues • 💾 Save Working Configs • 🚀 Production Ready</p>
                </div>
                
                <div class="main-content">
                    <div class="sidebar">
                        <ul class="nav-menu">
                            <li><a href="#" onclick="showTab('browser-info')" class="active">🔍 Browser Info</a></li>
                            <li><a href="#" onclick="showTab('registration-test')">📝 Registration Tests</a></li>
                            <li><a href="#" onclick="showTab('authentication-test')">🔐 Authentication Tests</a></li>
                            <li><a href="#" onclick="showTab('advanced-options')">⚙️ Advanced Options</a></li>
                            <li><a href="#" onclick="showTab('transport-test')">🚀 Transport Tests</a></li>
                            <li><a href="#" onclick="showTab('algorithm-test')">🔢 Algorithm Tests</a></li>
                            <li><a href="#" onclick="showTab('passkey-test')">🔑 Passkey Tests</a></li>
                            <li><a href="#" onclick="showTab('hardware-test')">🔧 Hardware Tests</a></li>
                            <li><a href="#" onclick="showTab('fido-test')">🏆 FIDO1/FIDO2 Tests</a></li>
                            <li><a href="#" onclick="showTab('debug-tools')">🐛 Debug Tools</a></li>
                            <li><a href="#" onclick="showTab('settings-export')">💾 Export Settings</a></li>
                        </ul>
                    </div>
                    
                    <div class="content-area">
                        <!-- All the tab content would go here - this is a condensed version -->
                        <div id="browser-info" class="tab-content active">
                            <div class="section">
                                <h3>🔍 Browser & Platform Detection</h3>
                                <div id="browser-detection" class="debug-info">Loading browser information...</div>
                                <button onclick="refreshBrowserInfo()">🔄 Refresh Info</button>
                                <button onclick="runCapabilityTests()">🧪 Run Capability Tests</button>
                            </div>
                        </div>
                        <!-- Other tabs would be included here in the full version -->
                    </div>
                </div>
            </div>

            <script src="/webauthn-super-test.js"></script>
        </body>
        </html>
        """
    }
    
    private func getEmbeddedWebAuthnSuperTestJS() -> String {
        return """
        // WebAuthn Super Test JavaScript
        console.log('🔐 WebAuthn Super Test Lab loading...');
        
        class WebAuthnSuperTest {
            constructor() {
                this.settings = this.getDefaultSettings();
                this.testResults = [];
                this.debugLog = [];
                this.browserInfo = {};
            }
            
            getDefaultSettings() {
                return {
                    timeout: 60000,
                    challengeSize: 32,
                    algorithms: [-7],
                    transports: ['usb', 'nfc', 'ble', 'internal', 'hybrid'],
                    extensions: {}
                };
            }
            
            async init() {
                console.log('🚀 Initializing WebAuthn Super Test...');
                this.detectBrowser();
                await this.checkCapabilities();
                this.updateBrowserDisplay();
                this.updateCapabilitiesDisplay();
                this.log('WebAuthn Super Test Lab initialized successfully');
            }
            
            detectBrowser() {
                const ua = navigator.userAgent;
                this.browserInfo = {
                    userAgent: ua,
                    platform: navigator.platform,
                    language: navigator.language,
                    cookieEnabled: navigator.cookieEnabled,
                    onLine: navigator.onLine,
                    webAuthnSupported: this.isWebAuthnSupported()
                };
            }
            
            isWebAuthnSupported() {
                return !!(navigator.credentials && navigator.credentials.create && navigator.credentials.get);
            }
            
            async checkCapabilities() {
                if (!this.isWebAuthnSupported()) {
                    this.browserInfo.capabilities = { error: 'WebAuthn not supported' };
                    return;
                }
                
                try {
                    const available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
                    this.browserInfo.capabilities = {
                        platformAuthenticator: available,
                        conditionalUI: PublicKeyCredential.isConditionalMediationAvailable ? await PublicKeyCredential.isConditionalMediationAvailable() : false
                    };
                } catch (error) {
                    this.browserInfo.capabilities = { error: error.message };
                }
            }
            
                         updateBrowserDisplay() {
                 const element = document.getElementById('browser-detection');
                 if (element) {
                     element.innerHTML = `
                         <div><strong>Browser:</strong> \\${this.getBrowserName()}</div>
                         <div><strong>Platform:</strong> \\${this.browserInfo.platform}</div>
                         <div><strong>WebAuthn Support:</strong> \\${this.browserInfo.webAuthnSupported ? '✅ Yes' : '❌ No'}</div>
                         <div><strong>User Agent:</strong> \\${this.browserInfo.userAgent}</div>
                     `;
                 }
             }
            
            getBrowserName() {
                const ua = this.browserInfo.userAgent;
                if (ua.includes('Chrome')) return 'Chrome';
                if (ua.includes('Firefox')) return 'Firefox';
                if (ua.includes('Safari')) return 'Safari';
                if (ua.includes('Edge')) return 'Edge';
                return 'Unknown';
            }
            
                         updateCapabilitiesDisplay() {
                 const element = document.getElementById('webauthn-capabilities');
                 if (element && this.browserInfo.capabilities) {
                     if (this.browserInfo.capabilities.error) {
                         element.innerHTML = `<div class="capability-card"><h4>Error</h4><p>\\${this.browserInfo.capabilities.error}</p></div>`;
                     } else {
                         element.innerHTML = `
                             <div class="capability-card">
                                 <h4>Platform Authenticator</h4>
                                 <p>\\${this.browserInfo.capabilities.platformAuthenticator ? '✅ Available' : '❌ Not Available'}</p>
                             </div>
                             <div class="capability-card">
                                 <h4>Conditional UI</h4>
                                 <p>\\${this.browserInfo.capabilities.conditionalUI ? '✅ Supported' : '❌ Not Supported'}</p>
                             </div>
                         `;
                     }
                 }
             }
            
                         log(message) {
                 const timestamp = new Date().toLocaleTimeString();
                 const logEntry = `[\\${timestamp}] \\${message}`;
                 this.debugLog.push(logEntry);
                 console.log(logEntry);
                 
                 const debugElement = document.getElementById('debug-log');
                 if (debugElement) {
                     debugElement.textContent = this.debugLog.join('\\n');
                     debugElement.scrollTop = debugElement.scrollHeight;
                 }
             }
            
                         showStatus(elementId, message, type = 'info') {
                 const element = document.getElementById(elementId);
                 if (element) {
                     element.textContent = message;
                     element.className = `status \\${type}`;
                     element.style.display = 'block';
                 }
                 this.log(`[\\${type.toUpperCase()}] \\${message}`);
             }
        }
        
        // Global instance
        let superTest;
        
        // Initialization function
        function initSuperTest() {
            superTest = new WebAuthnSuperTest();
            superTest.init();
        }
        
        function showTab(tabId) {
            // Hide all tabs
            document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
            });
            
            // Remove active class from all nav links
            document.querySelectorAll('.nav-menu a').forEach(link => {
                link.classList.remove('active');
            });
            
            // Show selected tab
            const selectedTab = document.getElementById(tabId);
            if (selectedTab) {
                selectedTab.classList.add('active');
            }
            
            // Add active class to clicked nav link
            event.target.classList.add('active');
        }
        
        function refreshBrowserInfo() {
            if (superTest) {
                superTest.detectBrowser();
                superTest.updateBrowserDisplay();
                superTest.log('Browser information refreshed');
            }
        }
        
        function runCapabilityTests() {
            if (superTest) {
                superTest.checkCapabilities().then(() => {
                    superTest.updateCapabilitiesDisplay();
                    superTest.log('Capability tests completed');
                });
            }
        }
        
        // Initialize when page loads
        document.addEventListener('DOMContentLoaded', initSuperTest);
        
        console.log('🔐 WebAuthn Super Test Lab loaded successfully');
        """
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

public class WebSocketClient {
    private let connection: NWConnection
    public var onMessage: ((String) -> Void)?
    public var onDisconnect: (() -> Void)?
    public var username: String?
    public var currentRoom: String?
    
    init(connection: NWConnection) {
        self.connection = connection
    }
    
    public func send(_ message: String) {
        let frame = createWebSocketFrame(message)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }
    
    public func disconnect() {
        connection.cancel()
    }
    
    func startReceiving() {
        receiveWebSocketFrame()
    }
    
    private func receiveWebSocketFrame() {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, data.count >= 2 else {
                self?.onDisconnect?()
                return
            }
            
            if let message = self.parseWebSocketFrame(data) {
                self.onMessage?(message)
            }
            
            // Continue receiving
            self.receiveWebSocketFrame()
        }
    }
    
    private func parseWebSocketFrame(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        
        let firstByte = data[0]
        let secondByte = data[1]
        
        let opcode = firstByte & 0x0F
        let masked = (secondByte & 0x80) != 0
        var payloadLength = Int(secondByte & 0x7F)
        
        var offset = 2
        
        // Handle extended payload length
        if payloadLength == 126 {
            guard data.count >= offset + 2 else { return nil }
            payloadLength = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2
        } else if payloadLength == 127 {
            guard data.count >= offset + 8 else { return nil }
            // For simplicity, we'll limit to smaller messages
            return nil
        }
        
        // Handle masking
        var maskingKey: [UInt8] = []
        if masked {
            guard data.count >= offset + 4 else { return nil }
            maskingKey = Array(data[offset..<offset + 4])
            offset += 4
        }
        
        // Extract payload
        guard data.count >= offset + payloadLength else { return nil }
        var payload = Array(data[offset..<offset + payloadLength])
        
        // Unmask if necessary
        if masked {
            for i in 0..<payload.count {
                payload[i] ^= maskingKey[i % 4]
            }
        }
        
        // Convert to string (assuming text frame)
        if opcode == 1 {
            return String(data: Data(payload), encoding: .utf8)
        }
        
        return nil
    }
    
    private func createWebSocketFrame(_ message: String) -> Data {
        let payload = message.data(using: .utf8)!
        var frame = Data()
        
        // First byte: FIN (1) + RSV (000) + Opcode (0001 for text)
        frame.append(0x81)
        
        // Second byte: MASK (0) + Payload length
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65536 {
            frame.append(126)
            frame.append(UInt8(payload.count >> 8))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            // For simplicity, we'll limit message size
            frame.append(126)
            frame.append(UInt8(65535 >> 8))
            frame.append(UInt8(65535 & 0xFF))
        }
        
        // Payload
        frame.append(payload)
        
        return frame
    }
}

// Extension for SHA1 hashing
extension Data {
    func sha1() -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(self.count), &digest)
        }
        return Data(digest)
    }
}
// MARK: - Additional Admin Functions (added for authentication)
extension WebServer {
    private func generateAdminLoginHTML() -> String {
        return WebAdminContent.generateAdminLoginHTML()
    }
    
    private func generateAdminLoginJS() -> String {
        return WebAdminContent.generateAdminLoginJS()
    }
    
    private func handleAdminLogin(_ connection: NWConnection, request: String) {
        print("[WebServer] 🔑 Admin login attempt")
        
        // Extract client IP
        let clientIPString = adminManager.extractClientIP(request, connection: connection)
        print("[WebServer] 🔍 Extracted client IP for admin login: \(clientIPString ?? "unknown")")
        
        // Extract request body
        guard let bodyStart = request.range(of: "\r\n\r\n")?.upperBound else {
            sendErrorResponse(connection, error: "Invalid request format")
            return
        }
        
        let bodyString = String(request[bodyStart...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let username = json["username"] as? String else {
            sendErrorResponse(connection, error: "Invalid request body")
            return
        }
        
        print("[WebServer] 🔑 Admin login for username: \(username)")
        
        do {
            // Authenticate using WebAuthAdminManager
            let authenticatedUsername = try webAuthAdminManager.authenticateAdmin(
                username: username,
                requestData: json,
                clientIP: clientIPString
            )
            
            guard let finalUsername = authenticatedUsername else {
                print("[WebServer] ❌ Admin authentication failed")
                sendErrorResponse(connection, error: "Authentication failed", statusCode: "401 Unauthorized")
                return
            }
            
            // Verify admin access
            guard webAuthAdminManager.verifyAdminAccess(username: finalUsername) else {
                print("[WebServer] ❌ User \(finalUsername) is not an admin or is disabled")
                sendErrorResponse(connection, error: "Access denied", statusCode: "403 Forbidden")
                return
            }
            
            // Create admin session using AdminManager
            let (sessionId, success) = adminManager.createAdminSession(username: finalUsername, clientIP: clientIPString)
            
            guard success else {
                print("[WebServer] ❌ Failed to create admin session for \(finalUsername)")
                sendErrorResponse(connection, error: "Session creation failed", statusCode: "500 Internal Server Error")
                return
            }
            
            print("[WebServer] ✅ Admin login successful for \(finalUsername)")
            
            // Return success with session ID
            let response: [String: Any] = [
                "success": true,
                "sessionId": sessionId,
                "username": finalUsername
            ]
            
            let responseData = try JSONSerialization.data(withJSONObject: response)
            let responseString = String(data: responseData, encoding: .utf8) ?? "{\"success\":true}"
            
            // Send response with Set-Cookie header for session
            let httpResponse = """
            HTTP/1.1 200 OK\r
            Content-Type: application/json\r
            Content-Length: \(responseString.utf8.count)\r
            Set-Cookie: adminSessionId=\(sessionId); HttpOnly; SameSite=Strict; Path=/admin\r
            Connection: close\r
            Access-Control-Allow-Origin: *\r
            \r
            \(responseString)
            """
            
            connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            
        } catch {
            print("[WebServer] ❌ Admin authentication failed: \(error)")
            sendErrorResponse(connection, error: "Authentication failed", statusCode: "401 Unauthorized")
        }
    }
}
