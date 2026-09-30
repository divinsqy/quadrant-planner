# v1 Foundation, Domain, Drift, and Legacy Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the v1 domain model, typed Drift database, repositories, settings defaults, and a safe one-way import from the existing v0.x SQLite database.

**Architecture:** Create a new `quadrant_v1.sqlite` database so the current `quadrant.sqlite` remains untouched. Domain entities are immutable Dart values; Drift tables and repositories are the only persistence boundary. Legacy migration reads the old JSON-state schema and normalizes old score ranges into v1's `0..100` model.

**Tech Stack:** Flutter 3.47.3, Dart >=3.13.0, drift ^2.35.0, drift_flutter ^0.3.1, drift_dev ^2.35.0, build_runner ^2.16.1, flutter_riverpod ^3.4.3, go_router ^18.0.2, uuid, path.

**Spec:** `docs/superpowers/specs/2026-09-30-quadrant-planner-v1-design.md`

## Global Constraints

- New database filename: `quadrant_v1.sqlite`; legacy source remains `quadrant.sqlite`.
- `importance`, `baseUrgency`, `progress` are integers in `0..100`.
- Task statuses: `inbox, planned, inProgress, waiting, completed, cancelled`.
- Default thresholds: importance 50, urgency 50.
- Default weekday work windows: 09:00–12:00 and 14:00–18:00.
- A task belongs to at most one project and any number of tags.
- Deletion is soft-delete via `deletedAt`.
- Legacy source must never be modified or deleted by migration.

## Review Focus

1. Legacy custom ranges such as `importanceMin=-3, importanceMax=7` normalize exactly into 0..100 without assuming old defaults.
2. A partially corrupt legacy row is reported/skipped without aborting valid rows or changing the legacy DB.
3. Running migration twice is idempotent and cannot duplicate tasks/tags/events.
4. Foreign-key deletion cannot orphan dependencies or milestones.
5. Empty Inbox task titles are rejected at repository boundary, while description/tags/deadline remain optional.

---

### Task 1: Lock toolchain and create the v1 bootstrap boundary

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Create: `lib/app/quadrant_planner_app.dart`
- Create: `lib/core/database/database_paths.dart`
- Test: `test/core/database/database_paths_test.dart`

**Interfaces:**
- Produces: `DatabasePaths.forPlatform({required String basePath}) -> DatabasePaths` with `v1DatabasePath` and `legacyDatabasePath`.
- Produces: `QuadrantPlannerApp` as the root widget wrapped by `ProviderScope`.

- [ ] **Step 1: Write the failing path test**

Assert that base `/tmp/QuadrantPlanner` yields `quadrant_v1.sqlite` and `quadrant.sqlite` as distinct sibling files.

- [ ] **Step 2: Run it and verify failure**

Run: `flutter test test/core/database/database_paths_test.dart -r expanded`  
Expected: FAIL because `DatabasePaths` does not exist.

- [ ] **Step 3: Update dependencies and bootstrap**

Set Dart SDK `>=3.13.0 <4.0.0`. Add `flutter_riverpod: ^3.4.3`, `go_router: ^18.0.2`, `drift: ^2.35.0`, `drift_flutter: ^0.3.1`; dev dependencies `drift_dev: ^2.35.0`, `build_runner: ^2.16.1`. Keep current file selector, UUID, secure storage, HTTP, localization, and calendar asset dependencies until later plans retire old code.

- [ ] **Step 4: Implement path/bootstrap interfaces**

`main()` calls `runApp(const ProviderScope(child: QuadrantPlannerApp()))`. Do not build the final shell yet; a minimal app placeholder is sufficient.

- [ ] **Step 5: Generate/get dependencies and verify**

Run: `flutter pub get && flutter test test/core/database/database_paths_test.dart -r expanded && flutter analyze`  
Expected: PASS.

- [ ] **Step 6: Commit**

`git commit -am "chore: bootstrap v1 architecture"`

---

### Task 2: Define immutable domain entities and validation

**Files:**
- Create: `lib/domain/tasks/task.dart`
- Create: `lib/domain/tasks/task_status.dart`
- Create: `lib/domain/tasks/workload.dart`
- Create: `lib/domain/projects/project.dart`
- Create: `lib/domain/projects/milestone.dart`
- Create: `lib/domain/tasks/task_dependency.dart`
- Create: `lib/domain/tags/tag.dart`
- Create: `lib/domain/settings/app_preferences.dart`
- Test: `test/domain/domain_validation_test.dart`

**Interfaces:**
- Produces: `Task.create(...)`, `Task.copyWith(...)`.
- Produces: `TaskStatus`, `Workload`, `Project`, `Milestone`, `TaskDependency`, `Tag`, `AppPreferences.defaults()`.
- Values use UTC timestamps internally; display localization stays outside domain.

- [ ] **Step 1: Write failing domain validation tests**

