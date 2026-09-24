# Notification audio resources

The catalog references original StarBridge product sounds supplied by the maintainer in `StarBridge_正式与预备音频_v1`. These WAV resources are **not Apache-2.0 source assets** and are not Star Citizen media. Keep binaries out of public source distributions; see `open-core/ASSET_POLICY.md` and `open-core/DATA_RIGHTS.md`.

For private acceptance, run `scripts/Stage-NotificationAudio.ps1 -PackageRoot <authorized package directory>`. It verifies all five SHA-256 digests before copying into ignored `.private-ops/notification-audio`. NativeHost includes those files under `Assets/Audio` when built. Missing resources must show unavailable, never pretend to play.

- Approved: `notify.soft` v1 and `notify.emergency_broadcast` X5.
- Candidate: `notify.action` A and `notify.operation` A, not promoted to approved.
- Fallback: emergency X4, selected only when higher-tier assets are absent. A present corrupt higher-tier file rejects playback instead of silently falling back.

The preview slice exposes ordinary-notification preview with device-local mute and volume. The subsequent room slice observes authenticated directory results for new invitations/applications and uses the same verified cue. Automatic audio is quiet for baseline/recovery reads, foreground use, games and paused reminders. Private-message/background notification delivery is not complete. Neither slice plays startup/click sounds, changes system volume, migrates WPF settings or grants release/distribution rights.
