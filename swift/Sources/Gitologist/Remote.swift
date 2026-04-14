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

func hasRemote(at path: String, name: String = "origin") -> Bool {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		return false
	}

	let configPath = gitDir.appendingPathComponent("config")

	guard FileManager.default.fileExists(atPath: configPath.path),
	      let configContent = try? String(contentsOf: configPath, encoding: .utf8)
	else {
		return false
	}

	let remotePattern = "\\[remote \"\(name)\"\\]"
	guard let regex = try? NSRegularExpression(pattern: remotePattern, options: []) else {
		return false
	}

	let range = NSRange(location: 0, length: configContent.utf16.count)
	return regex.firstMatch(in: configContent, options: [], range: range) != nil
}

func getRemoteUrl(at gitDir: String, remoteName: String) async -> String? {
	let configPath = URL(fileURLWithPath: gitDir).appendingPathComponent("config")

	guard FileManager.default.fileExists(atPath: configPath.path) else {
		return nil
	}

	guard let configContent = try? String(contentsOf: configPath, encoding: .utf8) else {
		return nil
	}

	let lines = configContent.split(separator: "\n")

	var inRemoteSection = false
	var currentRemote = ""

	for line in lines {
		let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

		let remotePattern = "^\\[remote \"([^\"]+)\"\\]$"
		guard let regex = try? NSRegularExpression(pattern: remotePattern) else {
			continue
		}
		let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
		if let match = regex.firstMatch(in: trimmed, options: [], range: nsRange) {
			inRemoteSection = true
			if let nameRange = Range(match.range(at: 1), in: trimmed) {
				currentRemote = String(trimmed[nameRange])
			}
			continue
		}

		if inRemoteSection, currentRemote == remoteName {
			let urlPattern = "^url\\s*=\\s*(.+)$"
			guard let urlRegex = try? NSRegularExpression(pattern: urlPattern) else {
				continue
			}
			let urlNsRange = NSRange(trimmed.startIndex..., in: trimmed)
			if let urlMatch = urlRegex.firstMatch(in: trimmed, options: [], range: urlNsRange) {
				if let urlRange = Range(urlMatch.range(at: 1), in: trimmed) {
					return String(trimmed[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
				}
			}
		}

		if trimmed.hasPrefix("["), !trimmed.hasPrefix("[remote") {
			inRemoteSection = false
		}
	}

	return nil
}
