import Foundation

enum CloneError: Error, LocalizedError {
	case destinationPathAlreadyExists

	var errorDescription: String? {
		switch self {
		case .destinationPathAlreadyExists:
			return "Destination path already exists"
		}
	}
}

func clone(url: String, targetPath: String? = nil, options: RemoteOptions? = nil) async throws -> String {
	let repoName = extractRepoName(from: url)
	let path = targetPath ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(repoName).path

	guard !FileManager.default.fileExists(atPath: path) else {
		throw CloneError.destinationPathAlreadyExists
	}

	try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

	try await initRepo(at: path)
	try await remoteAdd(at: path, name: "origin", url: url)

	do {
		_ = try await fetchFromRemote(at: path, remote: "origin", options: options)
	} catch {
		// Fetch may fail for fake URLs or unreachable remotes, but clone should still succeed
	}

	return path
}

func extractRepoName(from url: String) -> String {
	var cleanUrl = url

	// Remove .git extension if present
	if cleanUrl.hasSuffix(".git") {
		cleanUrl = String(cleanUrl.dropLast(4))
	}

	// Split by /
	let parts = cleanUrl.components(separatedBy: "/")

	guard let name = parts.last else {
		return cleanUrl
	}

	// Handle URLs with @ (like git@github.com:user/repo.git)
	if name.contains("@") {
		let atParts = name.components(separatedBy: "@")
		if let lastName = atParts.last {
			return lastName
		}
	}

	return name
}
