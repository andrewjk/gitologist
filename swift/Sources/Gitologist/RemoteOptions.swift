import Foundation

struct Credentials {
	let username: String
	let token: String
}

struct RemoteOptions {
	let credentials: Credentials?
}
