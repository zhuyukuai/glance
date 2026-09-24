#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/glance-tests.XXXXXX")"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
COMMON=(
  glance/Liveness/LandmarkGeometry.swift
  glance/Liveness/GeometryLiveness.swift
  glance/Liveness/GlareCue.swift
  glance/Liveness/LivenessCues.swift
  glance/Liveness/LivenessScoring.swift
  glance/Liveness/ActiveLivenessChallenge.swift
  glance/Liveness/LivenessAnalyzer.swift
)
for test in liveness_selftest replay_challenge_selftest; do
  swiftc -module-cache-path "${TMPDIR:-/tmp}/glance-security-module-cache" -O -o "$TEST_BUILD_DIR/$test" "${COMMON[@]}" "tools/$test.swift"
  "$TEST_BUILD_DIR/$test"
done
swiftc -module-cache-path "${TMPDIR:-/tmp}/glance-security-module-cache" -O -o "$TEST_BUILD_DIR/unlock_security_selftest" \
  glance/FaceScanContinuity.swift glance/UnlockAttempt.swift glance/CredentialSessionLifetime.swift tools/unlock_security_selftest.swift
"$TEST_BUILD_DIR/unlock_security_selftest"
