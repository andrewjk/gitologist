import { readFile } from "node:fs/promises";
import { join, relative } from "node:path";

interface IgnorePattern {
	pattern: string;
	isNegated: boolean;
	isDirectoryOnly: boolean;
	pathPrefix: string;
}

export class IgnoreParser {
	private patterns: Map<string, IgnorePattern[]> = new Map();

	async loadGitignore(repoPath: string): Promise<void> {
		this.patterns.clear();
		await this.loadGitignoreRecursive(repoPath, repoPath);
	}

	private async loadGitignoreRecursive(repoPath: string, currentDir: string): Promise<void> {
		const gitignorePath = join(currentDir, ".gitignore");
		const relativeDir = relative(repoPath, currentDir) || ".";

		try {
			const content = await readFile(gitignorePath, "utf-8");
			const patterns = this.parseGitignore(content, relativeDir);
			if (patterns.length > 0) {
				this.patterns.set(relativeDir, patterns);
			}
		} catch {
			// No .gitignore file in this directory
		}

		// Recursively check subdirectories (but skip .git)
		const { readdirSync, statSync } = await import("node:fs");
		try {
			const entries = readdirSync(currentDir);
			for (const entry of entries) {
				if (entry === ".git") continue;
				const fullPath = join(currentDir, entry);
				try {
					const stat = statSync(fullPath);
					if (stat.isDirectory()) {
						await this.loadGitignoreRecursive(repoPath, fullPath);
					}
				} catch {
					// Skip if can't stat
				}
			}
		} catch {
			// Skip if can't read directory
		}
	}

	private parseGitignore(content: string, pathPrefix: string): IgnorePattern[] {
		const patterns: IgnorePattern[] = [];
		const lines = content.split("\n");

		for (let line of lines) {
			line = line.trim();

			// Skip empty lines and comments
			if (!line || line.startsWith("#")) continue;

			// Handle negation (!)
			const isNegated = line.startsWith("!");
			if (isNegated) {
				line = line.slice(1);
			}

			// Handle directory-only patterns (trailing /)
			const isDirectoryOnly = line.endsWith("/");
			if (isDirectoryOnly) {
				line = line.slice(0, -1);
			}

			// Skip empty pattern after processing
			if (!line) continue;

			patterns.push({
				pattern: line,
				isNegated,
				isDirectoryOnly,
				pathPrefix,
			});
		}

		return patterns;
	}

	isIgnored(filePath: string, isDirectory = false): boolean {
		// Normalize path
		const normalizedPath = filePath.replace(/\\/g, "/");
		const pathParts = normalizedPath.split("/");

		// Check all applicable .gitignore files
		let ignored = false;

		for (const [, patterns] of this.patterns) {
			for (const pattern of patterns) {
				if (this.matchesPattern(normalizedPath, pathParts, pattern, isDirectory)) {
					ignored = !pattern.isNegated;
				}
			}
		}

		return ignored;
	}

	private matchesPattern(
		filePath: string,
		pathParts: string[],
		pattern: IgnorePattern,
		isDirectory: boolean,
	): boolean {
		// Check if pattern applies to this file based on path prefix
		if (pattern.pathPrefix !== ".") {
			const prefixParts = pattern.pathPrefix.split("/");
			if (
				pathParts.length < prefixParts.length ||
				!prefixParts.every((part, i) => part === pathParts[i])
			) {
				return false;
			}
		}

		// Get the relative path from the .gitignore location
		const relativePath =
			pattern.pathPrefix === "." ? filePath : filePath.slice(pattern.pathPrefix.length + 1);

		// If directory-only pattern, only match directories
		if (pattern.isDirectoryOnly && !isDirectory) {
			return false;
		}

		return this.matchPatternString(relativePath, pathParts, pattern.pattern);
	}

	private matchPatternString(filePath: string, pathParts: string[], pattern: string): boolean {
		// Convert gitignore pattern to regex
		let regexPattern = pattern;

		// Handle patterns with /
		if (pattern.includes("/")) {
			// Pattern with / is anchored
			if (pattern.startsWith("/")) {
				regexPattern = pattern.slice(1);
			}
		} else {
			// Pattern without / matches at any depth
			// Match against the last part or the whole path with wildcards
			const escapedPattern = this.escapeRegex(pattern).replace(/\*\*/g, ".*");
			const regex = new RegExp(
				`(^|/)${escapedPattern.replace(/\\\*/g, "[^/]*").replace(/\\\?/g, ".")}$`,
			);
			return regex.test(filePath);
		}

		// Handle ** (matches zero or more directories)
		regexPattern = regexPattern.replace(/\*\*/g, "<<<DOUBLESTAR>>>");

		// Handle * (matches anything except /)
		regexPattern = regexPattern.replace(/\*/g, "[^/]*");

		// Handle ? (matches single character except /)
		regexPattern = regexPattern.replace(/\?/g, "[^/]");

		// Restore ** as .*
		regexPattern = regexPattern.replace(/<<<DOUBLESTAR>>>/g, ".*");

		// Handle character classes [abc]
		regexPattern = regexPattern.replace(/\[([^\]]+)\]/g, "[$1]");

		// Escape other regex special characters
		regexPattern = this.escapeRegexExcept(regexPattern, "[^/].*$+()|");

		// Match pattern
		const regex = new RegExp(`^${regexPattern}(/.*)?$`);
		return regex.test(filePath);
	}

	private escapeRegex(str: string): string {
		return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
	}

	private escapeRegexExcept(str: string, except: string): string {
		const exceptSet = new Set(except);
		let result = "";
		for (const char of str) {
			if (".*+?^${}()|[]\\".includes(char) && !exceptSet.has(char)) {
				result += "\\" + char;
			} else {
				result += char;
			}
		}
		return result;
	}
}
