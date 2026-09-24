# Glance — offline fork

Camera-assisted lock-screen unlock for macOS, forked from [jonnyoo/glance](https://github.com/jonnyoo/glance).
This repository adds mandatory active challenges, continuous identity checks, bounded credential sessions,
and guarded password delivery. It disables automatic updates and removes the update framework dependency.

> **Experimental convenience feature. This is not Apple Face ID or a security upgrade over Touch ID.**
> A normal RGB webcam does not provide a trusted depth sensor or a trusted video capture path.
> Photos, replayed/edited video, virtual cameras and generated video remain threats. Passing synthetic
> regression tests does not establish a real-world spoof rejection rate.
>
> Glance stores your actual Mac login password, encrypted behind a user-presence-gated Keychain key.
> Once authorized, the running process can decrypt that password until the session expires.
> Do not use a valuable account until the target Mac/camera has passed the [manual acceptance tests](docs/security-testing.md).

## Installation

Requirements: macOS 15+, Apple Silicon or Intel, a macOS-supported camera, and **full Xcode 26+** to build.
Command Line Tools alone cannot build the complete application. The source supports built-in, external,
and Continuity cameras, but individual cameras and OS versions still require testing.

**No notarized release of this hardened fork is currently provided.** Successful push builds in
[Actions](https://github.com/zhuyukuai/glance/actions) provide a seven-day `glance-test-universal`
artifact for hardware testing. It contains an ad-hoc signed app, its source commit and SHA-256 checksum.
This test signature has camera access but no provisioned keychain sharing group; use a disposable macOS
account. An upstream Glance DMG is not a build of this fork. To build locally, select the reviewed commit
or branch:

```bash
git clone https://github.com/zhuyukuai/glance.git
cd glance
open glance.xcodeproj
```

In Xcode, select the `glance` scheme and your own signing team. The project still has development signing
identifiers from upstream; use a consistent signing identity for subsequent local builds so Keychain and
macOS permissions remain associated with the same app. Do not grant additional entitlements to work
around a failed lock-screen test.

Build and run, then:

1. Start in a disposable macOS account. The first-run flow requires **Camera** and **Accessibility**
   permissions, face enrollment and a saved password before full Settings and Face Lab become available.
2. Follow enrollment, authorize a credential session using the system prompt, and save only the password
   for the **currently signed-in test account**. Do not put your primary account's password into a test build.
3. In Settings, select the intended physical camera. Use Face Lab to check detection, lighting, pose
   direction and recognition. Before first-run setup, QuickTime can check camera preview without credentials.
4. If enabling the optional space-key trigger, grant **Input Monitoring** separately.
5. Lock the test account, keep your face still until prompted, and perform each requested action.

Glance must already be running in the signed-in user's session. It does **not** unlock FileVault at boot
or replace the initial login after a restart. If the app/session is unavailable, use the normal password
or Touch ID. Do not disable FileVault or other macOS protections to make Glance work.

## Unlock policy

- Heavy passive spoof checks are mandatory in the actual unlock path, independently of mutable preferences.
- Three randomly ordered actions are selected from blink, open mouth, turn left and turn right.
  Every action starts with a fresh neutral hold, followed by a prompt, a response deadline and a return
  to neutral. Incorrect/early actions fail the scan; a generic motion sequence is not simply waited out.
- Only the same continuously recognized enrolled identity can advance the challenge. Missing faces,
  identity changes, large tracking jumps, stale frames or camera stalls terminate the attempt.
- At most **three scans per lock session**, including retries/cancelled scans. Actual manual unlock
  resets this budget; wake events do not. A scan takes up to 8–20 seconds (15 by default).
- Password events are sent only to the verified system `loginwindow` process for the active locked
  console session. The process/session, authorization and cancellation token are checked repeatedly.
  There is **no global keyboard/HID fallback**. Some macOS versions may reject this targeted route;
  use manual login if unlock cannot be confirmed. Password delivery failures are not automatically retried.
- Credential sessions default to **one hour idle**, configurable from 15 minutes to 8 hours. Every
  authorization expires after **8 hours total**, even with repeated face unlocks. Expiry is enforced
  on key access using a monotonic clock that includes sleep. Old day-based settings migrate to one hour.

The lock-screen prompt uses private SkyLight APIs. Their availability and the targeted keyboard route
must be checked on each supported macOS version. Build success does not prove lock-screen compatibility.

## Privacy and storage

Face recognition and liveness extraction use local Vision/Core ML processing. The application does not
save camera frames. Enrolled face embeddings are encrypted with AES-GCM; the Mac password is stored as
an encrypted Keychain item. Its AES key requires user presence when a credential session is authorized.
Deleting the password from Settings also removes face enrollment.

This fork has no automatic updater, update feed, telemetry or remote Swift package dependency. CI scans
runtime sources for known networking primitives. **This is source-level hardening, not an OS-enforced
network block:** App Sandbox is disabled for lock-screen integration. Audit the final signed app and its
runtime traffic if a strict offline deployment is required. Build tooling and model conversion can use
the network; neither runs during normal recognition.

## Tests

```bash
bash tools/run_security_tests.sh
```

The suite exercises passive cues, all 24 three-action permutations, the previously accepted fixed replay
(with and without a neutral prefix), wrong/early actions, deadlines, identity continuity, attempt budgets,
credential expiry and cancellation at every password-output boundary. Tests do not access a camera,
read credentials or post keyboard events. CI also builds the complete unsigned application with Xcode.
See [security testing and remaining limits](docs/security-testing.md) for required device testing.

Face Lab: Settings → About → click the app icon five times. Its experimental cue settings do not weaken
the real unlock policy, and its analyzer does not control the lock-screen prompt.

## Acknowledgements and license

- [Jonathan Zhou / original Glance](https://github.com/jonnyoo/glance)
- [The Boring Notch](https://github.com/TheBoredTeam/boring.notch)
- [InsightFace](https://github.com/deepinsight/insightface) — ArcFace model; see the model provider's usage terms.

[MIT](LICENSE) © Jonathan Zhou. Original license retained.
