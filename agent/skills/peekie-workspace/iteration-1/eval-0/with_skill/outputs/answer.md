Tests did not all pass — 13 issues in `ExamplesTests` (11 failures + 2 mixed/flaky).

## Failures

| Test | Message |
|---|---|
| `ExamplesTests / ExampleSUITests / failure()` | Expected 5.0 but got 6.0 |
| `ExamplesTests / ExampleSUITests / failureWithAttachment()` | Expected 5.0 but got 6.0 |
| `ExamplesTests / ExampleSUITests / flackyParameterized(value:) [false]` | SwiftTestingTests.swift:66: Expectation failed: (result → 4.0) == 5.0 |
| `ExamplesTests / ExampleSUITests / throwing()` | Calculator.swift:26: Caught error: .divisionByZero |
| `ExamplesTests / OuterSuite / outerFailure()` | Outer suite failure: result was 200.0 |
| `ExamplesTests / OuterSuite / InnerSuite / innerFailure()` | Inner suite failure: result was 12.0 |
| `ExamplesTests / OuterSuite / InnerSuite / DeeplyNestedSuite / deeplyNestedFailure()` | Deeply nested failure: result was 0.0 |
| `ExamplesTests / XCTestTests / test_failure()` | Expected 5.0 but got 6.0 |
| `ExamplesTests / XCTestTests / test_failureWithAttachment()` | Expected 5.0 but got 6.0 |
| `ExamplesTests / XCTestTests / test_throwing()` | Calculator.swift:26: failed: caught error: "divisionByZero" |
| `ExamplesTests / rootLevelFailure()` | Expected 5.0 but got 6.0 |

## Mixed (flaky — failed in at least one repetition)

| Test | Message |
|---|---|
| `ExamplesTests / ExampleSUITests / flacky()` | Flacky failure message: result was 2.0 |
| `ExamplesTests / XCTestTests / test_flacky()` | Flacky failure message: result was 2.0 |

Most failures look like the same `Expected 5.0 but got 6.0` pattern (likely an off-by-one in the calculator under test), plus a couple of `divisionByZero` throws.
