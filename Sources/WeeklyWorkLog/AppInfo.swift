import Foundation

enum AppInfo {
    static let fallbackVersion = "1.5.0"
    static let fallbackReleaseDate = "2026-07-28"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackVersion
    }

    static var releaseDate: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDate") as? String
            ?? fallbackReleaseDate
    }
}
