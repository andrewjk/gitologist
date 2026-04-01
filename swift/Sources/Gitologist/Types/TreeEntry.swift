import Foundation

enum TreeEntryType: String, Codable {
	case blob
	case tree
}

struct TreeEntry: Codable {
	let path: String
	let sha: String
	let mode: String
	let type: TreeEntryType
}
