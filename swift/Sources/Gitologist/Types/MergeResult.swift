import Foundation

struct MergeResult: Codable {
	let success: Bool
	let fastForward: Bool
	let commitSha: String?
	let message: String?
}
