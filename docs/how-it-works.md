# How the check works

## What is measured

Syncwright reads the whole file once and builds two signals at 25 samples a second:

1. **Sound.** The loudness of the dialogue band of the first audio track.
2. **Picture.** How open the mouth is, found with Apple's face landmark detection on every frame. This is compared with speech loudness, because people open their mouths when they talk.

If there are too few faces to be meaningful, or the picture-and-sound method scores better, it falls back to comparing picture movement against sound onsets, which suits claps, cuts and action.

## Finding the offset

The two signals are slid against each other across a range of 3 seconds either way. The position where they line up best is the offset. The result is refined to better than one frame.

The file is also split into sections of 4 minutes, and the offset is worked out for each one. That shows whether the sync is steady, drifts steadily, or jumps (for example after an ad break).

The container's own timing is read as well. If the audio track is flagged to start later or earlier than the video, that is added in, so the number you see is the real gap between what you hear and what you see.

## Confidence

Confidence is based on how clearly the best offset stands out from the rest, and on how many sections agree.

| Level | Meaning |
|---|---|
| High | A clear match, and most sections agree. Safe to apply. |
| Medium | A clear match, but with fewer agreeing sections. Usually fine. |
| Low | A weak match. Check by ear before applying. |
| None | No reliable relationship found. The app says "Could not determine". |

**Fix All Needed** only touches files with Medium or High confidence.

## Patterns

- **Steady.** Every section agrees. A single shift fixes the file.
- **Drifting.** The offset grows or shrinks through the file, as happens when the audio and video run at slightly different speeds. A single shift cannot fix this.
- **Jumping.** The offset changes between sections because of edits or ad breaks. A single shift fixes only part of the file.

For the last two the app offers the audio re-encode. See [Fixing sync](fixing.md).

## Accuracy

The measurement is accurate to about 40 ms, one frame at 25 frames a second. People rarely notice errors under about 45 ms when the sound is early and 125 ms when it is late, so the app treats anything under 40 ms as in sync.
