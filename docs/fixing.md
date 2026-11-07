# Fixing sync

## Without re-encoding

**Fix Sync** copies every stream into a new file of the same type with new timing. Nothing is decoded or encoded, so there is no loss of quality and it takes seconds.

The video is never moved, so it always starts at time zero. The audio is adjusted instead:

- **Audio is late.** The start of the audio is trimmed by the amount. Audio packets are about 20 to 30 ms long, so the result is within one packet of the target.
- **Audio is early.** The audio is held back by the amount, using the audio track's start time.

All audio tracks move together. Subtitles, chapters and the cover image are kept. Track names and languages are kept.

### MP4, M4V and MOV files

These get some extra care, because Plex and some other players are strict about them:

- The file's brand stays `mp42`.
- Timecode and other data tracks are left out. They are not needed for playback.
- The index is moved to the front of the file for fast starts.
- ffmpeg's extra bitrate box inside subtitle tracks is switched off. Newer ffmpeg adds it and Plex's transcoder can reject it.

### Verification

After writing, Syncwright checks the new file. It must have the same streams and codecs, a sensible length, and every packet must read cleanly. If any check fails, the new file is deleted and the problem is shown.

## With re-encoding, only when needed

If the check finds the sync drifting or jumping, or the lossless fix fails for a file, a **Fix by Re-encoding Audio** button appears.

This re-encodes the **audio only**:

- Same codec, bitrate, sample rate, channel count and language as the original.
- The audio is cut at each section and its speed adjusted very slightly, by well under one percent, so it follows the picture. This is not audible.
- Video, subtitles and chapters are copied untouched, and the container stays the same.

If the audio codec cannot be written by ffmpeg (DTS is one), the audio is written as AAC instead.

Re-encoded audio is a second generation copy, so there is a small loss of quality. Use it only when the lossless fix cannot do the job.

## Output names

The corrected file is saved next to the original as `name_synced.ext`. Your original is never changed or removed.

## Plex

Corrected MP4 files play in Plex. If a corrected file still will not play in Plex, check the Plex error and see [Troubleshooting](troubleshooting.md).
