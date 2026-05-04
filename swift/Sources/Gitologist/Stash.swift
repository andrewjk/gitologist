import Foundation

enum StashError: Error, LocalizedError {
	case nothingToStash
	case headNotFound
	case notAGitRepository
	case noStashFound

	var errorDescription: String? {
		switch self {
		case .nothingToStash:
			return "Nothing to stash"
		case .headNotFound:
			return "HEAD not found"
		case .notAGitRepository:
			return "Not a git repository"
		case .noStashFound:
			return "No stash found"
		}
	}
}

func stash(at path: String, message: String = "WIP") async throws -> String {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw StashError.notAGitRepository
	}

	let currentStatus = try await status(at: path)

	let headCommitSha = try await getCurrentCommit(at: gitDir.path)
	guard let headCommitSha = headCommitSha else {
		throw StashError.headNotFound
	}

	let indexPath = gitDir.appendingPathComponent("index")
	var index = try await getIndex(at: indexPath.path)

	let headCommitData = try await readObject(at: gitDir.path, sha: headCommitSha)
	let headTreeSha = try extractTreeFromCommit(headCommitData)
	var headTreeEntries: [String: String] = [:]

	let headEntries = try parseTreeEntries(await readObject(at: gitDir.path, sha: headTreeSha))
	for entry in headEntries {
		headTreeEntries[entry.path] = entry.sha
	}

	var hasStagedChanges = false

	for (filePath, entry) in index {
		let headSha = headTreeEntries[filePath]
		if headSha != entry.sha {
			hasStagedChanges = true
			break
		}
	}

	if !hasStagedChanges && currentStatus.modified.isEmpty && currentStatus.untracked.isEmpty && currentStatus.deleted.isEmpty {
		throw StashError.nothingToStash
	}

	for file in currentStatus.modified {
		try await stageFile(at: path, gitDir: gitDir.path, filePath: file, index: &index)
	}

	for file in currentStatus.untracked {
		try await stageFile(at: path, gitDir: gitDir.path, filePath: file, index: &index)
	}

	for file in currentStatus.deleted {
		index.removeValue(forKey: file)
	}

	let treeSha = try await createTree(at: path, gitDir: gitDir.path, index: index)
	let stashCommitSha = try await createCommit(at: gitDir.path, treeSha: treeSha, message: message, parentSha: headCommitSha)

	let stashRefPath = gitDir.appendingPathComponent("refs").appendingPathComponent("stash")
	try FileManager.default.createDirectory(at: stashRefPath.deletingLastPathComponent(), withIntermediateDirectories: true)
	try "\(stashCommitSha)\n".write(to: stashRefPath, atomically: true, encoding: .utf8)

	try await resetHard(at: path, gitDir: gitDir.path, commitSha: headCommitSha)

	return stashCommitSha
}

private func stageFile(at repoPath: String, gitDir: String, filePath: String, index: inout [String: IndexEntry]) async throws {
	let fullPath = URL(fileURLWithPath: repoPath).appendingPathComponent(filePath)
	let content = try String(contentsOf: fullPath, encoding: .utf8)
	let hash = try await hashObject(at: gitDir, content: content, type: "blob")
	let attributes = try FileManager.default.attributesOfItem(atPath: fullPath.path)

	let fileSize = attributes[.size] as? UInt32 ?? 0
	let ctime = attributes[.creationDate] as? Date ?? Date()
	let mtime = attributes[.modificationDate] as? Date ?? Date()

	index[filePath] = IndexEntry(
		path: filePath,
		sha: hash,
		mode: "100644",
		size: fileSize,
		ctimeSeconds: UInt32(ctime.timeIntervalSince1970),
		ctimeNanos: 0,
		mtimeSeconds: UInt32(mtime.timeIntervalSince1970),
		mtimeNanos: 0,
		dev: 0,
		ino: 0,
		uid: 0,
		gid: 0
	)
}

