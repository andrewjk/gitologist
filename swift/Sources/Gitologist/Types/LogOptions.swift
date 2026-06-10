import Foundation

struct LogOptions: Codable {
	let limit: Int?
	let oneline: Bool?
	let branch: String?
	let file: String?

	init(limit: Int? = nil, oneline: Bool? = nil, branch: String? = nil, file: String? = nil) {
		self.limit = limit
		self.oneline = oneline
		self.branch = branch
		self.file = file
	}
}
