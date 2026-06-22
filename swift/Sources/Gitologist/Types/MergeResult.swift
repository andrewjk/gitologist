import Foundation

public struct MergeResult: Codable, Sendable {
	public let success: Bool
	public let fastForward: Bool
	public let commitSha: String?
	public let message: String?

	public init(success: Bool, fastForward: Bool, commitSha: String?, message: String?) {
		self.success = success
		self.fastForward = fastForward
		self.commitSha = commitSha
		self.message = message
	}
}
