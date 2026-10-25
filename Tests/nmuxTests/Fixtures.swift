import Foundation

// The repository's root, found from this file, so the tests read its files from any working directory.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

func repositoryPath(_ relative: String) -> String { repository.appendingPathComponent(relative).path }
