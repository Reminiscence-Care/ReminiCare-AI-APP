# Stability implementation acceptance — 2026-10-08

## Implemented

- Recorder and player commands are serialized through injected ports. Recording
  states include preparing, recording, stopping, completed and failed. Startup
  cancellation cannot revive the UI; concurrent stop requests finalize once.
- Amplitude detection runs during bounded calibration. Three successive failures
  show manual-stop guidance; the monotonic maximum-duration watchdog continues.
- Player completion, cancellation and failure settle waiting work and remove
  subscriptions. Recording starts after playback stops. Native iOS recorder
  session management is disabled so the coordinator owns the shared session.
- Lifecycle and audio/input-route interruptions retain usable recordings and
  require explicit recognition/rerecording. Disposal releases audio focus.
- STT jobs have isolated progress and cancellation. NCKU retains successful
  segments for retry and stops sending further segments on cancellation. Yating
  requires EOF; partial results are errors with retained audio, not success.
- AI HTTP requests use abortable requests, bounded timeouts and stale-result
  checks. Aborting a connection cannot guarantee upstream model computation or
  billing stops once the provider has accepted the request.
- Conversation turns distinguish memories from corrections. Scene generation
  uses cumulative memory, era and location; image retries do not resend STT.
- Memory records have stable IDs/schema versions, atomic file publication and
  relative image paths. Migration backs up all legacy strings, including corrupt
  rows. Deletion/draft cleanup respects other record references and directory
  ownership. Settings publish a snapshot only after storage succeeds, with
  compensating rollback on failures.
- Obsolete topic search and cloud vision ranking code/settings were removed;
  bundled topic images remain. TTS cache keys include provider/voice identity.

## Automated and local checks

- Flutter analyze: no issues.
- Flutter tests: 80 passed (old unused search/vision tests removed; new lifecycle,
  cancellation, partial EOF, controller, migration and rollback tests added).
- Windows debug build and Android debug APK: passed.
- Real NCKU short Chinese recording: approximately 3.12 seconds, 99,982-byte WAV,
  177,715-byte encoded request. Successful response in approximately 490 ms;
  expected surname matched the local annotation. Token and returned transcript
  were not logged. The original sample was not modified or committed.
- Worker was not changed; its existing checks are run in CI. No Worker deployment
  is part of this update.
- Initial macOS CI exposed a pre-existing Runner configuration that referenced
  CocoaPods settings directly and omitted Flutter's generated build variables.
  Debug/Release/Profile now use Flutter's wrapper xcconfig files; the unsigned
  iOS build passed on revision 843406a in GitHub macOS CI (run 37674070644).

## Required external/device acceptance

This Windows host has no connected iPad or Android device. Test fixtures and one
short STT request do not prove microphone stability or transcription quality.

- On iPad: run Chinese and Taiwanese speech with immediate start, quiet speech,
  background noise, 3/6-second pauses, long recording, manual stop, permission
  denial, input-route switching and background/foreground transitions. Check no
  premature stop, silent hang, lost recording or playback/recording conflict.
- Collect medium/long Chinese and Taiwanese samples and record segment-boundary
  accuracy plus total latency; keep the existing 5-second/240-KiB budget until
  real results justify a change. No synthetic requests probe server limits.
- macOS/Xcode unsigned iOS debug build: passed in CI, not locally executed.
  Signing/installing on an actual iPad remains outstanding.
- NCKU is an externally managed laboratory service; the user cannot change its
  servers. Current default HTTP STT and raw TCP TTS remain unencrypted. This is
  an acknowledged external limitation, not a user task or a prerequisite for
  long-recording acceptance. TLS configuration alone does not secure a server;
  future deployment security requirements need a separate decision.
- Confirm migration on a copy of real existing history, save failures/retry and
  shared-image deletion. The legacy JSON backup must be retained for recovery.

The WebSocket ready/connect deadlines are 5/10 seconds. EOF completion deadline
is 30 seconds after audio sending. NCKU per-request deadline remains 60 seconds.
Playback startup/stop deadlines are 10/5 seconds with a 2-minute playback bound.
