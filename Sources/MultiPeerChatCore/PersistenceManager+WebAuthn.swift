// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation
import DogTagKit

// MARK: - PersistenceManager WebAuthn Integration
// All user data is now stored in WebAuthn credentials

extension PersistenceManager: WebAuthnUserManager {
    
    /// Check if a user is enabled and can authenticate
    public func isUserEnabled(username: String) -> Bool {
        // Check if user exists in admin users (legacy system)
        if let adminUser = getAdminUser(by: username) {
            return adminUser.isEnabled
        }
        
        // If no admin user record exists, allow WebAuthn to handle it
        return true
    }
    
    /// Get user emoji for display
    public func getUserEmoji(username: String) -> String? {
        // All emoji data is now handled by WebAuthn credentials
        return nil
    }
    
    /// Update user emoji
    public func updateUserEmoji(username: String, emoji: String) -> Bool {
        // All emoji updates are now handled by WebAuthn credentials
        return false
    }
    
    /// Create or update user record after registration
    public func createUser(username: String, credentialId: String, publicKey: String, clientIP: String?, emoji: String) throws {
        // All user data is now stored in WebAuthn credentials - no additional records needed
        print("[WebAuthn] User \(username) created - all data stored in WebAuthn credentials")
    }
    
    /// Update user login information after authentication
    public func updateUserLogin(username: String, signCount: UInt32, clientIP: String?) throws {
        // All login tracking is now handled by WebAuthn credentials
        print("[WebAuthn] Login update for \(username) handled by WebAuthn credentials")
    }
    
    /// Delete user and associated data
    public func deleteUser(username: String) throws {
        // All user deletion is now handled by WebAuthn credentials
        print("[WebAuthn] User \(username) deletion handled by WebAuthn credentials")
    }
} 
