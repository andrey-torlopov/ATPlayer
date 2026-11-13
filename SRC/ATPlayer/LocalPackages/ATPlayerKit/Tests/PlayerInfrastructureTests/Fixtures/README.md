# Audio validation fixtures

Audio is generated locally and excluded from Git. No recorded music or third-party media is distributed with the source.

Install FFmpeg, then run this command from the repository root **before building the test bundle**:

```sh
python3 SRC/ATPlayer/LocalPackages/ATPlayerKit/Tools/generate_audio_fixtures.py
```

The script generates a 440 Hz sine wave at 44100 Hz, mono, with 0.1 seconds of source audio. Compressed containers can include codec padding. It uses a temporary directory and copies files here only after every codec succeeds.

| File | Codec |
|---|---|
| tone.mp3 | libmp3lame |
| tone.flac | flac |
| tone.wav | pcm_s16le |
| tone.aiff | pcm_s16be |
| tone.caf | pcm_s16le |
| tone.aac | aac |
| tone.m4a | aac |
| tone-alac.m4a | alac |

SwiftPM copies this directory into the test bundle. The tests run without FFmpeg once the bundle is built. Missing generated fixtures fail with a preparation instruction; invalid variants are created in a temporary directory by the tests.

`ReportedMP3Tests` are optional local regression tests. Their user-supplied recording is never committed; without that file those tests explicitly skip.