private func resetHard(at path: String, gitDir: String, commitSha: String) async throws {
	let commitData = try await readObject(at: gitDir, sha: commitSha)
	let treeSha = try extractTreeFromCommit(commitData)

	let gitignore = IgnoreParser()
	await gitignore.loadGitignore(repoPath: path)

	var targetEntries = try await flattenTree(gitDir: gitDir, treeSha: treeSha)

	try await resetHardRecursive(at: path, repoPath: path, currentDir: path, gitDir: gitDir, gitignore: gitignore, targetEntries: &targetEntries)

	// Create any remaining target files
	for (filePath, sha) in targetEntries {
		let blobData = try await readObject(at: gitDir, sha: sha)
		let content = try extractContentFromBlob(blobData)
		let fullPath = URL(fileURLWithPath: path).appendingPathComponent(filePath)
		try FileManager.default.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true)
		try content.write(to: fullPath, atomically: true, encoding: .utf8)
	}

	try await updateIndex(gitDir: gitDir, workingPath: path, treeSha: treeSha)
}

private func resetHardRecursive(at path: String, repoPath: String, currentDir: String, gitDir: String, gitignore: IgnoreParser, targetEntries: inout [String: String]) async throws {
	let entries = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: currentDir), includingPropertiesForKeys: [.isDirectoryKey])

	for entry in entries {
		if entry.lastPathComponent == ".git" { continue }

		let relPath = relativePath(from: repoPath, to: entry.path)
		let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

		if await gitignore.isIgnored(filePath: relPath, isDirectory: isDir) {
			continue
		}

		if isDir {
			// Check if any target file is under this directory
			var hasTargetFiles = false
			for targetPath in targetEntries.keys {
				if targetPath == relPath || targetPath.hasPrefix(relPath + "/") {
					hasTargetFiles = true
					break
				}
			}

			if !hasTargetFiles {
				try? FileManager.default.removeItem(at: entry)
				continue
			}

			try await resetHardRecursive(at: path, repoPath: repoPath, currentDir: entry.path, gitDir: gitDir, gitignore: gitignore, targetEntries: &targetEntries)
		} else {
			if let targetSha = targetEntries[relPath] {
				let currentContent = try String(contentsOf: entry, encoding: .utf8)
				let currentHash = try await hashObject(at: gitDir, content: currentContent, type: "blob")

				if currentHash != targetSha {
					let blobData = try await readObject(at: gitDir, sha: targetSha)
					let content = try extractContentFromBlob(blobData)
					try content.write(to: entry, atomically: true, encoding: .utf8)
				}

				targetEntries.removeValue(forKey: relPath)
			} else {
				try? FileManager.default.removeItem(at: entry)
			}
		}
	}
}

private func relativePath(from base: String, to fullPath: String) -> String {
	let baseComponents = URL(fileURLWithPath: base).standardized.pathComponents
	let fullComponents = URL(fileURLWithPath: fullPath).standardized.pathComponents
	return fullComponents.dropFirst(baseComponents.count).joined(separator: "/")
}

private func restoreTree(at path: String, gitDir: String, treeSha: String, prefix: String) async throws {
	let treeData = try await readObject(at: gitDir, sha: treeSha)
	let entries = try parseTreeEntries(treeData)

	for entry in entries {
		let entryPath = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"

		if entry.type == .blob {
			let blobData = try await readObject(at: gitDir, sha: entry.sha)
			let content = try extractContentFromBlob(blobData)
			let fullPath = URL(fileURLWithPath: path).appendingPathComponent(entryPath)
			try FileManager.default.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true)
			try content.write(to: fullPath, atomically: true, encoding: .utf8)
		} else if entry.type == .tree {
			try await restoreTree(at: path, gitDir: gitDir, treeSha: entry.sha, prefix: entryPath)
		}
	}
}

