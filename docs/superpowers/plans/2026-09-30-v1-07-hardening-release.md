# v1 Accessibility, Performance, Cleanup, CI, and Desktop Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove obsolete v0 scaffolding, harden accessibility/performance/error handling, complete end-to-end tests, and ship verified Windows EXE and macOS DMG artifacts.

**Architecture:** This plan changes no intended product semantics. It proves cross-feature flows, performance budgets, keyboard/semantics behavior, packaging, and migration/recovery behavior against the approved specification.

**Tech Stack:** Flutter test/integration_test, GitHub Actions, Inno Setup, macOS hdiutil/codesign/notarytool when credentials exist.

**Spec:** `docs/superpowers/specs/2026-09-30-quadrant-planner-v1-design.md`

## Global Constraints

- 1,000 active tasks: Dashboard remains interactive; target quadrant pan/zoom 60 fps on mainstream desktop.
- Ordinary local mutation perceived latency target <100 ms.
- WCAG AA text contrast; visible focus; keyboard-only navigation; reduced motion.
- Analyze/tests must pass before packaging.
- Windows artifact is x64 EXE.
- macOS DMG must state actual architecture; unsigned/unnotarized status is explicit when Apple credentials are absent.
- v0 legacy DB remains preserved.

## Review Focus

1. Fresh install, migrated install, and restored install must all reach the same v1 schema.
2. Keyboard-only user must reach every primary action including clustered task selection and Planner reordering.
3. Reduced-motion mode must remove nonessential interpolation without disabling state feedback.
4. 1,000-task Dashboard must not exhibit quadratic hover/hit-test behavior.
5. Installer artifacts must contain runtime dependencies and launch on clean target machines.

---

### Task 1: Accessibility and keyboard audit

**Files:**
- Create: `test/accessibility/keyboard_navigation_test.dart`
- Create: `test/accessibility/semantics_test.dart`
- Modify: feature widgets as failures identify gaps

**Interfaces:**
- Global shortcuts: Ctrl/Cmd+K search, Ctrl/Cmd+N capture, Ctrl/Cmd+Enter save, Esc close, Ctrl/Cmd+1..7 navigation, Ctrl/Cmd+Shift+P replan.
- Quadrant task/cluster semantics include task title and coordinates/status.

- [ ] **Step 1: Write failing keyboard/semantics tests**

Traverse all nav destinations, quick capture, quadrant selection/open, drawer close, planner block move/lock, report generate/export actions.

- [ ] **Step 2: Fix UI semantics/focus until tests pass**

Respect `MediaQuery.disableAnimations` or equivalent reduced-motion signal.

- [ ] **Step 3: Verify and commit**

Commit `fix: harden desktop accessibility`.

---

### Task 2: Performance harness and dense quadrant optimization

**Files:**
- Create: `test/performance/quadrant_benchmark_test.dart`
- Modify: quadrant cluster/hit-test/controller code only as needed
- Create: `docs/performance/v1-dashboard-benchmark.md`

**Interfaces:**
- Benchmark fixture generates 1,000 active tasks deterministically.
- Hit-test/clustering must use spatial bucketing/indexing, not scan every point on every pointer event.

- [ ] **Step 1: Add benchmark/regression test**

Measure build/clustering and repeated hit-test operations with a generous CI ceiling; document local frame-profile procedure for 60fps verification.

- [ ] **Step 2: Optimize measured bottlenecks**

Memoize derived urgency by day/input revision; batch state updates; avoid rebuilding entire page for hover-only changes.

- [ ] **Step 3: Verify and commit**

Commit `perf: harden dense dashboard performance`.

---

### Task 3: End-to-end product journeys

**Files:**
- Create: `integration_test/task_to_report_test.dart`
- Create: `integration_test/offline_sync_conflict_test.dart`
- Create: `integration_test/backup_restore_test.dart`
- Create: `integration_test/legacy_migration_test.dart`

