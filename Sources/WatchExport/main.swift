import Foundation
import WatchCore

// Reuse the native app's consistent Firefox snapshot and URL handling.
do {
    let stories = try FirefoxBookmarks.load()
    FileHandle.standardOutput.write(try JSONEncoder().encode(stories))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
