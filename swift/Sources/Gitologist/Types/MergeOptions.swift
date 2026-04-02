import Foundation

struct MergeOptions: Codable {
	let message: String?
	let noFastForward: Bool?

	init(message: String? = nil, noFastForward: Bool? = nil) {
		self.message = message
		self.noFastForward = noFastForward
	}
}
