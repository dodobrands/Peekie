import Foundation

struct FileCoverageDTO: Decodable {
    var coveredLines: Int
    var executableLines: Int
    var lineCoverage: Double
    var name: String
    var path: String
}

struct TargetCoverageDTO: Decodable {
    var name: String
    var coveredLines: Int
    var executableLines: Int
    var lineCoverage: Double
    var files: [FileCoverageDTO]
}

struct CoverageReportDTO: Decodable {
    var lineCoverage: Double
    var targets: [TargetCoverageDTO]
}
