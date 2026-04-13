import Foundation

struct IndexEntry: Codable {
	let path: String
	let sha: String
	let mode: String
	let size: UInt32
	let ctimeSeconds: UInt32
	let ctimeNanos: UInt32
	let mtimeSeconds: UInt32
	let mtimeNanos: UInt32
	let dev: UInt32
	let ino: UInt32
	let uid: UInt32
	let gid: UInt32
}
