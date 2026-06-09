# Failure attachments pulled into `/tmp/peekie-eval-failed-attachments/`

Ran:

```bash
peekie attachments Tests/PeekieTests/Resources/SPM-26.5-iOS.xcresult \
  --output-dir /tmp/peekie-eval-failed-attachments \
  --include failure
```

`--include failure` pushes down to `xcresulttool --only-failures`, so the JSON manifest only lists attachments from the failing tests.

## Failure attachments (per the peekie manifest)

Two tests failed, each with 2 repetitions, so 4 attachments total — all currently plain `text/plain` failure-context dumps (no screenshots in this particular xcresult):

| Test | Rep | File on disk | Content type |
|---|---:|---|---|
| `ExamplesTests / ExampleSUITests / failureWithAttachment()` | 1 | `/tmp/peekie-eval-failed-attachments/DA864376-BE3A-43BF-AEB5-1FFC0A2CFDD5.txt` | text/plain |
| `ExamplesTests / ExampleSUITests / failureWithAttachment()` | 2 | `/tmp/peekie-eval-failed-attachments/17307BA9-AF94-41C8-962E-FD49082907B4.txt` | text/plain |
| `ExamplesTests / XCTestTests / test_failureWithAttachment()` | 1 | `/tmp/peekie-eval-failed-attachments/8155519D-CFA8-4E1A-A51B-D8312BFAE97E.txt` | text/plain |
| `ExamplesTests / XCTestTests / test_failureWithAttachment()` | 2 | `/tmp/peekie-eval-failed-attachments/59C262F2-CBC7-4DD4-933B-8CC82471D73E.txt` | text/plain |

These are the attachments you want to look at — they're "Failure context" dumps from the two failing tests.

## Heads-up: more files landed on disk than the manifest

`xcresulttool` writes every attachment in the bundle to disk during export, even with `--only-failures`. Peekie's manifest correctly filters to just the 4 above, but the directory itself has 35 files plus a `manifest.json`. The extras (PNGs, other `.txt` blobs, files with no extension) belong to passing tests.

If you only want the failure attachments physically present, pull just the 4 paths above; everything else in the directory can be ignored or deleted.

## `ls -la /tmp/peekie-eval-failed-attachments/`

