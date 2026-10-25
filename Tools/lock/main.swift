// check-lock <lock> <zip>: exits non-zero, with the reason, when the zip is not the one the lock names.
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: check-lock <lock> <zip>\n".utf8))
    exit(2)
}
do {
    let lock = try Lock(String(contentsOfFile: arguments[1], encoding: .utf8))
    if let reason = lock.mismatch(zip: try Data(contentsOf: URL(fileURLWithPath: arguments[2]))) {
        FileHandle.standardError.write(Data("\(reason)\n".utf8))
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("check-lock: \(error)\n".utf8))
    exit(1)
}
