// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import XCTest
@testable import MultiPeerChatCore
@testable import DogTagKit

class AdminTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear any existing admin users
        PersistenceManager.shared.clearAllData()
    }
    
    override func tearDown() {
        // Clean up after tests
        PersistenceManager.shared.clearAllData()
        super.tearDown()
    }
    
    func testAdminUserCreation() {
        let adminUser = AdminUser(
            username: "testadmin",
            credentialId: "test-credential-id",
            publicKey: "test-public-key",
            signCount: 0,
            lastLoginIP: "127.0.0.1",
            userNumber: 1
        )
        
        // Test that admin user is created with proper defaults
        XCTAssertTrue(adminUser.isEnabled, "New admin user should be enabled by default")
        XCTAssertEqual(adminUser.username, "testadmin")
        XCTAssertEqual(adminUser.userNumber, 1)
    }
    
    func testAdminUserPersistence() {
        let adminUser = AdminUser(
            username: "persisttest",
            credentialId: "persist-credential",
            publicKey: "persist-public-key",
            signCount: 5,
            lastLoginIP: "192.168.1.1",
            userNumber: 2
        )
        
        // Save admin user
        PersistenceManager.shared.saveAdminUser(adminUser)
        
        // Load and verify
        let loadedUsers = PersistenceManager.shared.loadAdminUsers()
        XCTAssertEqual(loadedUsers.count, 1)
        
        let loadedUser = loadedUsers.first!
        XCTAssertEqual(loadedUser.username, "persisttest")
        XCTAssertEqual(loadedUser.credentialId, "persist-credential")
        XCTAssertEqual(loadedUser.signCount, 5)
        XCTAssertEqual(loadedUser.lastLoginIP, "192.168.1.1")
        XCTAssertTrue(loadedUser.isEnabled)
    }
    
    func testAdminUserToggle() {
        let adminUser = AdminUser(
            username: "toggletest",
            credentialId: "toggle-credential",
            publicKey: "toggle-public-key",
            signCount: 0,
            lastLoginIP: nil,
            userNumber: 3
        )
        
        PersistenceManager.shared.saveAdminUser(adminUser)
        
        // Toggle to disabled
        let disabledUser = adminUser.withEnabledStatus(false)
        PersistenceManager.shared.saveAdminUser(disabledUser)
        
        // Verify disabled
        let loadedUser = PersistenceManager.shared.getAdminUser(by: "toggletest")
        XCTAssertNotNil(loadedUser)
        XCTAssertFalse(loadedUser!.isEnabled)
        
        // Toggle back to enabled
        let enabledUser = disabledUser.withEnabledStatus(true)
        PersistenceManager.shared.saveAdminUser(enabledUser)
        
        // Verify enabled
        let reloadedUser = PersistenceManager.shared.getAdminUser(by: "toggletest")
        XCTAssertNotNil(reloadedUser)
        XCTAssertTrue(reloadedUser!.isEnabled)
    }
    
    func testDisableUsersByIP() {
        // Create multiple users with same IP
        let user1 = AdminUser(
            username: "user1",
            credentialId: "cred1",
            publicKey: "key1",
            signCount: 0,
            lastLoginIP: "10.0.0.1",
            userNumber: 1
        )
        
        let user2 = AdminUser(
            username: "user2",
            credentialId: "cred2",
            publicKey: "key2",
            signCount: 0,
            lastLoginIP: "10.0.0.1",
            userNumber: 2
        )
        
        let user3 = AdminUser(
            username: "user3",
            credentialId: "cred3",
            publicKey: "key3",
            signCount: 0,
            lastLoginIP: "10.0.0.2",
            userNumber: 3
        )
        
        // Save all users
        PersistenceManager.shared.saveAdminUser(user1)
        PersistenceManager.shared.saveAdminUser(user2)
        PersistenceManager.shared.saveAdminUser(user3)
        
        // Disable by IP
        PersistenceManager.shared.disableAdminUsersByIP("10.0.0.1")
        
        // Verify results
        let loadedUsers = PersistenceManager.shared.loadAdminUsers()
        
        let user1Loaded = loadedUsers.first { $0.username == "user1" }
        let user2Loaded = loadedUsers.first { $0.username == "user2" }
        let user3Loaded = loadedUsers.first { $0.username == "user3" }
        
        XCTAssertFalse(user1Loaded!.isEnabled, "User1 should be disabled (matching IP)")
        XCTAssertFalse(user2Loaded!.isEnabled, "User2 should be disabled (matching IP)")
        XCTAssertTrue(user3Loaded!.isEnabled, "User3 should remain enabled (different IP)")
    }
    
    func testWebAuthnUserEnabledCheck() {
        let webAuthnManager = WebAuthnManager(
            rpId: "localhost",
            storageBackend: .json(""),
            rpName: "Test",
            rpIcon: nil,
            userManager: PersistenceManager.shared
        )
        
        // Create disabled user
        let disabledUser = AdminUser(
            username: "disableduser",
            credentialId: "disabled-cred",
            publicKey: "disabled-key",
            signCount: 0,
            lastLoginIP: nil,
            userNumber: 1
        ).withEnabledStatus(false)
        
        PersistenceManager.shared.saveAdminUser(disabledUser)
        
        // Test user enabled check (only test username-based check since no WebAuthn credential exists)
        XCTAssertFalse(webAuthnManager.isUserEnabled(username: "disableduser"))
        
        // Enable user and test again
        let enabledUser = disabledUser.withEnabledStatus(true)
        PersistenceManager.shared.saveAdminUser(enabledUser)
        
        XCTAssertTrue(webAuthnManager.isUserEnabled(username: "disableduser"))
    }
    
    func testGetNextUserNumber() {
        // Test with no existing users
        XCTAssertEqual(PersistenceManager.shared.getNextUserNumber(), 1)
        
        // Add a user
        let user1 = AdminUser(
            username: "user1",
            credentialId: "cred1",
            publicKey: "key1",
            signCount: 0,
            lastLoginIP: nil,
            userNumber: 5 // Non-sequential number
        )
        PersistenceManager.shared.saveAdminUser(user1)
        
        // Next number should be 6
        XCTAssertEqual(PersistenceManager.shared.getNextUserNumber(), 6)
        
        // Add another user
        let user2 = AdminUser(
            username: "user2",
            credentialId: "cred2",
            publicKey: "key2",
            signCount: 0,
            lastLoginIP: nil,
            userNumber: 10
        )
        PersistenceManager.shared.saveAdminUser(user2)
        
        // Next number should be 11
        XCTAssertEqual(PersistenceManager.shared.getNextUserNumber(), 11)
    }
    
    func testIPTracking() {
        // Test IP tracking during user creation and login
        let testIP = "192.168.1.100"
        
        // Create user with IP
        let adminUser = AdminUser(
            username: "iptest",
            credentialId: "ip-credential",
            publicKey: "ip-public-key",
            signCount: 0,
            lastLoginIP: testIP,
            userNumber: 1
        )
        
        PersistenceManager.shared.saveAdminUser(adminUser)
        
        // Verify IP is stored
        let loadedUser = PersistenceManager.shared.getAdminUser(by: "iptest")
        XCTAssertNotNil(loadedUser)
        XCTAssertEqual(loadedUser!.lastLoginIP, testIP)
        
        // Test login update with different IP
        let newIP = "10.0.0.1"
        let updatedUser = loadedUser!.updatedWithLogin(ip: newIP, signCount: 5)
        PersistenceManager.shared.saveAdminUser(updatedUser)
        
        // Verify IP and login data are updated
        let reloadedUser = PersistenceManager.shared.getAdminUser(by: "iptest")
        XCTAssertNotNil(reloadedUser)
        XCTAssertEqual(reloadedUser!.lastLoginIP, newIP)
        XCTAssertEqual(reloadedUser!.signCount, 5)
        XCTAssertNotNil(reloadedUser!.lastLoginAt)
        
        // Test that created time doesn't change on login update
        XCTAssertEqual(reloadedUser!.createdAt, adminUser.createdAt)
    }
} 
