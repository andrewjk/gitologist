import Foundation

public struct LogEntry: Codable, Sendable {
	public let sha: String
	public let abbreviatedSha: String
	public let tree: String
	public let parent: String?
	public let author: String
	public let authorEmail: String
	public let committer: String
	public let date: Date
	public let message: String

	public init(sha: String, abbreviatedSha: String, tree: String, parent: String?, author: String, authorEmail: String, committer: String, date: Date, message: String) {
		self.sha = sha
		self.abbreviatedSha = abbreviatedSha
		self.tree = tree
		self.parent = parent
		self.author = author
		self.authorEmail = authorEmail
		self.committer = committer
		self.date = date
		self.message = message
	}
}
