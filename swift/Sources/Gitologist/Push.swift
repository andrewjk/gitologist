import Foundation

public enum PushError: Error, LocalizedError {
	case notAGitRepository
	case localBranchDoesNotExist(String)
	case uncommittedChanges
	case pushFailed(Int, String)
	case pushRejected(String)

	public var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .localBranchDoesNotExist(branch):
			return "Local branch '\(branch)' does not exist"
		case .uncommittedChanges:
			return "You have uncommitted changes. Commit or stash them before pushing."
		case let .pushFailed(status, text):
			return "Push failed: \(status) \(text)"
		case let .pushRejected(reason):
			return "Push rejected: \(reason)"
		}
	}
}

public func push(at path: String, remote: String? = nil, branch: String? = nil, options: RemoteOptions? = nil) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw PushError.notAGitRepository
	}

	let remoteName = remote ?? "origin"
	let branchName: String

	if let customBranch = branch {
		branchName = customBranch
	} else {
		branchName = try await getCurrentBranch(at: gitDir.path)
	}

	let localBranchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent(branchName)

	guard FileManager.default.fileExists(atPath: localBranchPath.path) else {
		throw PushError.localBranchDoesNotExist(branchName)
	}

	let currentStatus = try await status(at: path)

	guard currentStatus.modified.isEmpty, currentStatus.untracked.isEmpty, currentStatus.deleted.isEmpty else {
		throw PushError.uncommittedChanges
	}

	let commitSha = try String(contentsOf: localBranchPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

	let remoteUrl = await getRemoteUrl(at: gitDir.path, remoteName: remoteName)

	if let remoteUrl = remoteUrl, remoteUrl.hasPrefix("http://") || remoteUrl.hasPrefix("https://") {
		try await pushToRemote(remoteUrl: remoteUrl, commitSha: commitSha, branchName: branchName, gitDir: gitDir.path, options: options)
	}

	let remoteBranchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent(remoteName).appendingPathComponent(branchName)
	try FileManager.default.createDirectory(at: remoteBranchPath.deletingLastPathComponent(), withIntermediateDirectories: true)

	try "\(commitSha)\n".write(to: remoteBranchPath, atomically: true, encoding: .utf8)
}

private func pushToRemote(remoteUrl: String, commitSha: String, branchName: String, gitDir: String, options: RemoteOptions? = nil) async throws {
	var oldSha = String(repeating: "0", count: 40)

	do {
		let remoteRefs = try await discoverRefsForPush(remoteUrl: remoteUrl, options: options)
		if let remoteRef = remoteRefs.first(where: { $0.ref == "refs/heads/\(branchName)" }) {
			oldSha = remoteRef.sha
		}
	} catch {}

	let objects = try await enumerateObjects(at: gitDir, sha: commitSha)

	let packfile = createPackfile(objects)

	try await sendPush(remoteUrl: remoteUrl, oldSha: oldSha, newSha: commitSha, branchName: branchName, packfile: packfile, options: options)
}

private func discoverRefsForPush(remoteUrl: String, options: RemoteOptions? = nil) async throws -> [DiscoveredRef] {
	guard let url = URL(string: remoteUrl) else {
		throw PushError.pushFailed(0, "Invalid URL")
	}
	var components = URLComponents(url: url.appendingPathComponent("info/refs"), resolvingAgainstBaseURL: true)
	components?.queryItems = [URLQueryItem(name: "service", value: "git-receive-pack")]

	guard let fetchUrl = components?.url else {
		throw PushError.pushFailed(0, "Invalid URL")
	}

	var request = URLRequest(url: fetchUrl)
	request.httpMethod = "GET"
	request.setValue("application/x-git-receive-pack-advertisement", forHTTPHeaderField: "Accept")
	request.setValue("version=2", forHTTPHeaderField: "Git-Protocol")

	if let credentials = options?.credentials {
		let authString = "\(credentials.username):\(credentials.token)"
		if let authData = authString.data(using: .utf8) {
			let base64Auth = authData.base64EncodedString()
			request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
		}
	}

	let (data, response) = try await URLSession.shared.data(for: request)

	guard let httpResponse = response as? HTTPURLResponse else {
		throw PushError.pushFailed(0, "Invalid response")
	}

	if httpResponse.statusCode != 200 {
		return []
	}

	let lines = decodePktLines(data)
	var refs: [DiscoveredRef] = []
	var started = false

	for line in lines {
		if line.contains("# service=git-receive-pack") {
			started = true
			continue
		}
		if !started { continue }
		if line.isEmpty { continue }

		let parts = line.split(separator: " ", maxSplits: 1)
		if parts.count >= 2 {
			let sha = String(parts[0])
			guard sha.count == 40, sha.allSatisfy({ $0.isNumber || ($0.isLetter && $0.isASCII) }) else {
				continue
			}
			let refParts = String(parts[1]).split(separator: "\0")
			let ref = String(refParts[0])
			refs.append(DiscoveredRef(sha: sha, ref: ref))
		}
	}

	return refs
}