**Interfaces:**
- Journey 1: create -> plan -> focus -> complete -> weekly report.
- Journey 2: local offline edit -> reconnect -> same-field conflict -> resolve.
- Journey 3: backup -> mutate -> restore.
- Journey 4: v0 fixture -> migration -> Dashboard.

- [ ] **Step 1: Write integration tests from acceptance criteria**

- [ ] **Step 2: Fix only defects exposed by journeys; update spec first if semantics must change**

- [ ] **Step 3: Verify**

Run platform-appropriate integration tests plus `flutter test && flutter analyze`.

- [ ] **Step 4: Commit**

`git commit -am "test: cover v1 end-to-end journeys"`.

---

### Task 4: Remove obsolete v0 files and accidental transfer artifacts

**Files:**
- Remove/replace when no longer imported: `lib/models.dart`, `lib/store.dart`, old `lib/sync_client.dart`
- Remove: `WRITE_PERMISSION_TEST.md`
- Remove: `.bootstrap/payload.part.00`
- Update: `README.md`
- Update: `test/models_test.dart`, `test/widget_test.dart` to v1 tests or remove superseded smoke tests

**Interfaces:**
- No v1 code imports legacy app model/store files.
- Migration has its own legacy reader and remains able to parse old DB.

- [ ] **Step 1: Confirm references**

Run `git grep` for old imports/classes and remove only after migration implementation no longer depends on them.

- [ ] **Step 2: Clean files and update README**

Document v1 feature set, local-first behavior, migration, build/run commands, and sync optionality.

- [ ] **Step 3: Verify and commit**

`flutter test && flutter analyze`; commit `chore: remove v0 scaffolding`.

---

### Task 5: Update CI and package v1.0

**Files:**
- Modify: `.github/workflows/build-desktop-installers.yml`
- Modify: `installer/windows/quadrant_planner.iss`
- Modify: `scripts/build_macos_dmg.sh`
- Modify: `pubspec.yaml`

**Interfaces:**
- App version: `1.0.0+10` for first v1 release candidate unless a later build number is required by existing release history.
- CI runs code generation check, analyze, unit/widget tests, builds release, packages artifacts.
- macOS script derives artifact architecture from built app/binary and names DMG accurately.

- [ ] **Step 1: Set version and CI checks**

Add `dart run build_runner build --delete-conflicting-outputs` or generated-file verification before analyze. Keep Flutter 3.47.3 baseline for reproducibility.

- [ ] **Step 2: Add package smoke checks**

Windows: assert EXE exists and Release folder contains required VC runtime DLLs before Inno packaging.  
macOS: assert app exists, codesign verify (ad-hoc or Developer ID), create DMG, run `hdiutil verify`.

- [ ] **Step 3: Run local non-packaging verification**

`flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze && flutter test` -> PASS.

- [ ] **Step 4: Commit and trigger GitHub Actions**

Commit `build: package Quadrant Planner v1.0`.

- [ ] **Step 5: Verify both CI jobs and artifacts**

Windows job PASS and uploads `QuadrantPlanner-Windows-x64`.  
macOS job PASS and uploads `QuadrantPlanner-macOS`.  
Record run ID, artifact digests, exact EXE/DMG filenames, architecture, and notarization status in release notes.

---

### Task 6: Final verification against spec acceptance criteria

**Files:**
- Create: `docs/releases/v1.0.0-verification.md`

**Interfaces:**
- Checklist mirrors all 17 acceptance criteria from the design spec.

- [ ] **Step 1: Execute each acceptance criterion**

Record test/manual evidence rather than marking by assumption.

- [ ] **Step 2: Run final full suite**

`flutter analyze` -> no issues.  
`flutter test` -> all pass.  
Relevant integration tests -> all pass.  
Latest Windows/macOS workflow -> both pass.

- [ ] **Step 3: Record known limitations**

If no Apple Developer ID credentials exist, explicitly state DMG is not notarized; do not call it signed/notarized beyond actual evidence.

- [ ] **Step 4: Commit**

`git add docs/releases/v1.0.0-verification.md && git commit -m "docs: verify v1.0 release"`.
