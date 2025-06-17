# Recompress BodyCam Quick Action

A macOS Shortcuts Quick Action that re‑encodes body camera footage using `ffmpeg`. Each selected clip becomes an AV1 file with Opus audio and is stored in a dated `yyyymmdd` folder. The date comes from the clip's `creation_time` metadata when present, or else from the file creation time. Tested on **macOS 15.5 (24F74)**.

## Features
 - [**creates output files**](tests/test_shortcuts.sh#L28-L40) — writes `<original>_av1.mp4` in a `yyyymmdd` folder
  next to the log file.
 - [**removes originals after second run**](tests/test_shortcuts.sh#L42-L48) — deletes the source clips once
  the new versions are verified.
 - [**writes log files**](tests/test_shortcuts.sh#L50-L58) — records a summary of each run in the output
  directory.
 - [**audio only for low motion**](tests/test_audio_only_for_low_motion.sh#L11-L26) — segments with minimal movement are split into audio-only files

## Requirements
- macOS 15.5 or newer
- [`ffmpeg`](https://ffmpeg.org/) compiled with `libsvtav1` and `libopus` support (`brew install ffmpeg`)
- Permission to run shell scripts from the Shortcuts app

## Installation
1. Clone this repository or copy `shortcuts.sh`.
2. In the **Shortcuts** app, create a new **Quick Action** with a **Run Shell Script** step.
3. Set the shell to `/bin/zsh` and configure it to pass input as *arguments*.
4. Paste the contents of `shortcuts.sh` into the script field.
5. (Optional) Prepend an output folder path before the *Shortcut Input* variable to bypass the folder picker.
6. Save the Quick Action so it appears in Finder when files are selected.

## Grant Full Disk Access
The script deletes the original files once the new versions are confirmed. For this to work, grant **Full Disk Access** to the following in **System Settings → Privacy & Security → Full Disk Access** (use **⌘⇧G** to jump to each path):

- `/System/Library/CoreServices/Finder.app`
- `/System/Library/PrivateFrameworks/WorkflowKit.framework/XPCServices/BackgroundShortcutRunner.xpc/Contents/MacOS/BackgroundShortcutRunner`
- `/System/Library/PrivateFrameworks/WorkflowKit.framework/XPCServices/ShortcutsMacHelper.xpc/Contents/MacOS/ShortcutsMacHelper`

## Usage
1. Select one or more bodycam video files in Finder.
2. Right‑click and choose **Recompress BodyCam**.
3. Pick an output folder when prompted, or supply it as the first argument in the Quick Action to skip the picker.
4. Each clip is transcoded to `<original>_av1.mp4` inside a `yyyymmdd` folder named after its recording date.
5. A log file is created in the output directory summarizing the run.

## Customization
The first argument to `shortcuts.sh` is the destination folder. When running from Shortcuts, leave this argument blank to display the folder picker, or supply a path (e.g. `/Users/me/BodycamAV1`) before the *Shortcut Input* variable to use a fixed location.

Set `KEEP_ORIGINALS=1` to preserve the source clips instead of deleting them once the AV1 versions are created. The originals are removed by default only after each new file is verified.

Adjust the encoding parameters in the script as needed for your workflow.

## Testing
An integration test script for macOS is provided as `macos-test.sh`. It runs
`shortcuts.sh` directly with a temporary clip and verifies that the re‑encoded
file is produced.

```bash
./macos-test.sh
```

For Linux or CI environments, `tests/test_shortcuts.sh` provides a similar test
using mocked macOS utilities. It generates its own video samples so no input
files are required.

```bash
./tests/test_shortcuts.sh
```

Run the scripts on a system with `ffmpeg` and `zsh` available.

## License
This project is available under the [MIT License](LICENSE).
