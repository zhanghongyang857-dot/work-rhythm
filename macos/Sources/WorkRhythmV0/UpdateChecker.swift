import AppKit
import Foundation

struct AvailableRelease: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(AvailableRelease)
    case unavailable(String)
}

enum UpdateCheckerError: LocalizedError {
    case noPublicRelease
    case invalidResponse
    case invalidVersion

    var errorDescription: String? {
        switch self {
        case .noPublicRelease:
            "暂时没有可下载的新版本。"
        case .invalidResponse:
            "无法读取 GitHub 的版本信息。"
        case .invalidVersion:
            "最新版本号格式无法识别。"
        }
    }
}

enum UpdateChecker {
    // This remains a public GitHub Releases endpoint. Keep it in sync with the release guide.
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/zhanghongyang857-dot/work-rhythm/releases/latest")!

    static func latestRelease() async throws -> AvailableRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WorkRhythm", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UpdateCheckerError.invalidResponse
        }
        guard response.statusCode != 404 else {
            throw UpdateCheckerError.noPublicRelease
        }
        guard (200...299).contains(response.statusCode) else {
            throw UpdateCheckerError.invalidResponse
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard SemanticVersion(release.tagName) != nil else {
            throw UpdateCheckerError.invalidVersion
        }
        return AvailableRelease(version: release.tagName, notes: release.body ?? "", pageURL: release.htmlURL)
    }

    static func isNewer(_ releaseVersion: String, than currentVersion: String) -> Bool {
        guard let release = SemanticVersion(releaseVersion), let current = SemanticVersion(currentVersion) else {
            return false
        }
        return release > current
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
        }
    }

    private struct SemanticVersion: Comparable {
        let components: [Int]

        init?(_ value: String) {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "v", with: "", options: [.anchored])
                .split(separator: "-", maxSplits: 1).first
            guard let normalized else { return nil }
            let values = normalized.split(separator: ".").map { Int($0) }
            guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
            components = values.compactMap { $0 }
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            let length = max(lhs.components.count, rhs.components.count)
            for index in 0..<length {
                let left = index < lhs.components.count ? lhs.components[index] : 0
                let right = index < rhs.components.count ? rhs.components[index] : 0
                if left != right { return left < right }
            }
            return false
        }
    }
}
