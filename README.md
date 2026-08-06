# Gitologist

A Git client in (TypeScript | Swift | C# | Zig).

> This is a basic Git client, built to provide rudimentary sync features on top of Git storage.
>
> It is missing many Git features, and will likely never have them.
>
> Its interface may drift from the Git ways of doing things if it makes its use case simpler.

## Features

- [x] clone
- [x] init
- [x] add
- [x] restore
- [ ] diff
- [x] log
- [x] status
- [x] commit
- [x] merge
- [x] fetch
- [x] pull
- [x] push
- [x] stash
- [x] unstash

## Not Implemented

- mv
- rm
- bisect
- grep
- show
- backfill
- branch
- rebase
- reset
- switch
- tag

## Getting Started

### Web/Node

Use your package manager to install Gitologist:

```bash
npm install gitologist
```

And then call e.g. `clone`, `add`, `commit` and `push`:

```javascript
import { clone, add, commit, push, status } from "gitologist";

const url = "https://github.com/andrewjk/gitologist.git";
const repoPath = join(".", "gitologist");
await clone(url, repoPath);

// Now we have a cloned folder and the user can edit files, which we can add, commit and push
await add(repoPath, ["test.txt"]);
await commit(repoPath, "Added a text file");
await push(repoPoth);

// Calling status should show no changes now
const repoStatus = await status(testDir);
console.log(repoStatus);
```

### Swift

The Swift version of Gitologist can be installed from https://github.com/andrewjk/gitologist-swift.

From Xcode, select `File` > `Add package dependencies` and follow the instructions.

Or add the following to your Package.swift file:

```swift
dependencies: [
    .package(url: "https://github.com/andrewjk/gitologist-swift", from: "1.0.5")
]
```

And then call e.g. `clone`, `add`, `commit` and `push`:

```swift
import Gitologist

let url = "https://github.com/andrewjk/gitologist.git"
let repoPath = FileManager.default.temporaryDirectory.appendingPathComponent("gitologist")
_ = try await clone(url: url, targetPath: repoPath.path)

// Now we have a cloned folder and the user can edit files, which we can add, commit and push
try await add(at: repoPath.path, files: ["test.txt"])
_ = try await commit(at: repoPath.path, message: "Added a text file")
try await push(at: repoPath.path)

// Calling status should show no changes now
let repoStatus = try await status(at: repoPath.path)
print("\(repoStatus)")
```

### C#

Install Gitologist from NuGet: https://www.nuget.org/packages/Gitologist/

And then call e.g. `Clone.CloneRepo`, `Add.AddFiles`, `Commit.CreateCommit` and `Push.PushToRemote`:

```c#
using Gitologist;

var url = "https://github.com/andrewjk/gitologist.git";
var repoPath = Path.Combine(Path.GetTempPath(), "gitologist");
await Clone.CloneRepo(url, targetPath);

// Now we have a cloned folder and the user can edit files, which we can add, commit and push
await Add.AddFiles(repoPath, ["test.txt"]);
await Commit.CreateCommit(repoPath, "Added a text file");
await Push.PushToRemote(repoPath);

// Calling status should show no changes now
var repoStatus = await Status.GetStatus(repoPath);
Console.WriteLine(repoStatus.ToString())
```

### Zig

The Zig version of Gitologist can be installed from https://github.com/andrewjk/gitologist-zig.

TODO: Zig package and instructions

And then call e.g. `clone`, `add`, `commit` and `push`:

```zig
const clone = @import("gitologist").clone;
const extended = @import("gitologist").extended;
const htmlRenderers = @import("gitologist").htmlRenderers;

const io = std.testing.io;
const allocator = std.testing.allocator;

const url = "https://github.com/andrewjk/gitologist.git"
const repo_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist" });
defer allocator.free(repo_path);

const result_path = try clone(io, allocator, url, target_path, null);
defer allocator.free(result_path);

try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

const commit_sha = try commit(io, allocator, repo_path, "Added a text file");
defer allocator.free(commit_sha);

try push(io, allocator, repo_path, null, null, null);

const repo_result = try status(io, allocator, repo_path);
defer repo_result.deinit(allocator);

std.debug.print("{s}\n", repo_result);
```
