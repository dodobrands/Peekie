# Failure attachments from `SPM-26.5-iOS.xcresult`

## What landed in `/tmp/peekie-eval-failed-attachments-baseline/`

```
$ ls -la /tmp/peekie-eval-failed-attachments-baseline/
total 56
drwxr-xr-x    9 alldmeat  wheel    288 Jun  9 21:00 .
drwxrwxrwt  314 root      wheel  10048 Jun  9 21:00 ..
-rw-r--r--    1 alldmeat  wheel     38 Jun  9 21:00 17307BA9-AF94-41C8-962E-FD49082907B4.txt
-rw-r--r--    1 alldmeat  wheel     26 Jun  9 21:00 2F539FF4-2672-4560-9CA4-E564F43D7A5C.txt
-rw-r--r--    1 alldmeat  wheel     26 Jun  9 21:00 59C262F2-CBC7-4DD4-933B-8CC82471D73E.txt
-rw-r--r--    1 alldmeat  wheel     26 Jun  9 21:00 8155519D-CFA8-4E1A-A51B-D8312BFAE97E.txt
-rw-r--r--    1 alldmeat  wheel     38 Jun  9 21:00 D45449E5-006A-4334-8117-88B97BF16CAB.txt
-rw-r--r--    1 alldmeat  wheel     38 Jun  9 21:00 DA864376-BE3A-43BF-AEB5-1FFC0A2CFDD5.txt
-rw-r--r--    1 alldmeat  wheel   3223 Jun  9 21:00 manifest.json
```

6 attachment files + 1 merged `manifest.json` mapping each file to its failing test and repetition.

## Mapping (from manifest.json)

| File | Failed test | Repetition | Suggested name |
|---|---|---|---|
| `8155519D-CFA8-4E1A-A51B-D8312BFAE97E.txt` | `XCTestTests/test_failureWithAttachment()` | 1 (First Run) | Failure context |
| `59C262F2-CBC7-4DD4-933B-8CC82471D73E.txt` | `XCTestTests/test_failureWithAttachment()` | 2 (Retry 1) | Failure context |
| `2F539FF4-2672-4560-9CA4-E564F43D7A5C.txt` | `XCTestTests/test_failureWithAttachment()` | 3 (Retry 2) | Failure context |
| `DA864376-BE3A-43BF-AEB5-1FFC0A2CFDD5.txt` | `ExampleSUITests/failureWithAttachment()` | 1 (First Run) | Failure context |
| `17307BA9-AF94-41C8-962E-FD49082907B4.txt` | `ExampleSUITests/failureWithAttachment()` | 2 (Retry 1) | Failure context |
| `D45449E5-006A-4334-8117-88B97BF16CAB.txt` | `ExampleSUITests/failureWithAttachment()` | 3 (Retry 2) | Failure context |

## Contents

These are NOT screenshots — they're small text "Failure context" attachments that the calculator example tests dump when they fail:

- XCTest variants contain e.g. `Operands: 2 and 3, got 6.0`
- Swift Testing variants contain e.g. `Operands: 2 and 3, expected 5, got 6.0`

No PNG/JPEG attachments exist on any of the failed tests in this bundle.

## How it was done

1. `xcrun xcresulttool get test-results tests` to enumerate all `Test Case` nodes with `result == "Failed"`. 11 failed tests total:
   - `rootLevelFailure()`
   - `XCTestTests/test_failure()`, `test_failureWithAttachment()`, `test_throwing()`
   - `OuterSuite/outerFailure()`, `OuterSuite/InnerSuite/innerFailure()`, `OuterSuite/InnerSuite/DeeplyNestedSuite/deeplyNestedFailure()`
   - `ExampleSUITests/failure()`, `failureWithAttachment()`, `throwing()`, `flackyParameterized(value:)`
2. For each failed test ID, `xcrun xcresulttool export attachments --test-id <id> --path … --output-path <tmp>`, then merge files and manifests into the output dir.
3. Only the two `…WithAttachment()` tests actually produced any attachments — the other 9 failures had none.

### Note on `--only-failures`

`xcresulttool export attachments --only-failures` (the obvious one-liner) produced an empty manifest on this bundle: it filters to attachments XCTest itself tagged with `isAssociatedWithFailure == true` (e.g. attachments dropped via `XCTAttachment.lifetime = .keepAlways` on a failed test). The attachments in this bundle have `isAssociatedWithFailure: false` in the manifest, so Apple's built-in filter skipped them. The per-failed-test-id loop above is what actually pulls "attachments belonging to failing tests".