func unstash(at path: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw StashError.notAGitRepository
	}

	let stashRefPath = gitDir.appendingPathComponent("refs").appendingPathComponent("stash")

	guard FileManager.default.fileExists(atPath: stashRefPath.path) else {
		throw StashError.noStashFound
	}

	let stashCommitSha = try String(contentsOf: stashRefPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

	let stashCommitData = try await readObject(at: gitDir.path, sha: stashCommitSha)
	let stashTreeSha = try extractTreeFromCommit(stashCommitData)

	guard let mergeBaseSha = extractParentFromCommit(stashCommitData) else {
		try await restoreTree(at: path, gitDir: gitDir.path, treeSha: stashTreeSha, prefix: "")
		return
	}

	guard let currentHeadSha = try await getCurrentCommit(at: gitDir.path) else {
		try await restoreTree(at: path, gitDir: gitDir.path, treeSha: stashTreeSha, prefix: "")
		return
	}

	if currentHeadSha == mergeBaseSha {
		try await restoreTree(at: path, gitDir: gitDir.path, treeSha: stashTreeSha, prefix: "")
		return
	}

	let mergeBaseTreeData = try await readObject(at: gitDir.path, sha: mergeBaseSha)
	let mergeBaseTreeSha = try extractTreeFromCommit(mergeBaseTreeData)
	let mergeBaseEntries = try await flattenTree(gitDir: gitDir.path, treeSha: mergeBaseTreeSha)

	let currentHeadData = try await readObject(at: gitDir.path, sha: currentHeadSha)
	let currentHeadTreeSha = try extractTreeFromCommit(currentHeadData)
	let currentHeadEntries = try await flattenTree(gitDir: gitDir.path, treeSha: currentHeadTreeSha)

	let stashEntries = try await flattenTree(gitDir: gitDir.path, treeSha: stashTreeSha)

	var mergedEntries: [String: String] = [:]

	for (filePath, sha) in stashEntries {
		let baseSha = mergeBaseEntries[filePath]
		let currentSha = currentHeadEntries[filePath]

		if currentSha == nil || currentSha == baseSha {
			mergedEntries[filePath] = sha
			continue
		}

		if sha == baseSha {
			mergedEntries[filePath] = currentSha
			continue
		}

		let baseContent = try baseSha != nil ? (await readBlobContent(gitDir: gitDir.path, sha: baseSha!)) : ""
		let stashContent = try await readBlobContent(gitDir: gitDir.path, sha: sha)
		let currentContent = try await readBlobContent(gitDir: gitDir.path, sha: currentSha!)

		let merged = threeWayMerge(base: baseContent, theirs: stashContent, ours: currentContent)
		let mergedSha = try await hashObject(at: gitDir.path, content: merged, type: "blob")
		mergedEntries[filePath] = mergedSha
	}

	for (filePath, sha) in currentHeadEntries {
		if mergedEntries[filePath] != nil { continue }

		if let baseSha = mergeBaseEntries[filePath], baseSha != sha {
			mergedEntries[filePath] = sha
		}
	}

	for (filePath, sha) in mergedEntries {
		let content = try await readBlobContent(gitDir: gitDir.path, sha: sha)
		let fullPath = URL(fileURLWithPath: path).appendingPathComponent(filePath)
		try FileManager.default.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true)
		try content.write(to: fullPath, atomically: true, encoding: .utf8)
	}
}

private func extractParentFromCommit(_ commitData: String) -> String? {
	let lines = commitData.components(separatedBy: "\n")
	for line in lines {
		if line.hasPrefix("parent ") {
			return String(line.dropFirst(7))
		}
		if line.isEmpty {
			break
		}
	}
	return nil
}

private func flattenTree(gitDir: String, treeSha: String, prefix: String = "") async throws -> [String: String] {
	var entries: [String: String] = [:]
	let treeData = try await readObject(at: gitDir, sha: treeSha)
	let treeEntries = try parseTreeEntries(treeData)

	for entry in treeEntries {
		let entryPath = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"

		if entry.type == .blob {
			entries[entryPath] = entry.sha
		} else if entry.type == .tree {
			let subEntries = try await flattenTree(gitDir: gitDir, treeSha: entry.sha, prefix: entryPath)
			for (subPath, subSha) in subEntries {
				entries[subPath] = subSha
			}
		}
	}

	return entries
}

private func readBlobContent(gitDir: String, sha: String) async throws -> String {
	let blobData = try await readObject(at: gitDir, sha: sha)
	return try extractContentFromBlob(blobData)
}

