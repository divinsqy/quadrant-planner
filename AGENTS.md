# Quadrant Planner project rules

## Authority and scope

- Continue the existing implementation. Preserve the approved product behavior and architecture; do not redesign or perform unrelated refactors.
- The design baseline is `docs/superpowers/specs/2026-09-30-quadrant-planner-v1-design.md`. Read the roadmap and relevant numbered plans in `docs/superpowers/plans/` before implementing a task.
- Resolve routine implementation choices with the specification and engineering judgment. Ask only for required credentials, destructive operations, or a truly blocking specification contradiction.
- Windows and macOS are first-class targets. Preserve both desktop packaging paths.

## Branch and delivery policy

- Work exclusively on `v1-rewrite`. Verify `git status`, `git branch --show-current`, and recent history before changes.
- Never merge into `main`, switch project work to `main`, or rewrite shared history.
- Use TDD: reproduce a targeted failure, make the smallest correct change, then verify targeted tests.
- Run the full test suite and analyzer at complete feature/plan boundaries. Do not proceed to another plan while either is failing.
- Commit complete logical tasks. Do not push every tiny edit or trigger CI for trivial intermediate changes. Do not claim verification without actual command results.

## Immutable product rules

- Importance, base urgency, derived current urgency, and progress stay in `0..100`; default importance/urgency thresholds are `50/50`.
- Quadrant X is current urgency; Y is importance. Threshold dragging changes classification only, never task coordinates or stored scores.
- Current urgency is `max(ageUrgency, deadlineUrgency)`. Age urgency grows from the base urgency anchor by `1.5` per workday, clamped to `0..100`; deadline pressure is `100 * 2^(-remainingWorkDays / 3)`, with due/overdue tasks at `100`.
- Manually changing base urgency resets `baseUrgencyAnchorAt`; other edits do not.
- Only non-deleted `planned`/`inProgress` tasks enter the default live quadrant and Planner candidate set. Unsatisfied dependencies exclude Planner execution.
- Default weekday windows are `09:00–12:00` and `14:00–18:00`. Lunch is unavailable. Weekends are unavailable unless a one-date override opens them; an override does not change the recurring template.
- Automatic splitting is allowed only for tasks of at least `60` minutes; every automatic block is at least `30` minutes. Preserve locked blocks exactly and avoid overlaps. Human overrides take precedence.
- A task belongs to at most one Project and may have multiple Tags.
- Quadrant single click opens Task Preview; double click opens full Task Detail. Preserve pointer/keyboard accessibility and the list alternative, including clustered tasks.
- Local Drift/SQLite is the source of truth. Local operations must work without login/network; optional Supabase sync must never block them.
- Access/refresh tokens belong only in OS secure storage, never SQLite, logs, or backup files.
- Weekly reports derive from recorded evidence. Optional AI rewriting may change wording but must never invent facts. MD/XLSX/plain text use one report model and preserve local drafts on failure.
- Migration writes transactionally into `quadrant_v1.sqlite`; legacy `quadrant.sqlite` remains untouched. Failed imports roll back and repeated imports must not duplicate data.
- Backup is independent of sync, excludes credentials, and restore creates a pre-restore snapshot before validating/replacing data.

## Architecture boundaries

- `lib/main.dart` is bootstrap only. Do not accumulate UI or business logic there.
- `lib/domain/` owns immutable values and pure urgency, quadrant, calendar, and planning engines. Engines have no widget/database dependencies.
- `lib/core/database/` owns Drift schema and generated mappings. Feature repositories own validation and persistence; widgets must not issue ad-hoc SQL or access Drift DAOs directly.
- `lib/features/<feature>/data`, `application`, and `presentation` separate repositories, controllers/derived state, and widgets. Dashboard consumes repository streams and pure engines.
- `lib/app/` owns shell, router, themes, and tokens. Continue the existing feature-first implementation and Riverpod/go_router integration boundaries.
- The quadrant uses CustomPainter plus hit-testing/semantics/clustering. Task trajectories are derived from activity and the urgency engine, not daily database snapshots.
- `lib/migration/` owns read-only legacy parsing and transactional import. Retain legacy scaffolding until the cleanup plan and reference checks justify removal.
- Plans 01–07 own, respectively: persistence/migration; pure decision engines; desktop workspace; Planner/Focus UX; reports; sync/backup/export; hardening/release. Later plans consume earlier interfaces rather than bypassing them.
- Keep Flutter `3.47.3` and Dart `>=3.13.0 <4.0.0` aligned with the approved plans and existing CI. Generated Drift code is produced by build_runner.

## Verification commands

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/dashboard -r expanded
flutter test test/features/tasks -r expanded
flutter test
flutter analyze
```

For the current Dashboard integration repair, verify that `DashboardController.state.snapshots` contains the created task before inspecting selection, state rebuilds, lookup, and conditional rendering. Do not rewrite `QuadrantBoard` or `TaskPreviewDrawer` while their targeted tests pass.

Release validation additionally covers desktop release builds and installer smoke tests. Label macOS artifacts with their actual architecture and notarization status; claim universal only for a real arm64+x86_64 binary.
