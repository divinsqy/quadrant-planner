# v1 Urgency, Quadrant, Calendar, and Planner Engines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement deterministic, explainable pure-domain engines for urgency, quadrant classification, work calendars, candidate ranking, and time-slot planning.

**Architecture:** Engines are pure Dart services with no widget or database dependency. Repositories supply tasks/settings; engines return immutable derived models so UI and sync can evolve independently.

**Tech Stack:** Dart 3.13.x, Flutter test, existing bundled calendar asset, Plan 01 domain values.

**Spec:** `docs/superpowers/specs/2026-09-30-quadrant-planner-v1-design.md`

## Global Constraints

- Urgency formula: `ageUrgency = clamp(baseUrgency + elapsedWorkDays*1.5, 0, 100)`.
- Deadline pressure: `100 * 2^(-remainingWorkDays/3)`; due/overdue = 100.
- `currentUrgency = max(ageUrgency, deadlineUrgency)`.
- Editing base urgency resets `baseUrgencyAnchorAt`.
- Default thresholds 50/50; threshold changes never mutate task values.
- Weekday windows 09:00–12:00 and 14:00–18:00; weekend unavailable unless overridden.
- Auto-split only if estimate >=60 min; each chunk >=30 min.
- Recommendations expose reasons rather than a user-facing opaque score.

## Review Focus

1. Deadline exactly now, overdue, and far-future dates must clamp predictably.
2. Calendar year not covered by holiday JSON must fall back to Mon–Fri and mark the result estimated rather than returning null/crashing.
3. Daylight-saving/time-zone transitions must not change workday counts because calculations use local calendar dates.
4. A 60-minute task may split; a 59-minute task may not.
5. Planner with no fitting slot must leave a task unscheduled and provide a reason, never create negative/overlapping blocks.

---

### Task 1: Work calendar service and schedule model

**Files:**
- Create: `lib/domain/planning/work_schedule.dart`
- Create: `lib/domain/planning/work_calendar.dart`
- Create: `lib/core/calendar/holiday_calendar_loader.dart`
- Test: `test/domain/planning/work_calendar_test.dart`

**Interfaces:**
- Produces: `WorkSchedule.standard()`.
- Produces: `WorkCalendar.isWorkday(DateTime localDate) -> WorkdayDecision`.
- Produces: `WorkCalendar.workdaysBetween(DateTime from, DateTime to) -> WorkdayCount` with `isEstimated`.
- Produces: `availableWindows(DateTime localDate) -> List<TimeWindow>`.

- [ ] **Step 1: Write failing calendar tests**

Assert Mon–Fri, weekend, explicit holiday, standard windows, weekend override, and uncovered year fallback to weekday-only with `isEstimated=true`.

- [ ] **Step 2: Run and confirm failure**

`flutter test test/domain/planning/work_calendar_test.dart -r expanded`.

- [ ] **Step 3: Implement schedule/calendar**

Use local date parts for business-day iteration. Do not use 24-hour duration division for workday counts.

- [ ] **Step 4: Verify and commit**

`flutter test test/domain/planning/work_calendar_test.dart -r expanded` -> PASS.  
Commit: `git commit -am "feat: add work calendar engine"`.

---

### Task 2: Urgency engine

**Files:**
- Create: `lib/domain/urgency/urgency_engine.dart`
- Create: `lib/domain/urgency/urgency_result.dart`
- Test: `test/domain/urgency/urgency_engine_test.dart`

**Interfaces:**
- Consumes: `Task`, `WorkCalendar`.
- Produces: `UrgencyEngine.calculate(Task task, DateTime at) -> UrgencyResult`.
- `UrgencyResult`: `value` int 0..100, `ageComponent`, `deadlineComponent?`, `calendarEstimated`.

- [ ] **Step 1: Write failing formula tests**

Pin: base 35 + 10 workdays -> 50; deadline remaining 3 workdays -> 50; remaining 0 ->100; final=max components; manual base anchor reset uses only days after new anchor.

