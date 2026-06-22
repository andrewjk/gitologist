import Foundation

private let HEAD_FILE = "ref: refs/heads/main\n"
private let CONFIG_FILE = """
[core]
	repositoryformatversion = 0
	filemode = true
	bare = false
	logallrefupdates = true
"""

public func initRepo(at path: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	if FileManager.default.fileExists(atPath: gitDir.path) {
		return
	}

	try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("objects"), withIntermediateDirectories: true)
	try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("refs").appendingPathComponent("heads"), withIntermediateDirectories: true)
	try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("refs").appendingPathComponent("tags"), withIntermediateDirectories: true)
	try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("info"), withIntermediateDirectories: true)

	try HEAD_FILE.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
	try CONFIG_FILE.write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
	try "Unnamed repository; edit this file 'description' to name the repository.\n".write(to: gitDir.appendingPathComponent("description"), atomically: true, encoding: .utf8)
}
