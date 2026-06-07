import Foundation
import Logging

extension TestResultsDTO {
    private static let logger = Logger(label: "com.peekie.dto")
    init(from xcresultPath: URL) async throws {
        let output = try await Shell.execute(
            "xcrun",
            arguments: [
                "xcresulttool", "get", "test-results", "tests",
                "--path", xcresultPath.path,
                "--compact",
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to convert output to Data"
                )
            )
        }

        Self.logger.debug(
            "Parsing TestResultsDTO",
            metadata: [
                "dataSize": "\(data.count)",
            ]
        )
        self = try JSONDecoder().decode(TestResultsDTO.self, from: data)
        Self.logger.debug(
            "TestResultsDTO parsed successfully",
            metadata: [
                "testNodesCount": "\(testNodes.count)",
            ]
        )
    }
}

extension CoverageReportDTO {
    private static let logger = Logger(label: "com.peekie.dto")

    init(from xcresultPath: URL) async throws {
        let output = try await Shell.execute(
            "xcrun",
            arguments: [
                "xccov", "view", "--report", "--json",
                xcresultPath.path,
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to convert output to Data"
                )
            )
        }

        Self.logger.debug("Parsing CoverageReportDTO")
        self = try JSONDecoder().decode(CoverageReportDTO.self, from: data)
        Self.logger.debug(
            "CoverageReportDTO parsed successfully",
            metadata: [
                "targetsCount": "\(targets.count)",
            ]
        )
    }
}

extension BuildResultsDTO {
    private static let logger = Logger(label: "com.peekie.dto")

    init(from xcresultPath: URL) async throws {
        let output = try await Shell.execute(
            "xcrun",
            arguments: [
                "xcresulttool", "get", "build-results",
                "--path", xcresultPath.path,
                "--format", "json",
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to convert output to Data"
                )
            )
        }

        Self.logger.debug("Parsing BuildResultsDTO")
        self = try JSONDecoder().decode(BuildResultsDTO.self, from: data)
        Self.logger.debug("BuildResultsDTO parsed successfully")
    }
}
