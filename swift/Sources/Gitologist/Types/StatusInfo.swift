import Foundation

public struct StatusInfo: Codable, Sendable {
	public let branch: String
	public let upToDate: String
	public let staged: [String]
	public let modified: [String]
	public let untracked: [String]
	public let deleted: [String]

	public init(branch: String, upToDate: String, staged: [String], modified: [String], untracked: [String], deleted: [String]) {
		self.branch = branch
		self.upToDate = upToDate
		self.staged = staged
		self.modified = modified
		self.untracked = untracked
		self.deleted = deleted
	}
}
