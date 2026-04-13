import Foundation

enum PushError: Error, LocalizedError {
	case notAGitRepository
	case localBranchDoesNotExist(String)
	case uncommittedChanges
	case pushFailed(Int, String)
	case pushRejected(String)

	var errorDescription: String? {
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

func push(at path: String, remote: String? = nil, branch: String? = nil) async throws {
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

	guard currentStatus.modified.isEmpty, currentStatus.untracked.isEmpty else {
		throw PushError.uncommittedChanges
	}

	let commitSha = try String(contentsOf: localBranchPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

	let remoteUrl = await getRemoteUrl(at: gitDir.path, remoteName: remoteName)

	if let remoteUrl = remoteUrl, remoteUrl.hasPrefix("http://") || remoteUrl.hasPrefix("https://") {
		try await pushToRemote(remoteUrl: remoteUrl, commitSha: commitSha, branchName: branchName, gitDir: gitDir.path)
	}

	let remoteBranchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent(remoteName).appendingPathComponent(branchName)
	try FileManager.default.createDirectory(at: remoteBranchPath.deletingLastPathComponent(), withIntermediateDirectories: true)

	try "\(commitSha)\n".write(to: remoteBranchPath, atomically: true, encoding: .utf8)
}

private func pushToRemote(remoteUrl: String, commitSha: String, branchName: String, gitDir: String) async throws {
	let remoteRefs = try await discoverRefsForPush(remoteUrl: remoteUrl)
	let remoteRef = remoteRefs.first { $0.ref == "refs/heads/\(branchName)" }
	let oldSha = remoteRef?.sha ?? String(repeating: "0", count: 40)

	let objects = try await enumerateObjects(at: gitDir, sha: commitSha)

	let packfile = createPackfile(objects)

	try await uploadPackfile(remoteUrl: remoteUrl, oldSha: oldSha, newSha: commitSha, branchName: branchName, packfile: packfile)
}

private func discoverRefsForPush(remoteUrl: String) async throws -> [DiscoveredRef] {
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

	let (data, response) = try await URLSession.shared.data(for: request)

	guard let httpResponse = response as? HTTPURLResponse else {
		throw PushError.pushFailed(0, "Invalid response")
	}

	guard httpResponse.statusCode == 200 else {
		throw PushError.pushFailed(httpResponse.statusCode, HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
	}

	let lines = decodePktLines(data)

	var refs: [DiscoveredRef] = []
	var started = false

	for line in lines {
		if line.contains("# service=git-receive-pack") {
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

private func uploadPackfile(remoteUrl: String, oldSha: String, newSha: String, branchName: String, packfile: Data) async throws {
	guard let url = URL(string: remoteUrl) else {
		throw PushError.pushFailed(0, "Invalid URL")
	}
	let uploadUrl = url.appendingPathComponent("git-receive-pack")

	let requestBody = buildPushRequest(oldSha: oldSha, newSha: newSha, branchName: branchName, packfile: packfile)

	var request = URLRequest(url: uploadUrl)
	request.httpMethod = "POST"
	request.setValue("application/x-git-receive-pack-request", forHTTPHeaderField: "Content-Type")
	request.setValue("application/x-git-receive-pack-result", forHTTPHeaderField: "Accept")
	request.httpBody = requestBody

	let (data, response) = try await URLSession.shared.data(for: request)

	guard let httpResponse = response as? HTTPURLResponse else {
		throw PushError.pushFailed(0, "Invalid response")
	}

	guard httpResponse.statusCode == 200 else {
		throw PushError.pushFailed(httpResponse.statusCode, HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
	}

	let lines = decodePktLines(data)

	for line in lines {
		if line.hasPrefix("ng ") {
			let reason = String(line.dropFirst(3))
			throw PushError.pushRejected(reason)
		}
	}
}

private func buildPushRequest(oldSha: String, newSha: String, branchName: String, packfile: Data) -> Data {
	var lines: [Data] = []

	lines.append(encodePktLine("\(oldSha) \(newSha) refs/heads/\(branchName)"))
	lines.append(encodePktLine(nil))
	lines.append(packfile)

	return lines.reduce(Data(), +)
}
