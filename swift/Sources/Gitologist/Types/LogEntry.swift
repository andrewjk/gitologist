import Foundation

struct LogEntry: Codable {
	let sha: String
	let abbreviatedSha: String
	let tree: String
	let parent: String?
	let author: String
	let committer: String
	let date: Date
	let message: String
}
