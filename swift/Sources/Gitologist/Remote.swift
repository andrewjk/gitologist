import Foundation

enum RemoteError: Error, LocalizedError {
	case notAGitRepository
	case remoteAlreadyExists(String)

	var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .remoteAlreadyExists(name):
			return "Remote '\(name)' already exists"
		}
	}
}

func remoteAdd(at path: String, name: String, url: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw RemoteError.notAGitRepository
	}

	let configPath = gitDir.appendingPathComponent("config")
	var configContent = ""

	if FileManager.default.fileExists(atPath: configPath.path) {
		configContent = try String(contentsOf: configPath, encoding: .utf8)
	}

	let remotePattern = "\\[remote \"\(name)\"\\]"
	let regex = try NSRegularExpression(pattern: remotePattern, options: [])
	let range = NSRange(location: 0, length: configContent.utf16.count)

	if regex.firstMatch(in: configContent, options: [], range: range) != nil {
		throw RemoteError.remoteAlreadyExists(name)
	}

	let remoteConfig = """
	[remote "\(name)"]
		url = \(url)
		fetch = +refs/heads/*:refs/remotes/\(name)/*
	"""

	configContent = configContent.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + remoteConfig.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"

	try configContent.write(to: configPath, atomically: true, encoding: .utf8)
}
