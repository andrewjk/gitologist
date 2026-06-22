// Gitologist public API
//
// All functions are available as top-level functions after importing Gitologist:
//
//     import Gitologist
//
//     try await initRepo(at: path)
//     try await add(at: path, files: ["file.txt"])
//     try await commit(at: path, message: "Initial commit")
//     let info = try await status(at: path)
//     try await restore(at: path, files: ["file.txt"])
//     try await switchBranch(at: path, to: "feature")
//     let branch = try await getCurrentBranch(at: gitDir)
//     let commit = try await getCurrentCommit(at: gitDir)
//     try await fetchOrigin(at: path, remote: "origin")
//     let url = await getRemoteUrl(at: gitDir, remoteName: "origin")
