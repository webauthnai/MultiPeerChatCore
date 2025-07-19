// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import Network
import DogTagKit

public protocol AdminManagerDelegate: AnyObject {
    func adminManager(_ manager: AdminManager, didAuthenticateUser username: String) -> Bool
    func adminManager(_ manager: AdminManager, shouldAllowAdminAccess username: String) -> Bool
}

public class AdminManager: ObservableObject {
    public weak var delegate: AdminManagerDelegate?
    
    private var adminSessions: [String: AdminSession] = [:]
    private let sessionTimeout: TimeInterval = 3600 // 1 hour
    private let configuredAdminUsername: String
    
    private struct AdminSession {
        let sessionId: String
        let username: String
        let loginTime: Date
        let clientIP: String
        
        var isExpired: Bool {
            Date().timeIntervalSince(loginTime) > 3600 // 1 hour timeout
        }
    }
    
    public init(adminUsername: String) {
        self.configuredAdminUsername = adminUsername
    }
    
    // MARK: - Session Management
    
    public func extractSessionId(from request: String) -> String? {
        // Check for session ID in Cookie header first (most common)
        let lines = request.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("cookie:") {
                let cookies = line.dropFirst(7).components(separatedBy: ";")
                for cookie in cookies {
                    let parts = cookie.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                    if parts.count == 2 && parts[0] == "adminSessionId" {
                        return parts[1]
                    }
                }
            }
        }
        
        // Check for session ID in Authorization header
        for line in lines {
            if line.lowercased().hasPrefix("authorization: bearer ") {
                return String(line.dropFirst(22).trimmingCharacters(in: .whitespaces))
            }
        }
        
        return nil
    }
    
    public func extractClientIP(_ request: String, connection: NWConnection) -> String? {
        // Parse headers into dictionary
        let lines = request.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        
        for line in lines {
            if line.isEmpty { break } // Stop at header end
            if let colonRange = line.range(of: ":") {
                let key = String(line[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        // Try X-Forwarded-For header first
        if let forwardedFor = headers["x-forwarded-for"] {
            let clientIP = forwardedFor.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            print("[AdminManager] 🔍 Found X-Forwarded-For: \(forwardedFor) -> \(clientIP ?? "nil")")
            return clientIP
        }
        
        // Try X-Real-IP header
        if let realIP = headers["x-real-ip"] {
            print("[AdminManager] 🔍 Found X-Real-IP: \(realIP)")
            return realIP.trimmingCharacters(in: .whitespaces)
        }
        
        // Try to get from connection
        if let endpoint = connection.currentPath?.remoteEndpoint {
            switch endpoint {
            case .hostPort(let host, _):
                let hostIP = String(describing: host)
                print("[AdminManager] 🔍 Connection endpoint IP: \(hostIP)")
                return hostIP
            default:
                break
            }
        }
        
        print("[AdminManager] ⚠️ No IP found in headers or connection, returning nil")
        return nil
    }
    
    public func isValidAdminSession(_ request: String) -> Bool {
        // Extract session ID from request headers or cookies
        let sessionId = extractSessionId(from: request)
        
        guard let sessionId = sessionId,
              let session = adminSessions[sessionId],
              !session.isExpired else {
            print("[AdminManager] 🔒 No valid admin session found")
            return false
        }
        
        // CRITICAL: Verify the authenticated user matches the configured admin username
        guard session.username == configuredAdminUsername else {
            print("[AdminManager] 🔒 Session user '\(session.username)' does not match configured admin '\(configuredAdminUsername)'")
            adminSessions.removeValue(forKey: sessionId) // Remove invalid session
            return false
        }
        
        // Delegate to check if user is still valid
        guard delegate?.adminManager(self, shouldAllowAdminAccess: session.username) ?? false else {
            // Remove invalid session
            adminSessions.removeValue(forKey: sessionId)
            print("[AdminManager] 🔒 User \(session.username) not allowed admin access")
            return false
        }
        
        print("[AdminManager] ✅ Valid admin session for \(session.username)")
        return true
    }
    
    public func hasValidAdminSession(_ request: String) -> Bool {
        // If we have any valid admin sessions, allow access
        let validSessions = adminSessions.values.filter { !$0.isExpired }
        
        if !validSessions.isEmpty {
            print("[AdminManager] ✅ Found valid admin sessions - allowing admin API access")
            return true
        }
        
        // Also check for session cookie
        let sessionId = extractSessionId(from: request)
        if let sessionId = sessionId,
           let session = adminSessions[sessionId],
           !session.isExpired,
           session.username == configuredAdminUsername {
            print("[AdminManager] ✅ Valid session cookie found for admin API")
            return true
        }
        
        print("[AdminManager] 🔒 No valid admin sessions found")
        return false
    }
    
    public func createAdminSession(username: String, clientIP: String?) -> (sessionId: String, success: Bool) {
        // Verify this is the configured admin username
        guard username == configuredAdminUsername else {
            print("[AdminManager] ❌ Username \(username) does not match configured admin \(configuredAdminUsername)")
            return ("", false)
        }
        
        // Delegate authentication check
        guard delegate?.adminManager(self, didAuthenticateUser: username) ?? false else {
            print("[AdminManager] ❌ Admin authentication failed for \(username)")
            return ("", false)
        }
        
        // Create admin session
        let sessionId = UUID().uuidString
        let session = AdminSession(
            sessionId: sessionId,
            username: username,
            loginTime: Date(),
            clientIP: clientIP ?? "unknown"
        )
        
        // Store session
        adminSessions[sessionId] = session
        
        print("[AdminManager] ✅ Admin session created for \(username)")
        return (sessionId, true)
    }
    
    public func cleanupExpiredSessions() {
        let expiredSessionIds = adminSessions.compactMap { key, session in
            session.isExpired ? key : nil
        }
        
        for sessionId in expiredSessionIds {
            adminSessions.removeValue(forKey: sessionId)
        }
        
        if !expiredSessionIds.isEmpty {
            print("[AdminManager] 🧹 Cleaned up \(expiredSessionIds.count) expired admin sessions")
        }
    }
} 
