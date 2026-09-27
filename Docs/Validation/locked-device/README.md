# Locked-device protection test

The user store (`Application Support/ReaderData/User.sqlite` and its journal) uses **Complete** file protection. iOS discards the class key about 10 seconds after the device locks. After that, the database cannot be read or written until the user unlocks the device. The app must:

1. save the reading position while backgrounding, before the key is discarded;
2. fail cleanly if a write is attempted while locked, without corrupting or resetting the store;
3. read and write normally again after unlock, with the integrity check still `ok`.

A simulator cannot demonstrate this, because it does not enforce data protection. The Debug build therefore includes a **lock probe** (`BibleReader/App/LockProbe.swift`), compiled only in Debug. Each probe step runs one read, one position write, and `PRAGMA quick_check`. The report contains timings and outcomes only, never passages or paths.

## Run it (physical iPhone, about 2 minutes)

1. Connect the iPhone and select it as the run destination. Signing uses the owner's team, which is already set on all targets.
2. In Xcode, choose **Product → Scheme → Edit Scheme… → Run → Arguments** and add `--lock-probe` under *Arguments Passed On Launch*. Set **Run → Info → Build Configuration** to **Debug**, because the probe is not compiled into Release. The owner's scheme currently runs Release; switch back afterward.
3. Run the app. Open any chapter and scroll a little.
4. Press the side button to lock the phone. **Wait at least 30 seconds.**
5. Unlock the phone and return to the app. A **Lock probe** alert shows the report.
6. Relaunch the app (stop it in Xcode, then run again) and confirm the reader reopens at the same chapter and position, and that highlights are intact.

## Expected report

```
+0.0s check: read ok, write ok, integrity ok [protected data available]
+2.0s check: read ok, write ok, integrity ok [protected data available]
+~10s protected data will become unavailable
+20.0s check: read failed SQLite error NN, write failed SQLite error NN, integrity check failed [protected data unavailable]
+NN s protected data available
+NN s after unlock: read ok, write ok, integrity ok [protected data available]
```

A SQLite error at +20 s is the expected protection behavior. It is typically `SQLITE_IOERR` (10) or `SQLITE_AUTH` (23); the exact code depends on the OS and is worth recording. The +20 s line appears only if iOS grants that much background time, and a "background time expired" line may appear instead. Either way is acceptable.

The test **fails** if any of these happen:

- the +0 or +2 s write fails;
- "after unlock" shows a failure, or integrity is anything other than `ok`;
- relaunch loses the position or highlights;
- the app shows "Local reading data could not open" after unlock.

Record the device, iOS version, and report in this file when the test is run.

## Results

**27 September 2026 — passed.** iPhone 17 Pro Max (iPhone18,2), Debug build with `--lock-probe`; the iOS version was not recorded. Report as shown on the device:

```
+0.1s check: read ok, write ok, integrity ok [protected data available]
+2.1s check: read ok, write ok, integrity ok [protected data available]
+21.3s check: read failed SQLite error 10, write failed SQLite error 10, integrity check failed [protected data unavailable]
+70.9s protected data available
+73.1s after unlock: read ok, write ok, integrity ok [protected data available]
```

The console showed `os_unix.c … seekAndRead(…/ReaderData/User.sqlite) - Operation not permitted` for the locked attempt, which is SQLITE_IOERR under Complete protection, as expected. The position saved before the key was discarded, the locked attempt failed without damage, and the store recovered after unlock with `quick_check` ok. The iOS version and the relaunch check (step 6) were not reported with this result.

## What the app does outside the probe

- Backgrounding flushes the reading position under a finite background task (`BackgroundWriteLease`).
- A failed write keeps the previous state and shows "Your reading position could not be saved"; nothing is deleted.
- If the store cannot open, for example on a launch while locked, the reader shows "Local reading data could not open… Unlock the device and try again." Retry reopens the store; it is never replaced.
