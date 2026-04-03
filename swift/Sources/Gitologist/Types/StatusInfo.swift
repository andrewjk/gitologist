import Foundation

struct StatusInfo: Codable {
	let branch: String
	let upToDate: String
	let staged: [String]
	let modified: [String]
	let untracked: [String]
	let deleted: [String]
}
