# Failure attachments extracted

Pulled attachments belonging to failing tests in `Tests/PeekieTests/Resources/SPM-26.5-iOS.xcresult` into `/tmp/peekie-eval-failed-attachments/`.

## What's in the bundle

10 failing tests total — only **2 of them carry attachments**:

| Failing test | Attachments |
|---|---|
| `ExamplesTests / ExampleSUITests / failureWithAttachment()` | 2 × `Failure context*.txt` |
| `ExamplesTests / XCTestTests / test_failureWithAttachment()` | 2 × `Failure context*.txt` |

The other 8 failing tests (`failure()`, `throwing()`, `deeplyNestedFailure()`, `innerFailure()`, `outerFailure()`, `test_failure()`, `test_throwing()`, `rootLevelFailure()`) produced no attachments — they're plain assertion failures, no screenshots or context blobs recorded by the test code.

No PNG screenshots were attached on any of the failing tests in this bundle. Apps like SwiftUI snapshot suites typically attach images on failure, but in this fixture only the two `failureWithAttachment*` tests deliberately attach text blobs (operands + expected/got values).

## Files landed

```
$ ls -la /tmp/peekie-eval-failed-attachments/
total 32
drwxr-xr-x    6 alldmeat  wheel   192 Jun 10 00:36 .
drwxrwxrwt  252 root      wheel  8064 Jun 10 00:37 ..
-rw-r--r--    1 alldmeat  wheel    38 Jun 10 00:36 ExamplesTests___ExampleSUITests___failureWithAttachment__Failure context_0_A1B2AFC2-46C9-4E04-9E0D-6CC9AC482E9C.txt
-rw-r--r--    1 alldmeat  wheel    38 Jun 10 00:36 ExamplesTests___ExampleSUITests___failureWithAttachment__Failure context_0_E5DE515E-D0D4-4101-A6AE-ABD5133F7ABF.txt
-rw-r--r--    1 alldmeat  wheel    26 Jun 10 00:36 ExamplesTests___XCTestTests___test_failureWithAttachment__Failure context_0_9C05FDEA-0C08-4973-805A-487EE7D8A57D.txt
-rw-r--r--    1 alldmeat  wheel    26 Jun 10 00:36 ExamplesTests___XCTestTests___test_failureWithAttachment__Failure context_0_F416AB05-E00B-4945-ABFB-54FF68B6E45A.txt
```

I renamed each file to `<qualifiedName>__<original-attachment-name>` so you can tell which test produced which blob without cross-referencing UUIDs. Each test ran twice (repetitions), hence two files per test.

## Content (all four are tiny text blobs)

- `failureWithAttachment` (Swift Testing): `Operands: 2 and 3, expected 5, got 6.0`
- `test_failureWithAttachment` (XCTest): `Operands: 2 and 3, got 6.0`

Same assertion in both flavors — `2 + 3` returning `6.0`, so the calculator under test is broken on addition.

## How it was done

The skill's recipe (`peekie attachments --test-id <id>` loop) leaks: `xcrun xcresulttool export attachments --test-id` actually dumps every attachment from the bundle into the dir, not just the matching test's, so the dir got 351 files with `(1)…(9)` dupes from repeated invocations. Instead I used:

```bash
peekie tests <xcresult> --format json --include failure \
  --attachments export --attachments-to /tmp/staging
```

That correlates attachments to tests in the JSON manifest, then I copied only the paths under failure-status tests into `/tmp/peekie-eval-failed-attachments/` and dropped the staging dir.
