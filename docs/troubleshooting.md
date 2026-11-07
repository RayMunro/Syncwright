# Troubleshooting

## "ffmpeg was not found"

Install it with Homebrew: `brew install ffmpeg`. The app looks in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` and `/opt/local/bin`.

## "Could not determine sync"

The file had too little to go on. This is common when there are few visible faces, when music or effects cover the dialogue, or for narration over footage. If you know the offset, you can still enter it by hand, but confidence will not be shown.

## The result seems wrong

- Check the confidence and the chart. A Low confidence or scattered dots mean you should check by ear.
- Use **Check Result** on a corrected copy. A good fix should show "In sync".
- If the file has several audio tracks, only the first is used for the check. All tracks are corrected by the same amount.

## The check is slow

Every frame is searched for faces, so a long file takes several minutes. Close other heavy apps, and note that files are checked one at a time.

## A corrected file will not play in Plex

- Confirm the original plays in Plex. If it does not, the problem is not the fix.
- Compare the two files with `ffprobe` for differences such as extra streams.
- Try the corrected file in another player. If it plays there but not in Plex, send the Plex error text when you report the problem.

## The lossless fix failed verification

The app deletes a damaged output and says why. Try **Fix by Re-encoding Audio**, which rebuilds the audio stream.

## macOS will not open the app

Right-click Syncwright and choose **Open**, then confirm. This is needed once for apps that are not notarised.
