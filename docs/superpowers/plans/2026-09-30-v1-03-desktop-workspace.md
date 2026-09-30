# v1 Desktop Shell, Dashboard, Tasks, and Projects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the v0 UI with the approved desktop-first design system, navigation shell, live interactive quadrant Dashboard, Inbox/Tasks, Projects, and Task Detail flows.

**Architecture:** Riverpod providers bind Plan 01 repositories and Plan 02 derived engines to feature widgets. The quadrant uses a CustomPainter for rendering plus a separate hit-test/semantics layer for desktop pointer and keyboard access. Navigation uses go_router and preserves workspace state in feature controllers.

**Tech Stack:** Flutter 3.47.3, Riverpod 3.4.3, go_router 18.0.2, Material 3, CustomPainter.

**Spec:** `docs/superpowers/specs/2026-09-30-quadrant-planner-v1-design.md`

## Global Constraints

- Default page is Dashboard.
- Main navigation: Dashboard, Inbox, Tasks, Projects, Planner, Reports, Settings.
- Light/Dark/System themes.
- X=urgency, Y=importance.
- Hover tooltip, single-click preview, double-click full detail.
- Threshold drag changes only classification thresholds.
- Task point color=project, size=workload, status has non-color encoding.
- Keyboard users must be able to focus/select every task represented on the quadrant or use the synchronized list alternative.
- Nickname is editable and used in Dashboard greeting.

## Review Focus

1. 1,000 active task points must not create 1,000 expensive independent animated widgets.
2. Coincident points must cluster but still expose every member to pointer and keyboard users.
3. Threshold drag must clamp 0..100 and never edit task rows.
4. Return navigation must restore filter/scroll/quadrant viewport/selection.
5. Large text and narrow desktop windows must degrade into split/panel layouts without clipped controls.

---

### Task 1: Design system, router, and shell

**Files:**
- Create: `lib/app/theme/app_theme.dart`
- Create: `lib/app/theme/app_tokens.dart`
- Create: `lib/app/router/app_router.dart`
- Create: `lib/app/shell/app_shell.dart`
- Modify: `lib/app/quadrant_planner_app.dart`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**
- Produces route names: `dashboard, inbox, tasks, projects, planner, reports, settings, taskDetail, projectDetail`.
- Produces `AppTheme.light()`, `dark()`.
- Shell exposes navigation rail and compact fallback.

- [ ] **Step 1: Write failing shell tests**

Assert Dashboard default, seven destinations, system/light/dark theme mode, and Ctrl/Cmd+1..7 navigation intents.

- [ ] **Step 2: Implement tokens/theme/router/shell**

Use 8px spacing scale, 10–14px standard radii, 1px neutral borders; shadows only for floating layers.

- [ ] **Step 3: Verify**

`flutter test test/app/app_shell_test.dart -r expanded && flutter analyze`.

- [ ] **Step 4: Commit**

`git commit -am "feat: add v1 desktop shell"`.

---

### Task 2: Dashboard state and greeting/quick capture

**Files:**
- Create: `lib/features/dashboard/application/dashboard_controller.dart`
- Create: `lib/features/dashboard/presentation/dashboard_page.dart`
- Create: `lib/features/inbox/presentation/quick_capture.dart`
- Create: `lib/features/settings/presentation/profile_settings.dart`
- Test: `test/features/dashboard/dashboard_page_test.dart`

**Interfaces:**
- Dashboard controller returns active task snapshots with derived urgency/quadrant, current recommendation, and today queue preview.
- Quick Capture creates `TaskStatus.inbox` with only title required.
- Profile settings edits nickname via `PreferencesRepository`.

- [ ] **Step 1: Write failing widget tests**

Greeting updates when nickname changes; Quick Capture creates trimmed Inbox task; blank title rejected; newly planned/edited task appears in Dashboard stream immediately.

- [ ] **Step 2: Implement controller and UI skeleton**

Header: greeting/date/search/quick capture/sync placeholder. Body reserves left 2/3 quadrant, right 1/3 Now/Queue, lower collapsible list.

- [ ] **Step 3: Verify and commit**

Run targeted test; commit `feat: add dashboard workspace shell`.

---

### Task 3: Interactive quadrant renderer

