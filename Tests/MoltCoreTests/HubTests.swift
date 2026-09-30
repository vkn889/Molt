import XCTest
@testable import MoltCore

final class HubTests: XCTestCase {
  func testForegroundIntervalsClipAtMidnight() {
    let start = Date(timeIntervalSince1970: 1000)
    let values = UsageMath.seconds([ActivityInterval(app: "app", name: "App", start: start.addingTimeInterval(-60), end: start.addingTimeInterval(120), category: "")], from: start, to: start.addingTimeInterval(60))
    XCTAssertEqual(values["App"], 60)
  }
  func testCodexCumulativeUsageIsNotDoubleCounted() {
    let lines = [
      #"{"timestamp":"2026-09-29T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10,"cached_input_tokens":20}}}}"#,
      #"{"timestamp":"2026-09-29T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10,"cached_input_tokens":20}}}}"#,
      #"{"timestamp":"2026-09-29T10:02:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"output_tokens":30,"cached_input_tokens":40}}}}"#
    ]
    let records = LocalUsageParser.records(lines: lines, tool: "Codex", source: "session")
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records.reduce(0) { $0 + $1.input }, 140)
    XCTAssertEqual(records.reduce(0) { $0 + $1.cached }, 40)
    XCTAssertEqual(records.reduce(0) { $0 + $1.output }, 30)
    XCTAssertNil(UsageMath.estimate(records, inputRate: 0, outputRate: 0, cacheRate: 0))
    XCTAssertEqual(UsageMath.estimate(records, inputRate: 1, outputRate: 2, cacheRate: 0.5)!, 0.00022, accuracy: 0.000001)
  }
  func testClaudeDedupAndMalformedRecords() {
    let line = #"{"timestamp":"2026-09-29T10:00:00.000Z","message":{"id":"a","usage":{"input_tokens":50,"output_tokens":10,"cache_read_input_tokens":20}}}"#
    let records = LocalUsageParser.records(lines: [line, line, "bad json", "{}"], tool: "Claude Code", source: "session")
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].input, 50)
    XCTAssertNil(records[0].reportedCost)
  }
}
