import Foundation

public struct LogOptions: Codable, Sendable {
	public let limit: Int?
	public let oneline: Bool?
	public let branch: String?
	public let file: String?

	public init(limit: Int? = nil, oneline: Bool? = nil, branch: String? = nil, file: String? = nil) {
		self.limit = limit
		self.oneline = oneline
		self.branch = branch
		self.file = file
	}
}