**Files:**
- Create: `lib/features/dashboard/quadrant/quadrant_board.dart`
- Create: `lib/features/dashboard/quadrant/quadrant_painter.dart`
- Create: `lib/features/dashboard/quadrant/quadrant_hit_test.dart`
- Create: `lib/features/dashboard/quadrant/quadrant_clusterer.dart`
- Create: `lib/features/dashboard/quadrant/quadrant_viewport.dart`
- Test: `test/features/dashboard/quadrant/quadrant_clusterer_test.dart`
- Test: `test/features/dashboard/quadrant/quadrant_board_test.dart`

**Interfaces:**
- `QuadrantBoard(tasks, thresholds, selectedTaskId, onSelect, onOpen, onThresholdChanged)`.
- `QuadrantClusterer.cluster(points, viewport, radiusPx)`.
- Viewport supports pan/zoom/reset and data<->screen conversion.

- [ ] **Step 1: Write failing clustering/math tests**

Assert coordinate transforms, coincident point clustering, cluster expansion member retention, threshold clamp 0..100.

- [ ] **Step 2: Write failing interaction widget tests**

Hover/focus shows metadata; single click selects and opens preview callback; double click calls full-open callback; keyboard Enter opens selected task; threshold drag emits settings only.

- [ ] **Step 3: Implement painter + hit-test layer**

Paint quadrant backgrounds/grid/thresholds/points in one painter. Maintain spatial hit-test index for pointer interactions. Add semantics/focus nodes at cluster/member level without rendering every point as a heavyweight widget.

- [ ] **Step 4: Verify**

Run quadrant tests plus `flutter analyze`.

- [ ] **Step 5: Commit**

`git commit -am "feat: add live interactive quadrant"`.

---

### Task 4: Task preview, detail, Inbox, and Tasks library

**Files:**
- Create: `lib/features/tasks/presentation/task_preview_drawer.dart`
- Create: `lib/features/tasks/presentation/task_detail_page.dart`
- Create: `lib/features/tasks/presentation/task_editor.dart`
- Create: `lib/features/tasks/presentation/tasks_page.dart`
- Create: `lib/features/inbox/presentation/inbox_page.dart`
- Create: `lib/features/tasks/application/task_editor_controller.dart`
- Test: `test/features/tasks/task_flows_test.dart`

**Interfaces:**
- Preview supports lightweight edits and status actions.
- Full detail tabs: Overview, Subtasks, Dependencies, Activity.
- Single click from quadrant updates drawer; double click routes to `/tasks/:id`.

- [ ] **Step 1: Write failing flow tests**

Create Inbox -> plan it -> edit importance/baseUrgency/deadline -> verify base urgency anchor resets only when base urgency changes; status waiting excludes from Dashboard candidates; complete writes activity event.

- [ ] **Step 2: Implement task screens/controllers**

Add synchronized task list selection; preserve list filter and selected task in controller state.

- [ ] **Step 3: Verify and commit**

`flutter test test/features/tasks/task_flows_test.dart -r expanded`; commit `feat: add task workspace flows`.

---

### Task 5: Projects and milestones

**Files:**
- Create: `lib/features/projects/presentation/projects_page.dart`
- Create: `lib/features/projects/presentation/project_detail_page.dart`
- Create: `lib/features/projects/application/project_controller.dart`
- Create: `lib/domain/projects/project_progress.dart`
- Test: `test/features/projects/project_progress_test.dart`
- Test: `test/features/projects/project_page_test.dart`

**Interfaces:**
- Project tabs: Overview, Tasks, Milestones, Timeline.
- `calculateProjectProgress(tasks)` uses estimated minutes, falling back to workload weights for tasks without estimates.
- Project filter can feed Dashboard quadrant without changing task ownership.

- [ ] **Step 1: Write failing progress tests**

Pin weighted progress for known durations and fallback weights; completed 5-minute tasks must not equal an incomplete 3-day task.

- [ ] **Step 2: Implement project screens and filtering**

One task has at most one `projectId`; tags remain orthogonal.

- [ ] **Step 3: Verify full workspace**

Run: `flutter test && flutter analyze`.

- [ ] **Step 4: Commit**

`git commit -am "feat: add project workspace"`.
