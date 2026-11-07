# Read Aloud — Phase 0 device spikes

Plan: [`Docs/Plans/narration-plan.md`](../../Plans/narration-plan.md) §14 Phase 0. Decision: [0023](../../Decisions/0023-narration.md).

## S1 voice behavior — 6 November 2026 (partial)

- Device: iPhone 17 Pro Max (iPhone18,2), iOS 27.2, Developer Mode on. Xcode 27.2 (27B52), Debug.
- Harness: `BibleReaderTests/NarrationVoiceSpikeTests.swift`, opt-in, never part of normal suites:

  ```sh
  TEST_RUNNER_BIBLE_SPIKE_S1=1 xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
    -destination 'platform=iOS,id=<device UDID>' -derivedDataPath .build/DeviceDD \
    -only-testing:BibleReaderTests/NarrationVoiceSpikeTests
  ```

- Method:
  - Text is rendered offline with `AVSpeechSynthesizer.write(_:toBufferCallback:)`, and its audio duration is compared with a plain baseline. A variant that comes out longer means the voice spoke something extra. A spelled `L. O. R. D.` is the reference for how much longer a spelled word comes out.
  - Real-time `speak(_:)` records each `willSpeakRange` callback and the thread it arrives on.
  - This method can tell whether something extra was spoken. It can't tell whether a word was said *well*, so that still needs listening.
- Voices installed: 32 English voices, all default quality. No enhanced or premium voices were downloaded. Personal Voice authorization status was `1` (denied). One voice per language and engine family was sampled:
  - Eloquence: Eddy, en-US and en-GB.
  - Legacy MacinTalk: Fred.
  - Siri compact: Aaron, Arthur, Catherine.
  - Super-compact: Samantha, Daniel, Karen, Moira, Rishi, Tessa.

### Results

| Check | Result |
| --- | --- |
| Leading `¶` | Eloquence voices add about 0.6 s and Fred adds 0.93 s, so they speak it. Siri and super-compact voices add nothing, so they stay silent. The approved omission stays necessary. |
| `LORD` | Same duration as `Lord` on every sampled voice. The spelled reference is 0.4–0.6 s longer. Spoken as a word, not spelled out. No lexicon entry needed for the voices tested. |
| `æ` (`Cæsar’s`) | Within ±0.09 s of `Caesar’s` on every voice, so it isn't spelled or voiced as a separate letter. Whether it sounds right still needs listening. |
| Psalm 119 Hebrew letter (`א ALEPH.`) | Fred adds 1.46 s, so it speaks the letter. Every other sampled voice adds nothing. The approved omission stays necessary. |
| Word-range granularity | Word-level on every voice. Siri and super-compact voices include trailing punctuation (`world,`). Fred reports punctuation as separate ranges. Eloquence reports no range for `¶` even though it speaks it. Moira merged `Son. The` into one range across a sentence boundary. |
| Delegate thread | Every callback arrived on the main thread (the main-thread count matched the total for every voice). The controller's hop to the main actor is still correct, because the thread isn't documented. |

### Still open in S1

- Enhanced, premium, and Personal Voice classes. None were installed or authorized on the test device.
- Listening checks: overall quality, how `æ` sounds, and how the announcements sound.
- Catalog observation, not yet acted on: the picker lists Eloquence voices (Grandma, Grandpa, Rocko, and others) and lists each Eloquence voice once per locale under the same name, for example two "Eddy" entries.

## S2–S5

Not started.