Pin: title trim/non-empty; 0/100 accepted; -1/101 rejected; progress 0..100; `AppPreferences.defaults()` has thresholds 50/50 and nickname empty.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/domain/domain_validation_test.dart -r expanded`.

- [ ] **Step 3: Implement the domain types**

Task fields must include: `id, title, description, status, projectId, importance, baseUrgency, baseUrgencyAnchorAt, deadline, estimatedMinutes, workload, progress, includeInWeeklyReport, createdAt, updatedAt, completedAt, deletedAt`.

- [ ] **Step 4: Verify domain tests**

Run: `flutter test test/domain/domain_validation_test.dart -r expanded`  
Expected: PASS.

- [ ] **Step 5: Commit**

`git add lib/domain test/domain && git commit -m "feat: define v1 domain model"`

---

### Task 3: Create Drift schema and repositories

**Files:**
- Create: `lib/core/database/app_database.dart`
- Create: `lib/core/database/tables.dart`
- Generated: `lib/core/database/app_database.g.dart`
- Create: `lib/features/tasks/data/task_repository.dart`
- Create: `lib/features/projects/data/project_repository.dart`
- Create: `lib/features/settings/data/preferences_repository.dart`
- Test: `test/core/database/app_database_test.dart`
- Test: `test/features/tasks/task_repository_test.dart`

**Interfaces:**
- Produces: `AppDatabase.forTesting(QueryExecutor)`.
- Produces: `TaskRepository.createTask(TaskDraft)`, `watchTask(id)`, `watchExecutableTasks()`, `save(Task)`, `softDelete(id, at)`.
- Produces: `ProjectRepository` and `PreferencesRepository` streams.
- Tables: tasks, subtasks, projects, milestones, dependencies, tags, task_tags, activity_events, app_preferences, work_schedule_windows, weekend_overrides, focus_sessions, daily_plan_blocks, weekly_reports, weekly_notes, report_style_profiles, sync_outbox, sync_state, sync_conflicts, migration_state.

- [ ] **Step 1: Write failing schema/repository tests**

Assert FK enforcement, one project per task, many tags, soft delete excluded from executable stream, and task save emits updated watch value.

- [ ] **Step 2: Run tests to confirm failure**

Run: `flutter test test/core/database/app_database_test.dart test/features/tasks/task_repository_test.dart -r expanded`.

- [ ] **Step 3: Implement Drift schema**

Set schema version 1 for the new DB. Add indexes on task status/deletedAt/deadline/projectId, activity task/time, and outbox state.

- [ ] **Step 4: Generate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`  
Expected: generated `app_database.g.dart` with no generator errors.

- [ ] **Step 5: Implement repositories**

Repositories own domain<->row mapping and validation; widgets must not use Drift DAOs directly.

- [ ] **Step 6: Verify**

Run: `flutter test test/core/database/app_database_test.dart test/features/tasks/task_repository_test.dart -r expanded && flutter analyze`  
Expected: PASS.

- [ ] **Step 7: Commit**

`git add lib/core/database lib/features/tasks/data lib/features/projects/data lib/features/settings/data test && git commit -m "feat: add typed local persistence"`

---

### Task 4: Implement legacy migration preview and import

**Files:**
- Create: `lib/migration/legacy_models.dart`
- Create: `lib/migration/legacy_reader.dart`
- Create: `lib/migration/legacy_score_normalizer.dart`
- Create: `lib/migration/legacy_migration_service.dart`
- Test: `test/migration/legacy_score_normalizer_test.dart`
- Test: `test/migration/legacy_migration_service_test.dart`
- Fixture: `test/fixtures/legacy_v0.sqlite`

**Interfaces:**
- Produces: `LegacyMigrationService.preview() -> Future<LegacyMigrationPreview>`.
- Produces: `LegacyMigrationService.migrate({required DateTime migrationAt}) -> Future<LegacyMigrationResult>`.
- Produces: `normalizeLegacyScore(int value, int min, int max) -> int`.
- Legacy current urgency is evaluated at `migrationAt`, normalized through the saved legacy urgency range, assigned to `baseUrgency`, and `baseUrgencyAnchorAt=migrationAt`.

- [ ] **Step 1: Write failing normalization tests**

Pin mappings for old default importance `-10..10`: -10->0, 0->50, 10->100; custom range -3..7: -3->0, 2->50, 7->100; clamp out-of-range historical values.

- [ ] **Step 2: Write failing migration fixture tests**

Fixture must contain active/completed/deleted tasks, tags, activity, custom settings, and one malformed task row. Assert preview counts, valid rows imported, malformed row reported, source file hash unchanged, and second migration produces zero duplicates.

- [ ] **Step 3: Run and confirm failure**

Run: `flutter test test/migration -r expanded`.

- [ ] **Step 4: Implement read-only legacy reader and migration**

Open legacy SQLite read-only when supported; never issue DDL/DML to it. Map `active->planned`, `completed->completed`, deleted row -> `cancelled` with original `deletedAt`. Preserve IDs and tags where valid.

- [ ] **Step 5: Add migration-state transaction**

The new DB transaction records source path/hash, migration timestamp, imported counts, skipped row reasons. Roll back the v1 transaction on fatal error.

- [ ] **Step 6: Verify**

Run: `flutter test test/migration -r expanded && flutter test && flutter analyze`  
Expected: PASS.

- [ ] **Step 7: Commit**

`git add lib/migration test/migration test/fixtures && git commit -m "feat: migrate v0 data safely"`

---

### Task 5: Add migration gate to startup

**Files:**
- Create: `lib/migration/migration_controller.dart`
- Create: `lib/migration/migration_screen.dart`
- Modify: `lib/app/quadrant_planner_app.dart`
- Test: `test/migration/migration_screen_test.dart`

**Interfaces:**
- Consumes: `LegacyMigrationService.preview/migrate`.
- Produces: app startup state `checking -> previewRequired | ready | migrationFailed`.

- [ ] **Step 1: Write failing widget tests**

When preview reports 37 tasks/8 tags, show those counts and an Import button. On successful import, transition to app placeholder. On failure, show error and preserve retry/continue-with-new-empty-v1 choices; never offer deletion of legacy DB automatically.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/migration/migration_screen_test.dart -r expanded`.

- [ ] **Step 3: Implement startup migration gate**

The gate appears only when legacy source exists and no successful migration record exists.

- [ ] **Step 4: Verify and commit**

Run: `flutter test && flutter analyze`  
Expected: PASS.  
Commit: `git commit -am "feat: add safe v1 migration gate"`.
