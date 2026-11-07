# Changelog

## 1.0.0 (November 2026)

- First release.
- Checks sync across a whole video file using lip movement against speech, with a picture motion fallback.
- Lossless fix that never moves the video and keeps the container, codecs, subtitles and chapters.
- Audio only re-encode for files whose sync drifts or jumps.
- Batch checking and fixing of episodes and folders.
- Verifies every corrected file, and removes it if it is damaged.
- MP4 output tuned for Plex.