private func threeWayMerge(base: String, theirs: String, ours: String) -> String {
	let baseLines = base.components(separatedBy: "\n")
	let theirsLines = theirs.components(separatedBy: "\n")
	let oursLines = ours.components(separatedBy: "\n")

	if base == ours { return theirs }
	if base == theirs { return ours }

	let baseToTheirs = diffLines(base: baseLines, modified: theirsLines)
	let baseToOurs = diffLines(base: baseLines, modified: oursLines)

	var result: [String] = []
	var bi = 0
	var ti = 0
	var oi = 0

	while bi < baseLines.count {
		let theirsChange = baseToTheirs[bi]
		let oursChange = baseToOurs[bi]

		if let tc = theirsChange, let oc = oursChange {
			if tc.type == "replace" && oc.type == "replace" {
				if tc.lines == oc.lines {
					result.append(contentsOf: tc.lines)
				} else {
					result.append("<<<<<<< Updated upstream")
					result.append(contentsOf: oc.lines)
					result.append("=======")
					result.append(contentsOf: tc.lines)
					result.append(">>>>>>> Stashed changes")
				}
			} else if tc.type == "delete" && oc.type == "delete" {
				// Both deleted
			} else if tc.type == "insert" && oc.type == "insert" {
				if tc.lines == oc.lines {
					result.append(contentsOf: tc.lines)
				} else {
					result.append(contentsOf: oc.lines)
					result.append(contentsOf: tc.lines)
				}
			} else {
				result.append("<<<<<<< Updated upstream")
				result.append(contentsOf: oc.lines)
				result.append("=======")
				result.append(contentsOf: tc.lines)
				result.append(">>>>>>> Stashed changes")
			}
		} else if let tc = theirsChange {
			result.append(contentsOf: tc.lines)
		} else if let oc = oursChange {
			result.append(contentsOf: oc.lines)
		} else {
			result.append(baseLines[bi])
		}

		bi += 1
		ti += (theirsChange?.skip ?? 0) + 1
		oi += (oursChange?.skip ?? 0) + 1
	}

	while ti < theirsLines.count {
		result.append(theirsLines[ti])
		ti += 1
	}
	while oi < oursLines.count {
		result.append(oursLines[oi])
		oi += 1
	}

	return result.joined(separator: "\n")
}

private struct DiffChange {
	let type: String
	let lines: [String]
	let skip: Int
}

private func diffLines(base: [String], modified: [String]) -> [Int: DiffChange] {
	var changes: [Int: DiffChange] = [:]
	let lcs = longestCommonSubsequence(a: base, b: modified)

	var bi = 0
	var mi = 0
	var lcsIdx = 0

	while bi < base.count || mi < modified.count {
		if lcsIdx < lcs.count && bi < base.count && mi < modified.count {
			if base[bi] == lcs[lcsIdx], modified[mi] == lcs[lcsIdx] {
				bi += 1
				mi += 1
				lcsIdx += 1
				continue
			}
		}

		let startBi = bi
		while bi < base.count && (lcsIdx >= lcs.count || base[bi] != lcs[lcsIdx]) {
			bi += 1
		}
		let baseCount = bi - startBi

		let startMi = mi
		while mi < modified.count && (lcsIdx >= lcs.count || modified[mi] != lcs[lcsIdx]) {
			mi += 1
		}
		let modCount = mi - startMi

		if baseCount > 0 || modCount > 0 {
			let modLines = Array(modified[startMi ..< mi])
			if baseCount == 0, modCount > 0 {
				changes[startBi] = DiffChange(type: "insert", lines: modLines, skip: 0)
			} else if baseCount > 0, modCount == 0 {
				changes[startBi] = DiffChange(type: "delete", lines: [], skip: baseCount - 1)
			} else {
				changes[startBi] = DiffChange(type: "replace", lines: modLines, skip: baseCount - 1)
			}
		}

		if lcsIdx < lcs.count, bi < base.count, base[bi] == lcs[lcsIdx] {
			bi += 1
			mi += 1
			lcsIdx += 1
		}
	}

	return changes
}

private func longestCommonSubsequence(a: [String], b: [String]) -> [String] {
	let m = a.count
	let n = b.count
	var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

	for i in 1 ... m {
		for j in 1 ... n {
			if a[i - 1] == b[j - 1] {
				dp[i][j] = dp[i - 1][j - 1] + 1
			} else {
				dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
			}
		}
	}

	var result: [String] = []
	var i = m
	var j = n
	while i > 0, j > 0 {
		if a[i - 1] == b[j - 1] {
			result.insert(a[i - 1], at: 0)
			i -= 1
			j -= 1
		} else if dp[i - 1][j] > dp[i][j - 1] {
			i -= 1
		} else {
			j -= 1
		}
	}

	return result
}
