Not all green — 10 test failures in `SPM-26.5-iOS.xcresult`.

| # | Test | Failure |
|---|------|---------|
| 1 | `ExamplesTests / ExampleSUITests / failure()` | Expected 5.0 but got 6.0 |
| 2 | `ExamplesTests / ExampleSUITests / failureWithAttachment()` | Expected 5.0 but got 6.0 |
| 3 | `ExamplesTests / ExampleSUITests / throwing()` | Calculator.swift:26: Caught error: .divisionByZero |
| 4 | `ExamplesTests / OuterSuite / InnerSuite / DeeplyNestedSuite / deeplyNestedFailure()` | Deeply nested failure: result was 0.0 |
| 5 | `ExamplesTests / OuterSuite / InnerSuite / innerFailure()` | Inner suite failure: result was 12.0 |
| 6 | `ExamplesTests / OuterSuite / outerFailure()` | Outer suite failure: result was 200.0 |
| 7 | `ExamplesTests / XCTestTests / test_failure()` | Expected 5.0 but got 6.0 |
| 8 | `ExamplesTests / XCTestTests / test_failureWithAttachment()` | Expected 5.0 but got 6.0 |
| 9 | `ExamplesTests / XCTestTests / test_throwing()` | Calculator.swift:26: failed: caught error: "divisionByZero" |
| 10 | `ExamplesTests / rootLevelFailure()` | Expected 5.0 but got 6.0 |

Most look like the same off-by-one expectation (`Expected 5.0 but got 6.0`) plus a `divisionByZero` branch in `Calculator.swift:26` — looks like one underlying calc bug propagating through several suites.
