import Foundation

public struct MergeOptions: Codable, Sendable {
	public let message: String?
	public let noFastForward: Bool?

	public init(message: String? = nil, noFastForward: Bool? = nil) {
		self.message = message
		self.noFastForward = noFastForward
	}
}
