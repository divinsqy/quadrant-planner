# v1 Planner UI and Focus Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Plan 02's deterministic suggestions into an editable daily schedule with locked blocks, manual overrides, and Focus sessions that record actual time.

**Architecture:** The Planner controller persists user-confirmed plan blocks separately from regenerated suggestions. Replanning preserves locked/user-pinned blocks. Focus sessions are append-only time records linked to tasks and activity history.

**Tech Stack:** Flutter/Riverpod, Plan 01 Drift repositories, Plan 02 PlannerEngine.

**Spec:** `docs/superpowers/specs/2026-09-30-quadrant-planner-v1-design.md`

## Global Constraints

- Default work windows are 09:00–12:00 and 14:00–18:00.
- Weekends have no slots unless a one-date override exists.
- Locked blocks survive replan exactly.
- Human actions override automatic suggestions.
- Focus actual time never rewrites estimated time automatically.

## Review Focus

1. Replanning around locked blocks must not overlap or truncate locked blocks.
2. Dragging a block across lunch/weekend must snap/reject rather than silently create invalid time.
3. Starting a second Focus session while one is active must require stopping/pausing the first.
4. Crash/restart with an active Focus session must recover elapsed time from persisted start timestamp.
5. Completing a split task must remove future unfinished blocks for that task only after user confirmation.

---

### Task 1: Persist daily plan blocks and overrides

**Files:**
- Create: `lib/features/planner/data/planner_repository.dart`
- Create: `lib/features/planner/application/planner_controller.dart`
- Test: `test/features/planner/planner_repository_test.dart`

**Interfaces:**
- `PlannerRepository.watchDay(date)`.
- `replaceUnlockedSuggestions(date, blocks)`.
- `lockBlock(id, bool)`, `moveBlock(id, start, end)`, `pinTask(taskId,date)`, `skipTask(taskId,date)`.

- [ ] **Step 1: Write failing persistence tests**

Assert locked block unchanged across suggestion replacement; skip/pin stored per-date; no overlapping confirmed blocks accepted.

- [ ] **Step 2: Implement repository/controller**

Controller combines persisted overrides + Plan 02 `PlannerEngine`.

- [ ] **Step 3: Verify and commit**

Targeted tests PASS; commit `feat: persist editable daily plans`.

---

### Task 2: Build Planner timeline UI

**Files:**
- Create: `lib/features/planner/presentation/planner_page.dart`
- Create: `lib/features/planner/presentation/day_timeline.dart`
- Create: `lib/features/planner/presentation/planner_block_card.dart`
- Test: `test/features/planner/planner_page_test.dart`

**Interfaces:**
- Timeline displays 09:00–18:00 with 12:00–14:00 unavailable band.
- Drag/drop invokes controller validation; keyboard move alternative is exposed.
- Replan action replaces unlocked suggestions only.

- [ ] **Step 1: Write failing widget tests**

Lunch band visible; weekend empty state; temporary weekend override shows window; lock icon prevents drag/replan change; recommendation reasons visible.

- [ ] **Step 2: Implement timeline interactions**

Provide mouse and keyboard editing paths; invalid drops restore original position and explain why.

- [ ] **Step 3: Verify and commit**

Run targeted widget test; commit `feat: add interactive planner timeline`.

---

### Task 3: Focus session domain/data

**Files:**
- Create: `lib/domain/focus/focus_session.dart`
- Create: `lib/features/focus/data/focus_repository.dart`
- Create: `lib/features/focus/application/focus_controller.dart`
- Test: `test/features/focus/focus_controller_test.dart`

**Interfaces:**
- `start(taskId, at)`, `pause(at)`, `resume(at)`, `complete(at)`, `markBlocked(at)`.
- `activeSession()` restores after restart.
- Completion appends task activity and computes actual minutes from intervals.

- [ ] **Step 1: Write failing state-machine tests**

Assert no second active session, pause time excluded, restart recovery, blocked/completed terminal behavior, actual duration.

- [ ] **Step 2: Implement focus persistence/state machine**

Use timestamps, not a continuously written stopwatch counter.

- [ ] **Step 3: Verify and commit**

Commit `feat: record focus sessions`.

---

### Task 4: Focus UI and Dashboard/Task integration

**Files:**
- Create: `lib/features/focus/presentation/focus_page.dart`
- Modify: `lib/features/tasks/presentation/task_detail_page.dart`
- Modify: `lib/features/dashboard/presentation/dashboard_page.dart`
- Test: `test/features/focus/focus_page_test.dart`

**Interfaces:**
- Task Detail and Now card expose `Start Focus`.
- Focus page shows task/subtasks/elapsed/estimated remaining and complete/pause/blocked.
- Completion refreshes task activity and Planner state.

- [ ] **Step 1: Write failing integration widget test**

Start from Dashboard recommendation -> Focus -> pause/resume -> complete -> actual duration appears in activity and current day updates.

- [ ] **Step 2: Implement UI/integration**

- [ ] **Step 3: Verify full planner/focus suite**

Run `flutter test test/features/planner test/features/focus -r expanded && flutter analyze`.

- [ ] **Step 4: Commit**

`git commit -am "feat: integrate focus workflow"`.


---

### Task 5: Editable work schedule and weekend overrides

**Files:**
- Create: `lib/features/settings/presentation/work_schedule_settings.dart`
- Create: `lib/features/planner/presentation/weekend_override_dialog.dart`
- Test: `test/features/settings/work_schedule_settings_test.dart`

**Interfaces:**
- Settings edits recurring weekday windows and persists them through `PreferencesRepository`/schedule storage.
- Weekend override dialog writes a one-date `TimeWindow` override and does not mutate the recurring weekly schedule.

- [ ] **Step 1: Write failing settings tests**

Assert default 09:00–12:00 and 14:00–18:00; editing a weekday window changes future Planner suggestions; adding Saturday 10:00–12:00 affects only that date; invalid/overlapping windows are rejected.

- [ ] **Step 2: Implement settings and override dialog**

Changing schedule invalidates derived Planner suggestions but preserves locked blocks and confirmed Focus history.

- [ ] **Step 3: Verify and commit**

Run `flutter test test/features/settings/work_schedule_settings_test.dart test/features/planner -r expanded && flutter analyze`.  
Commit: `feat: make planning hours editable`.
