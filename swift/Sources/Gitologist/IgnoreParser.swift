import Foundation

struct IgnorePattern {
	let pattern: String
	let isNegated: Bool
	let isDirectoryOnly: Bool
	let pathPrefix: String
}

public actor IgnoreParser {
	var patterns: [String: [IgnorePattern]] = [:]

	public func loadGitignore(repoPath: String) async {
		patterns.removeAll()
		await loadGitignoreRecursive(repoPath: repoPath, currentDir: repoPath)
	}

	private func loadGitignoreRecursive(repoPath: String, currentDir: String) async {
		let gitignorePath = (currentDir as NSString).appendingPathComponent(".gitignore")
		let relativeDir = calculateRelativePath(from: repoPath, to: currentDir)

		do {
			let content = try String(contentsOfFile: gitignorePath, encoding: .utf8)
			let parsedPatterns = parseGitignore(content: content, pathPrefix: relativeDir)
			if !parsedPatterns.isEmpty {
				patterns[relativeDir] = parsedPatterns
			}
		} catch {
			// No .gitignore file in this directory
		}

		// Recursively check subdirectories (but skip .git)
		do {
			let entries = try FileManager.default.contentsOfDirectory(atPath: currentDir)
			for entry in entries {
				if entry == ".git" { continue }
				let fullPath = (currentDir as NSString).appendingPathComponent(entry)
				var isDirectory: ObjCBool = false
				if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
					if isDirectory.boolValue {
						await loadGitignoreRecursive(repoPath: repoPath, currentDir: fullPath)
					}
				}
			}
		} catch {
			// Skip if can't read directory
		}
	}

	private func parseGitignore(content: String, pathPrefix: String) -> [IgnorePattern] {
		var result: [IgnorePattern] = []
		let lines = content.components(separatedBy: "\n")

		for var line in lines {
			line = line.trimmingCharacters(in: .whitespacesAndNewlines)

			// Skip empty lines and comments
			if line.isEmpty || line.hasPrefix("#") { continue }

			// Handle negation (!)
			let isNegated = line.hasPrefix("!")
			if isNegated {
				line = String(line.dropFirst())
			}

			// Handle directory-only patterns (trailing /)
			let isDirectoryOnly = line.hasSuffix("/")
			if isDirectoryOnly {
				line = String(line.dropLast())
			}

			// Skip empty pattern after processing
			if line.isEmpty { continue }

			result.append(IgnorePattern(
				pattern: line,
				isNegated: isNegated,
				isDirectoryOnly: isDirectoryOnly,
				pathPrefix: pathPrefix
			))
		}

		return result
	}

	public func isIgnored(filePath: String, isDirectory: Bool = false) -> Bool {
		let normalizedPath = filePath.replacingOccurrences(of: "\\", with: "/")
		let pathParts = normalizedPath.components(separatedBy: "/")

		var ignored = false

		for (_, patternList) in patterns {
			for pattern in patternList {
				if matchesPattern(filePath: normalizedPath, pathParts: pathParts, pattern: pattern, isDirectory: isDirectory) {
					ignored = !pattern.isNegated
				}
			}
		}

		return ignored
	}

	private func matchesPattern(filePath: String, pathParts: [String], pattern: IgnorePattern, isDirectory: Bool) -> Bool {
		// Check if pattern applies to this file based on path prefix
		if pattern.pathPrefix != "." {
			let prefixParts = pattern.pathPrefix.components(separatedBy: "/")
			if pathParts.count < prefixParts.count {
				return false
			}
			for (index, part) in prefixParts.enumerated() {
				if part != pathParts[index] {
					return false
				}
			}
		}

		// Get the relative path from the .gitignore location
		let relativePath: String
		if pattern.pathPrefix == "." {
			relativePath = filePath
		} else {
			let prefixLength = pattern.pathPrefix.count + 1
			relativePath = String(filePath.dropFirst(prefixLength))
		}

		// If directory-only pattern, only match directories
		if pattern.isDirectoryOnly && !isDirectory {
			return false
		}

		return matchPatternString(filePath: relativePath, pathParts: pathParts, pattern: pattern.pattern)
	}

	private func matchPatternString(filePath: String, pathParts _: [String], pattern: String) -> Bool {
		// Handle patterns with /
		if pattern.contains("/") {
			// Pattern with / is anchored
			var regexPattern = pattern
			if pattern.hasPrefix("/") {
				regexPattern = String(pattern.dropFirst())
			}

			// Handle ** (matches zero or more directories)
			regexPattern = regexPattern.replacingOccurrences(of: "**", with: "<<<DOUBLESTAR>>>")

			// Handle * (matches anything except /)
			regexPattern = regexPattern.replacingOccurrences(of: "*", with: "[^/]*")

			// Handle ? (matches single character except /)
			regexPattern = regexPattern.replacingOccurrences(of: "?", with: "[^/]")

			// Restore ** as .*
			regexPattern = regexPattern.replacingOccurrences(of: "<<<DOUBLESTAR>>>", with: ".*")

			// Escape other regex special characters
			regexPattern = escapeRegexExcept(regexPattern, except: "[^/].*$+()|")

			// Match pattern
			do {
				let regex = try NSRegularExpression(pattern: "^" + regexPattern + "(/.*)?$", options: [])
				let range = NSRange(filePath.startIndex..., in: filePath)
				return regex.firstMatch(in: filePath, options: [], range: range) != nil
			} catch {
				return false
			}
		} else {
			// Pattern without / matches at any depth
			let escapedPattern = escapeRegex(pattern).replacingOccurrences(of: "\\*\\*", with: ".*")
			var finalPattern = escapedPattern
			finalPattern = finalPattern.replacingOccurrences(of: "\\*", with: "[^/]*")
			finalPattern = finalPattern.replacingOccurrences(of: "\\?", with: ".")

			do {
				let regex = try NSRegularExpression(pattern: "(^|/)" + finalPattern + "$", options: [])
				let range = NSRange(filePath.startIndex..., in: filePath)
				return regex.firstMatch(in: filePath, options: [], range: range) != nil
			} catch {
				return false
			}
		}
	}

	private func escapeRegex(_ str: String) -> String {
		var result = ""
		for char in str {
			if ".*+?^${}()|[]\\".contains(char) {
				result += "\\" + String(char)
			} else {
				result += String(char)
			}
		}
		return result
	}

	private func escapeRegexExcept(_ str: String, except: String) -> String {
		let exceptSet = Set(except)
		var result = ""
		for char in str {
			if ".*+?^${}()|[]\\".contains(char) && !exceptSet.contains(char) {
				result += "\\" + String(char)
			} else {
				result += String(char)
			}
		}
		return result
	}

	private func calculateRelativePath(from basePath: String, to targetPath: String) -> String {
		guard targetPath.hasPrefix(basePath) else {
			return "."
		}

		let baseComponents = (basePath as NSString).pathComponents
		let targetComponents = (targetPath as NSString).pathComponents

		var result: [String] = []
		for i in baseComponents.count ..< targetComponents.count {
			result.append(targetComponents[i])
		}

		return result.isEmpty ? "." : result.joined(separator: "/")
	}

	// Test helper
	func setPatternsForTesting(_ testPatterns: [String: [IgnorePattern]]) {
		patterns = testPatterns
	}
}
