import Foundation
import Security
import UIKit

enum KeychainVault {
    private static let service = "com.telefam.company.app.vault"
    private static let keyAccount = "master_aes_key_v1"
    private static let hwIdAccount = "device_hardware_secret_v1"

    static func loadOrCreateMasterKey() -> Data {
        if let existing = readKey(account: keyAccount), existing.count == 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: UInt8.min...UInt8.max)
            }
        }
        let data = Data(bytes)
        saveKey(account: keyAccount, data: data)
        return data
    }

    static func loadOrCreateHardwareSecretId() -> String {
        if let existing = readKey(account: hwIdAccount), let str = String(data: existing, encoding: .utf8) {
            return str
        }
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let combined = "\(vendorId):\(UUID().uuidString)"
        if let data = combined.data(using: .utf8) {
            saveKey(account: hwIdAccount, data: data)
        }
        return combined
    }

    static func hardwareModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(validatingUTF8: ptr) ?? UIDevice.current.model
            }
        }
    }

    static func deviceName() -> String {
        UIDevice.current.name
    }

    private static func readKey(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func saveKey(account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