- [ ] **Step 2: Run and verify failure**

`flutter test test/domain/urgency/urgency_engine_test.dart -r expanded`.

- [ ] **Step 3: Implement formula**

Round displayed/stored derived urgency to nearest integer only at the result boundary; keep component computation in double.

- [ ] **Step 4: Verify and commit**

Run targeted test and `flutter analyze`; commit `feat: add explainable urgency engine`.

---

### Task 3: Quadrant engine

**Files:**
- Create: `lib/domain/quadrant/quadrant.dart`
- Create: `lib/domain/quadrant/quadrant_engine.dart`
- Test: `test/domain/quadrant/quadrant_engine_test.dart`

**Interfaces:**
- Produces: `QuadrantEngine.classify({required int importance, required int urgency, required int importanceThreshold, required int urgencyThreshold}) -> Quadrant`.
- Quadrants: `doNow, plan, expedite, lowPriority`.

- [ ] **Step 1: Write failing boundary tests**

Pin values exactly equal to threshold as high side. Verify moving thresholds changes classification but leaves task importance/baseUrgency unchanged.

- [ ] **Step 2: Implement and verify**

Run targeted tests; commit `feat: add quadrant classification`.

---

### Task 4: Candidate filtering and explainable ranking

**Files:**
- Create: `lib/domain/planning/planner_candidate.dart`
- Create: `lib/domain/planning/planner_ranker.dart`
- Test: `test/domain/planning/planner_ranker_test.dart`

**Interfaces:**
- Produces: `PlannerRanker.rank(List<TaskPlanningSnapshot> tasks, DateTime now) -> List<PlannerCandidate>`.
- Each candidate exposes `tier` and `List<RecommendationReason>`.
- Blocked/waiting/inbox/completed/cancelled tasks are excluded before ranking.

- [ ] **Step 1: Write failing ranking tests**

Assert overdue/deadline<=1 workday before Q1, Q1 before approaching Q2, then expedite, then low priority. Within tier pin deadline, importance, in-progress preference, milestone proximity, slot-fit tie breakers.

- [ ] **Step 2: Implement minimal ranker**

Internal comparison keys are allowed; UI-facing output must be reasons, not a synthetic score.

- [ ] **Step 3: Verify and commit**

`flutter test test/domain/planning/planner_ranker_test.dart -r expanded` -> PASS.  
Commit: `feat: rank executable tasks explainably`.

---

### Task 5: Time-slot planner and splitting

**Files:**
- Create: `lib/domain/planning/planner_engine.dart`
- Create: `lib/domain/planning/planned_block.dart`
- Test: `test/domain/planning/planner_engine_test.dart`

**Interfaces:**
- Produces: `PlannerEngine.planDay({required DateTime date, required WorkSchedule schedule, required List<PlannerCandidate> candidates, required List<PlannedBlock> lockedBlocks}) -> DayPlanSuggestion`.
- `DayPlanSuggestion` contains ordered blocks plus unscheduled candidates with reason.

- [ ] **Step 1: Write failing schedule tests**

Pin no blocks in 12:00–14:00; no weekend blocks by default; temporary Saturday window works; 59-min task not split; 60-min task may split into >=30-min blocks; locked block unchanged after replan; no overlaps.

- [ ] **Step 2: Run and confirm failure**

`flutter test test/domain/planning/planner_engine_test.dart -r expanded`.

- [ ] **Step 3: Implement greedy deterministic packing**

Use ranked candidates and earliest fitting windows. Preserve locked blocks first, subtract them from availability, then pack unlocked work. Leave impossible tasks unscheduled.

- [ ] **Step 4: Verify full engine suite**

Run: `flutter test test/domain/planning test/domain/urgency test/domain/quadrant -r expanded && flutter analyze`.

- [ ] **Step 5: Commit**

`git commit -am "feat: add deterministic day planner"`.
