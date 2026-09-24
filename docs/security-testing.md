# Security regression and device acceptance

## Automated regression tests

Run `bash tools/run_security_tests.sh`. The tests compile production decision/state code with synthetic
measurements and fake event sinks. They do not use real credentials or produce keyboard events.

The 2026-09-24 review found that a fixed 2.3-second blink/mouth/turn sequence passed every old two-step
challenge and 120/120 randomly initialized Heavy analyzers when no passive deny signal was supplied.
The regression suite now feeds that recording repeatedly, with and without a neutral prefix, through
the production analyzer for every three-action permutation. It must never confirm. The same tests also
exercise valid prompted actions to ensure rejection was not implemented by simply disabling recognition.

Other required properties:

- An unexpected action, opposite head turn, pre-prompt motion, missing/nonfinite measurements, timestamp
  reversal, stalled frames or expired response cannot complete a challenge. Challenge failure is terminal.
- Unmatched identities cannot advance the challenge. Loss/change of the bound identity or discontinuous
  tracking ends the scan; neither live evidence nor a passive denial can be cleared by briefly hiding a face.
- Superseded/cancelled scans cannot emit credentials. Context loss at any event boundary suppresses the
  remaining password and Return. Output remains pinned to the system loginwindow PID, never global focus.
- Idle expiry and absolute authorization expiry are independent; repeated password reads cannot keep
  an authorized key alive indefinitely. The monotonic clock includes sleep.
- Prompt begin/update/end are scoped to the scan ID. Every exit from the coordinator's observation
  scope ends its prompt; a late callback or cleanup from a previous scan cannot affect the current one.

CI is a regression/build check, not a biometric certification or a real-camera spoof test. The RGB
challenge is finite and visible to an attacker. Tailored recordings, adaptive editing, deepfakes and
virtual-camera injection are not solved by this state machine. Do not publish a measured attack success
rate based on synthetic feature traces.

## Manual acceptance on a disposable account

Use a low-value local test account and a unique throwaway password. Record OS build, camera model,
app commit and signing identity; never record the password. Keep a working manual-login path.

1. Build the exact reviewed commit with full Xcode and a stable signing identity. Verify model loading;
   the actual unlock path must stop if the ArcFace model falls back. Verify a missing/disconnected
   selected camera stops scanning rather than unexpectedly switching to another input.
2. Enroll and test in Face Lab before saving a password. Check left/right mapping with both built-in
   and external cameras; check glasses, glare, different lighting and typical distances. Deliberately
   perform the wrong action and an action before its prompt. The UI must report a failed scan.
3. Test printed photos, still images on several displays, ordinary recorded videos, a repeated
   blink/mouth/turn recording, neutral-padded versions, different replay start offsets and speeds,
   and deliberate identity switching/occlusion. Any successful spoof is a deployment blocker.
4. Test lock, wake, display wake, external-monitor connection changes and optional space/hover retries.
   Challenge text must disappear on timeout, rejection, cancellation, manual unlock and app disable.
   Old scans must not remove the next scan's text. Three scans must exhaust the budget until real unlock.
5. Test password delivery only on the disposable account. If targeting the verified loginwindow does
   not work on that OS, stop: do not re-enable global HID posting. Check that injection failure is not
   automatically retried and that the UI does not report success while the Mac remains locked.
6. Open a local scratch editor in that account before locking. While a face unlock is about to submit,
   deliberately unlock through Touch ID or the manual password route. Confirm no characters or Return
   reach the editor. Repeat cancellation/session-expiry/user-switching cases. Delete the scratch content
   afterwards if the test exposes any part of the throwaway password.
7. Confirm idle and absolute expiry, including sleep/wake; reauthorize from Settings when the session
   expires. Restart and confirm that FileVault/initial login still require the normal authentication.
8. Inspect the signed app's dependency list and outbound traffic. Removing network source calls and
   Sparkle reduces exposure but does not establish an enforced network isolation boundary.

Until these pass for the intended machine/camera combination, keep the change under review and do not
use it to deliver a valuable account's password. Keep FileVault, SIP and normal macOS authentication enabled.
