import Foundation

public func snapshotName(from fileName: String) -> String {
    let withoutExtension = fileName.replacingOccurrences(of: ".xcresult", with: "")
    return withoutExtension.replacing(/-\d+(?:\.\d+){1,2}/, with: "")
}
