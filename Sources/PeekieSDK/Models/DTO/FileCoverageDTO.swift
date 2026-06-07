import Foundation

// MARK: - FileCoverageDTO

struct FileCoverageDTO: Decodable {
    var coveredLines: Int
    var executableLines: Int
    var lineCoverage: Double
    var name: String
    var path: String
}

// MARK: - TargetCoverageDTO

struct TargetCoverageDTO: Decodable {
    var name: String
    var coveredLines: Int
    var executableLines: Int
    var lineCoverage: Double
    var files: [FileCoverageDTO]
}

// MARK: - CoverageReportDTO

struct CoverageReportDTO: Decodable {
    var lineCoverage: Double
    var targets: [TargetCoverageDTO]
}
