import Foundation

public struct Credentials: Sendable {
	public let username: String
	public let token: String

	public init(username: String, token: String) {
		self.username = username
		self.token = token
	}
}

public struct RemoteOptions: Sendable {
	public let credentials: Credentials?

	public init(credentials: Credentials? = nil) {
		self.credentials = credentials
	}
}