```
total 320
drwxr-xr-x   38 alldmeat  wheel   1216 Jun  8 14:46 .
drwxrwxrwt  328 root      wheel  10496 Jun  8 14:46 ..
-rw-r--r--    1 alldmeat  wheel     16 Jun  8 14:46 0177C8B7-0D19-4945-A379-378AAB0D7020.txt
-rw-r--r--    1 alldmeat  wheel     67 Jun  8 14:46 0198FFDB-760B-47EE-8314-53526F9C6637.png
-rw-r--r--    1 alldmeat  wheel     47 Jun  8 14:46 0214E567-7222-4E57-ACF8-A205A5B9D93D.txt
-rw-r--r--    1 alldmeat  wheel     67 Jun  8 14:46 0EF9E02C-6771-4412-96B3-5AE98C11B804
-rw-r--r--    1 alldmeat  wheel     38 Jun  8 14:46 17307BA9-AF94-41C8-962E-FD49082907B4.txt
-rw-r--r--    1 alldmeat  wheel     12 Jun  8 14:46 24FA91E2-BF08-42C4-8240-076EB49CB44C.txt
-rw-r--r--    1 alldmeat  wheel     26 Jun  8 14:46 2F539FF4-2672-4560-9CA4-E564F43D7A5C.txt
-rw-r--r--    1 alldmeat  wheel      8 Jun  8 14:46 2F67D0DC-1E5D-40D4-8FB6-93FAB68F494E.txt
-rw-r--r--    1 alldmeat  wheel     12 Jun  8 14:46 30406EFF-9959-448E-8D1C-9DAB0166C548.txt
-rw-r--r--    1 alldmeat  wheel     30 Jun  8 14:46 3575CB71-B437-41B7-9E30-02D71B2885D0.txt
-rw-r--r--    1 alldmeat  wheel     12 Jun  8 14:46 3C4F726A-32D6-49F7-B1FC-C45CCC2E8F91.txt
-rw-r--r--    1 alldmeat  wheel     28 Jun  8 14:46 43ED7DE5-13BD-4A93-B5DB-56C97239F61E.txt
-rw-r--r--    1 alldmeat  wheel     30 Jun  8 14:46 4620A836-7D37-48BA-869B-21EB3A57990E.txt
-rw-r--r--    1 alldmeat  wheel     16 Jun  8 14:46 4DC01492-6DBE-4AFF-BD8C-9A50650754F7.txt
-rw-r--r--    1 alldmeat  wheel     26 Jun  8 14:46 59C262F2-CBC7-4DD4-933B-8CC82471D73E.txt
-rw-r--r--    1 alldmeat  wheel     19 Jun  8 14:46 5E98D363-2659-416C-8790-A18EEA0FF07B.txt
-rw-r--r--    1 alldmeat  wheel      8 Jun  8 14:46 73251674-542F-4BDE-B290-963A257DEEBF.txt
-rw-r--r--    1 alldmeat  wheel     26 Jun  8 14:46 8155519D-CFA8-4E1A-A51B-D8312BFAE97E.txt
-rw-r--r--    1 alldmeat  wheel     67 Jun  8 14:46 9CFE39F5-BC62-41A7-AFA7-7A98C2B6C211
-rw-r--r--    1 alldmeat  wheel     67 Jun  8 14:46 9F44249D-E137-4397-A306-D2AAFAC33BA0
-rw-r--r--    1 alldmeat  wheel     47 Jun  8 14:46 AFCF1442-52C3-4B84-A7BB-9B08073C3053.txt
-rw-r--r--    1 alldmeat  wheel      8 Jun  8 14:46 B0753250-308D-4494-AA3B-9A93165EDEDB.txt
-rw-r--r--    1 alldmeat  wheel     67 Jun  8 14:46 B73F6C00-E379-435B-A191-FBFD22C4FE4F.png
-rw-r--r--    1 alldmeat  wheel     12 Jun  8 14:46 BC69AABF-B28B-4B32-9E37-DB1D896EB82A.txt
-rw-r--r--    1 alldmeat  wheel      8 Jun  8 14:46 C5CA3FEE-A08B-4D75-81ED-BAAA27D027FD.txt
-rw-r--r--    1 alldmeat  wheel     16 Jun  8 14:46 C6B88DF8-A2FC-4DA5-943F-648A42899DFB.txt
-rw-r--r--    1 alldmeat  wheel     67 Jun  8 14:46 D056E923-2C80-4136-9A6A-22FC2DBF137A.png
-rw-r--r--    1 alldmeat  wheel     47 Jun  8 14:46 D1BD3844-C1F8-4EC3-982F-AD7148BF2E69.txt
-rw-r--r--    1 alldmeat  wheel     30 Jun  8 14:46 D1E16B2C-02FB-4FB5-BAA8-7134B1B6CD3F.txt
-rw-r--r--    1 alldmeat  wheel     38 Jun  8 14:46 D45449E5-006A-4334-8117-88B97BF16CAB.txt
-rw-r--r--    1 alldmeat  wheel     38 Jun  8 14:46 DA864376-BE3A-43BF-AEB5-1FFC0A2CFDD5.txt
-rw-r--r--    1 alldmeat  wheel     67 Jun  8 14:46 DC58609C-19EC-4AB2-B139-A4CC75F2AD5C.png
-rw-r--r--    1 alldmeat  wheel     16 Jun  8 14:46 E15C493C-039B-4C3C-8FF3-526A745944AB.txt
-rw-r--r--    1 alldmeat  wheel     19 Jun  8 14:46 FAD62EE1-E34F-4C39-A816-C2806EF30B76.txt
-rw-r--r--    1 alldmeat  wheel     19 Jun  8 14:46 FFFD5C3E-161A-4525-B070-240F36BFBAC7.txt
-rw-r--r--    1 alldmeat  wheel  18360 Jun  8 14:46 manifest.json
```
