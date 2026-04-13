import Foundation

struct FetchResult {
	let remote: String
	var refs: [RefInfo]
}

struct RefInfo {
	let name: String
	let sha: String
}

enum FetchError: Error, LocalizedError {
	case notAGitRepository
	case failedToDiscoverRefs(Int, String)
	case failedToFetchPackfile(Int, String)
	case invalidURL

	var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .failedToDiscoverRefs(status, text):
			return "Failed to discover refs: \(status) \(text)"
		case let .failedToFetchPackfile(status, text):
			return "Failed to fetch packfile: \(status) \(text)"
		case .invalidURL:
			return "Invalid URL"
		}
	}
}

func fetchFromRemote(at path: String, remote: String? = nil) async throws -> FetchResult {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw FetchError.notAGitRepository
	}

	let remoteName = remote ?? "origin"
	guard let remoteUrl = await getRemoteUrl(at: gitDir.path, remoteName: remoteName) else {
		return FetchResult(remote: remoteName, refs: [])
	}

	let refs = try await discoverRefs(remoteUrl: remoteUrl)
	var result = FetchResult(remote: remoteName, refs: [])

	var wants: [String] = []
	var haves: [String] = []

	for ref in refs {
		if ref.ref.hasPrefix("refs/heads/") {
			let branchName = String(ref.ref.dropFirst("refs/heads/".count))
			let localRefPath = gitDir.appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent(branchName)

			if FileManager.default.fileExists(atPath: localRefPath.path) {
				let localSha = try String(contentsOf: localRefPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
				haves.append(localSha)
			}

			wants.append(ref.sha)
			result.refs.append(RefInfo(name: branchName, sha: ref.sha))
		}
	}

	if !wants.isEmpty {
		let objects = try await fetchPackfile(remoteUrl: remoteUrl, wants: wants, haves: haves)
		try await storeObjects(at: gitDir.path, objects: objects)
	}

	for ref in result.refs {
		let remoteRefPath = gitDir
			.appendingPathComponent("refs")
			.appendingPathComponent("remotes")
			.appendingPathComponent(remoteName)
			.appendingPathComponent(ref.name)
		try FileManager.default.createDirectory(at: remoteRefPath.deletingLastPathComponent(), withIntermediateDirectories: true)
		try "\(ref.sha)\n".write(to: remoteRefPath, atomically: true, encoding: .utf8)
	}

	return result
}

func storeObjects(at gitDir: String, objects: [PackObject]) async throws {
	for obj in objects {
		_ = try await hashObject(at: gitDir, data: obj.content, type: obj.type.rawValue)
	}
}

struct DiscoveredRef {
	let sha: String
	let ref: String
}

func discoverRefs(remoteUrl: String) async throws -> [DiscoveredRef] {
	guard let url = URL(string: remoteUrl) else {
		throw FetchError.invalidURL
	}
	var components = URLComponents(url: url.appendingPathComponent("info/refs"), resolvingAgainstBaseURL: true)
	components?.queryItems = [URLQueryItem(name: "service", value: "git-upload-pack")]

	guard let fetchUrl = components?.url else {
		throw FetchError.invalidURL
	}

	var request = URLRequest(url: fetchUrl)
	request.httpMethod = "GET"
	request.setValue("application/x-git-upload-pack-advertisement", forHTTPHeaderField: "Accept")
	request.setValue("version=2", forHTTPHeaderField: "Git-Protocol")

	let (data, response) = try await URLSession.shared.data(for: request)

	guard let httpResponse = response as? HTTPURLResponse else {
		throw FetchError.failedToDiscoverRefs(0, "Invalid response")
	}

	guard httpResponse.statusCode == 200 else {
		throw FetchError.failedToDiscoverRefs(httpResponse.statusCode, HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
	}

	let lines = decodePktLines(data)

	var refs: [DiscoveredRef] = []
	var started = false

	for line in lines {
		if line.contains("# service=git-upload-pack") {
			started = true
			continue
		}

		if !started {
			continue
		}
		if line.isEmpty {
			continue
		}

		let parts = line.split(separator: " ", maxSplits: 1)
		if parts.count >= 2 {
			let sha = String(parts[0])
			guard sha.count == 40, sha.allSatisfy({ $0.isNumber || ($0.isLetter && $0.isASCII) }) else {
				continue
			}
			let refParts = String(parts[1]).split(separator: "\0")
			guard !refParts.isEmpty else {
				continue
			}
			let ref = String(refParts[0])
			refs.append(DiscoveredRef(sha: sha, ref: ref))
		}
	}

	return refs
}

func fetchPackfile(remoteUrl: String, wants: [String], haves: [String]) async throws -> [PackObject] {
	guard let url = URL(string: remoteUrl) else {
		throw FetchError.invalidURL
	}
	let fetchUrl = url.appendingPathComponent("git-upload-pack")

	let requestBody = buildFetchRequest(wants: wants, haves: haves)

	var request = URLRequest(url: fetchUrl)
	request.httpMethod = "POST"
	request.setValue("application/x-git-upload-pack-request", forHTTPHeaderField: "Content-Type")
	request.setValue("application/x-git-upload-pack-result", forHTTPHeaderField: "Accept")
	request.httpBody = requestBody

	let (data, response) = try await URLSession.shared.data(for: request)

	guard let httpResponse = response as? HTTPURLResponse else {
		throw FetchError.failedToFetchPackfile(0, "Invalid response")
	}

	guard httpResponse.statusCode == 200 else {
		throw FetchError.failedToFetchPackfile(httpResponse.statusCode, HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
	}

	guard let packfileOffset = findPackfileStart(data) else {
		return []
	}

	let packfileData = data[packfileOffset...]
	return try parsePackfile(Data(packfileData))
}

func buildFetchRequest(wants: [String], haves: [String]) -> Data {
	var lines: [Data] = []

	for want in wants {
		lines.append(encodePktLine("want \(want)"))
	}

	for have in haves {
		lines.append(encodePktLine("have \(have)"))
	}

	lines.append(encodePktLine("done"))
	lines.append(encodePktLine(nil))

	return lines.reduce(Data(), +)
}

func findPackfileStart(_ data: Data) -> Data.Index? {
	let signature = Data("PACK".utf8)
	for i in 0 ..< (data.count - 4) {
		if data[i ..< (i + 4)] == signature {
			return i
		}
	}
	return nil
}