private func sendPush(remoteUrl: String, oldSha: String, newSha: String, branchName: String, packfile: Data, options: RemoteOptions? = nil) async throws {
	guard let url = URL(string: remoteUrl) else {
		throw PushError.pushFailed(0, "Invalid URL")
	}
	let serviceUrl = url.appendingPathComponent("git-receive-pack")

	var requestBody = Data()

	let refLine = "\(oldSha) \(newSha) refs/heads/\(branchName)\0report-status agent=stash/1.0\n"
	requestBody.append(encodePktLine(refLine))
	requestBody.append(encodePktLine(nil))
	requestBody.append(packfile)

	var request = URLRequest(url: serviceUrl)
	request.httpMethod = "POST"
	request.setValue("application/x-git-receive-pack-request", forHTTPHeaderField: "Content-Type")
	request.setValue("application/x-git-receive-pack-result", forHTTPHeaderField: "Accept")
	request.setValue("version=2", forHTTPHeaderField: "Git-Protocol")

	if let credentials = options?.credentials {
		let authString = "\(credentials.username):\(credentials.token)"
		if let authData = authString.data(using: .utf8) {
			let base64Auth = authData.base64EncodedString()
			request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
		}
	}

	request.httpBody = requestBody

	let (data, response) = try await URLSession.shared.data(for: request)

	guard let httpResponse = response as? HTTPURLResponse else {
		throw PushError.pushFailed(0, "Invalid response")
	}

	guard httpResponse.statusCode == 200 else {
		let errorText = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
		throw PushError.pushFailed(httpResponse.statusCode, errorText)
	}

	let lines = decodePktLines(data)
	for line in lines {
		if line.hasPrefix("ng ") {
			throw PushError.pushRejected(String(line.dropFirst(3)))
		}
	}
}

public func setUpstreamBranch(at path: String, remoteName: String, branchName: String) async throws {
	let configPath = URL(fileURLWithPath: path).appendingPathComponent(".git").appendingPathComponent("config")

	var configContent = ""
	if FileManager.default.fileExists(atPath: configPath.path) {
		configContent = try String(contentsOf: configPath, encoding: .utf8)
	}

	let lines = configContent.split(separator: "\n", omittingEmptySubsequences: false)

	var inBranchSection = false
	var foundBranchSection = false
	var insertIndex = -1

	for (index, line) in lines.enumerated() {
		let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

		guard let branchRegex = try? NSRegularExpression(pattern: "^\\[branch \"([^\"]+)\"\\]$") else {
			continue
		}
		let nsRange = NSRange(trimmed.startIndex..., in: trimmed)

		if let match = branchRegex.firstMatch(in: trimmed, options: [], range: nsRange) {
			if let nameRange = Range(match.range(at: 1), in: trimmed) {
				let name = String(trimmed[nameRange])
				if name == branchName {
					inBranchSection = true
					foundBranchSection = true
				} else {
					inBranchSection = false
				}
			}
			continue
		}

		if inBranchSection {
			if trimmed.hasPrefix("remote =") || trimmed.hasPrefix("merge =") {
				continue
			}
			if insertIndex == -1 {
				insertIndex = index
			}
		} else {
			if trimmed.hasPrefix("["), insertIndex == -1 {
				insertIndex = index
			}
		}
	}

	var outputLines: [String] = lines.map { String($0) }

	if !foundBranchSection {
		outputLines.append("")
		outputLines.append("[branch \"\(branchName)\"]")
		outputLines.append("\tremote = \(remoteName)")
		outputLines.append("\tmerge = refs/heads/\(branchName)")
	} else {
		if insertIndex == -1 {
			insertIndex = outputLines.count
		}
		outputLines.insert("\tremote = \(remoteName)", at: insertIndex)
		outputLines.insert("\tmerge = refs/heads/\(branchName)", at: insertIndex + 1)
	}

	let newConfigContent = outputLines.joined(separator: "\n")
	try newConfigContent.write(to: configPath, atomically: true, encoding: .utf8)
}
