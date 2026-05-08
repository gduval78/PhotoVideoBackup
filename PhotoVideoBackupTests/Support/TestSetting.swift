import Foundation
@testable import PhotoVideoBackup

// Configuration changes applied before a backup run.
// Each case maps directly to a UserDefaults key read by the production code.
enum TestSetting {
    case folderOrganization(FolderOrganization)
    case maxFiles(Int)
    case additionalExtensions([String])

    func apply() {
        switch self {
        case .folderOrganization(let org):
            UserDefaults.standard.set(org.rawValue, forKey: "folderOrganization")
        case .maxFiles(let n):
            UserDefaults.standard.set(n, forKey: "backupFileLimit")
        case .additionalExtensions(let exts):
            UserDefaults.standard.set(exts.joined(separator: ","), forKey: "customExtensions")
        }
    }
}
