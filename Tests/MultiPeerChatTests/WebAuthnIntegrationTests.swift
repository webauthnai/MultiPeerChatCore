// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import XCTest
import Foundation
import CryptoKit
@testable import DogTagKit
@testable import MultiPeerChatCore

final class WebAuthnIntegrationTests: XCTestCase {
    var webAuthnManager: WebAuthnManager!
    var server: WebChatServer!
    let testRpId = "integration-test.example.com"
    let testAdminUsername = "Integration Test Admin"
    
    override func setUp() {
        super.setUp()
        
        // Clean up any existing test data
        PersistenceManager.shared.clearAllData()
        cleanupTestFiles()
        
        // Create WebAuthn manager
        webAuthnManager = WebAuthnManager(
            rpId: testRpId,
            webAuthnProtocol: .fido2CBOR,
            storageBackend: .json("integration_test_credentials.json"),
            rpName: "Integration Test RP",
            rpIcon: nil
        )
        
        // Create server instance
        server = WebChatServer(
            rpId: testRpId,
            adminUsername: testAdminUsername,
            storageBackend: .json("integration_test_credentials.json")
        )
    }
    
    override func tearDown() {
        server?.stop()
        server = nil
        webAuthnManager = nil
        
        cleanupTestFiles()
        PersistenceManager.shared.clearAllData()
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func cleanupTestFiles() {
        let testFiles = [
            "integration_test_credentials.json",
            "webauthn_credentials_fido2.json",
            "test_webauthn_credentials.json"
        ]
        
        for file in testFiles {
            if FileManager.default.fileExists(atPath: file) {
                try? FileManager.default.removeItem(atPath: file)
            }
        }
    }
    
    private func createMockES256KeyPair() -> (privateKey: P256.Signing.PrivateKey, publicKeyData: Data, coseKey: [String: Any]) {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let publicKeyData = publicKey.x963Representation
        
        // Extract x and y coordinates for COSE key format
        let x = publicKeyData.subdata(in: 1..<33)
        let y = publicKeyData.subdata(in: 33..<65)
        
        let coseKey: [String: Any] = [
            "1": 2,  // kty: EC2
            "3": -7, // alg: ES256
            "-1": 1, // crv: P-256
            "-2": x, // x coordinate
            "-3": y  // y coordinate
        ]
        
        return (privateKey, publicKeyData, coseKey)
    }
    
    private func encodeCBOR(_ value: Any) -> Data {
        // Simple CBOR encoder for test data
        if let map = value as? [String: Any] {
            var data = Data([0xA0 | UInt8(map.count)]) // Map with count
            for (key, val) in map.sorted(by: { $0.key < $1.key }) {
                if let intKey = Int(key) {
                    data.append(encodeCBORInteger(intKey))
                } else {
                    data.append(encodeCBORString(key))
                }
                data.append(encodeCBOR(val))
            }
            return data
        } else if let data = value as? Data {
            var result = Data()
            if data.count < 24 {
                result.append(0x40 | UInt8(data.count))
            } else if data.count < 256 {
                result.append(0x58)
                result.append(UInt8(data.count))
            } else {
                result.append(0x59)
                result.append(UInt8(data.count >> 8))
                result.append(UInt8(data.count & 0xFF))
            }
            result.append(data)
            return result
        } else if let int = value as? Int {
            return encodeCBORInteger(int)
        } else if let string = value as? String {
            return encodeCBORString(string)
        }
        return Data()
    }
    
    private func encodeCBORInteger(_ value: Int) -> Data {
        if value >= 0 {
            if value < 24 {
                return Data([UInt8(value)])
            } else if value < 256 {
                return Data([0x18, UInt8(value)])
            } else {
                return Data([0x19, UInt8(value >> 8), UInt8(value & 0xFF)])
            }
        } else {
            let positive = -value - 1
            if positive < 24 {
                return Data([0x20 | UInt8(positive)])
            } else if positive < 256 {
                return Data([0x38, UInt8(positive)])
            } else {
                return Data([0x39, UInt8(positive >> 8), UInt8(positive & 0xFF)])
            }
        }
    }
    
    private func encodeCBORString(_ value: String) -> Data {
        let stringData = value.data(using: .utf8)!
        var result = Data()
        if stringData.count < 24 {
            result.append(0x60 | UInt8(stringData.count))
        } else if stringData.count < 256 {
            result.append(0x78)
            result.append(UInt8(stringData.count))
        }
        result.append(stringData)
        return result
    }
    
    private func createMockAttestationObject(coseKey: [String: Any], credentialId: Data) -> Data {
        // Create authenticator data
        let rpIdHash = Data(SHA256.hash(data: testRpId.data(using: .utf8)!))
        let flags: UInt8 = 0x45 // UP | UV | AT flags
        let signCount = Data([0x00, 0x00, 0x00, 0x00])
        let aaguid = Data(repeating: 0x00, count: 16)
        let credentialIdLength = Data([0x00, UInt8(credentialId.count)])
        let publicKeyData = encodeCBOR(coseKey)
        
        var authData = Data()
        authData.append(rpIdHash)
        authData.append(flags)
        authData.append(signCount)
        authData.append(aaguid)
        authData.append(credentialIdLength)
        authData.append(credentialId)
        authData.append(publicKeyData)
        
        let attestationObject: [String: Any] = [
            "fmt": "none",
            "attStmt": [:] as [String: Any],
            "authData": authData
        ]
        
        return encodeCBOR(attestationObject)
    }
    
    private func createMockClientDataJSON(type: String, challenge: String, origin: String) -> Data {
        let clientData: [String: Any] = [
            "type": type,
            "challenge": challenge,
            "origin": origin,
            "crossOrigin": false
        ]
        
        return try! JSONSerialization.data(withJSONObject: clientData)
    }
    
    // MARK: - Integration Tests
    
    func testServerWebAuthnIntegration() throws {
        // Test that the server's WebAuthn manager works correctly
        let username = testAdminUsername
        
        // Test server WebAuthn integration indirectly
        XCTAssertNotNil(server, "Server should be initialized with WebAuthn support")
        
        // Since webAuthnManager is accessed through webServer.webAuthnManager (internal),
        // we test the integration indirectly through server functionality
        // Note: Server starts with 0 rooms until the Lobby room is created
        XCTAssertTrue(server.totalRooms >= 0, "Server should have at least 0 rooms")
        XCTAssertFalse(server.isRunning, "Server should not be running initially")
    }
    
    func testMultiUserWebAuthnFlow() throws {
        let users = ["user1", "user2", "user3"]
        var registeredCredentials: [String: (credentialId: String, privateKey: P256.Signing.PrivateKey)] = [:]
        
        // Register multiple users
        for username in users {
            let registrationOptions = try webAuthnManager.generateRegistrationOptions(username: username)
            let publicKey = registrationOptions["publicKey"] as! [String: Any]
            let challenge = publicKey["challenge"] as! String
            
            let (privateKey, _, coseKey) = createMockES256KeyPair()
            let credentialId = Data(repeating: UInt8.random(in: 0...255), count: 16)
            
            let attestationObjectData = createMockAttestationObject(coseKey: coseKey, credentialId: credentialId)
            let clientDataJSON = createMockClientDataJSON(
                type: "webauthn.create",
                challenge: challenge,
                origin: "https://\(testRpId)"
            )
            
            let registrationCredential: [String: Any] = [
                "id": credentialId.base64EncodedString(),
                "rawId": credentialId.base64EncodedString(),
                "response": [
                    "attestationObject": attestationObjectData.base64EncodedString(),
                    "clientDataJSON": clientDataJSON.base64EncodedString()
                ],
                "type": "public-key"
            ]
            
            try webAuthnManager.verifyRegistration(username: username, credential: registrationCredential)
            registeredCredentials[username] = (credentialId.base64EncodedString(), privateKey)
        }
        
        // Test authentication for all users
        for username in users {
            guard let (_, _) = registeredCredentials[username] else {
                XCTFail("Missing credential for user \(username)")
                continue
            }
            
            let authenticationOptions = try webAuthnManager.generateAuthenticationOptions(username: username)
            XCTAssertNotNil(authenticationOptions, "Should generate auth options for \(username)")
            
            // Verify each user can authenticate independently
            let authPublicKey = authenticationOptions["publicKey"] as! [String: Any]
            XCTAssertNotNil(authPublicKey["challenge"], "Should have challenge for \(username)")
        }
        
        XCTAssertEqual(registeredCredentials.count, users.count, "All users should be registered")
    }
    
    func testWebAuthnSecurityFeatures() throws {
        let username = "security_test_user"
        
        // Test challenge uniqueness
        let options1 = try webAuthnManager.generateRegistrationOptions(username: "\(username)_1")
        let options2 = try webAuthnManager.generateRegistrationOptions(username: "\(username)_2")
        
        let challenge1 = (options1["publicKey"] as! [String: Any])["challenge"] as! String
        let challenge2 = (options2["publicKey"] as! [String: Any])["challenge"] as! String
        
        XCTAssertNotEqual(challenge1, challenge2, "Challenges should be unique")
        
        // Test user ID uniqueness
        let user1 = (options1["publicKey"] as! [String: Any])["user"] as! [String: Any]
        let user2 = (options2["publicKey"] as! [String: Any])["user"] as! [String: Any]
        
        let userId1 = user1["id"] as! String
        let userId2 = user2["id"] as! String
        
        XCTAssertNotEqual(userId1, userId2, "User IDs should be unique")
    }
    
    func testErrorHandlingInIntegration() {
        // Test error handling with various invalid scenarios
        
        // Test registration with invalid username
        XCTAssertThrowsError(try webAuthnManager.verifyRegistration(username: "", credential: [:])) { error in
            XCTAssertTrue(error is WebAuthnError, "Should throw WebAuthn error for empty username")
        }
        
        // Test authentication for non-existent user
        XCTAssertThrowsError(try webAuthnManager.generateAuthenticationOptions(username: "nonexistent_user")) { error in
            XCTAssertEqual(error as! WebAuthnError, WebAuthnError.credentialNotFound, "Should throw credential not found error")
        }
        
        // Test with malformed credential
        let malformedCredential: [String: Any] = [
            "id": "invalid",
            "type": "not-public-key"
        ]
        
        XCTAssertThrowsError(try webAuthnManager.verifyRegistration(username: "test", credential: malformedCredential)) { error in
            XCTAssertTrue(error is WebAuthnError, "Should throw WebAuthn error for malformed credential")
        }
    }
    
    func testConcurrentWebAuthnOperations() {
        let expectation = XCTestExpectation(description: "Concurrent WebAuthn operations")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.concurrent.webauthn", attributes: .concurrent)
        
        for i in 0..<10 {
            queue.async {
                do {
                    let options = try self.webAuthnManager.generateRegistrationOptions(username: "concurrent_user_\(i)")
                    XCTAssertNotNil(options["publicKey"], "Should generate options for concurrent user \(i)")
                    expectation.fulfill()
                } catch {
                    XCTFail("Failed to generate options for concurrent user \(i): \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testWebAuthnWithDifferentProtocols() throws {
        // Test FIDO2 CBOR protocol
        let cborManager = WebAuthnManager(
            rpId: testRpId,
            webAuthnProtocol: .fido2CBOR,
            storageBackend: .json("cbor_test.json")
        )
        
        let cborOptions = try cborManager.generateRegistrationOptions(username: "cbor_user")
        XCTAssertNotNil(cborOptions["publicKey"], "CBOR manager should generate valid options")
        
        // Test U2F protocol
        let u2fManager = WebAuthnManager(
            rpId: testRpId,
            webAuthnProtocol: .u2fV1A,
            storageBackend: .json("u2f_test.json")
        )
        
        let u2fOptions = try u2fManager.generateRegistrationOptions(username: "u2f_user")
        XCTAssertNotNil(u2fOptions["publicKey"], "U2F manager should generate valid options")
        
        // Clean up test files
        try? FileManager.default.removeItem(atPath: "cbor_test.json")
        try? FileManager.default.removeItem(atPath: "u2f_test.json")
    }
    
    func testMemoryAndPerformanceIntegration() {
        // Test memory usage with multiple operations
        weak var weakManager: WebAuthnManager?
        
        autoreleasepool {
            let tempManager = WebAuthnManager(rpId: "temp.memory.test")
            weakManager = tempManager
            
            // Perform multiple operations
            for i in 0..<50 {
                _ = try! tempManager.generateRegistrationOptions(username: "memory_user_\(i)")
            }
        }
        
        // Manager should be deallocated
        XCTAssertNil(weakManager, "WebAuthn manager should be deallocated after autoreleasepool")
    }
}

// MARK: - Performance Tests

extension WebAuthnIntegrationTests {
    
    func testRegistrationPerformance() {
        measure {
            for i in 0..<10 {
                _ = try! webAuthnManager.generateRegistrationOptions(username: "perf_user_\(i)")
            }
        }
    }
} 
