# v1 Weekly Report, Style Import, and Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate factual weekly-report drafts from recorded work, preserve the user's concise technical style, import report-style samples, and export identical content as Markdown, XLSX, and copyable plain text.

**Architecture:** A local `WeeklyReportBuilder` produces a structured model with evidence references. Renderers consume that same model. Optional AI rewriting is a post-processing adapter that receives facts/style and must return edits traceable to the same evidence; local generation remains complete without network.

**Tech Stack:** Dart/Flutter, excel_plus ^2.24.0, file_selector, Plan 01 repositories.

**Spec:** `docs/superpowers/specs/2026-09-30-quadrant-planner-v1-design.md`

## Global Constraints

- Default style: concise Chinese technical writing, numbered work items, `[xx%]`, Q/A reflection, numbered next-week actions, supervisor feedback blank.
- Preserve technical identifiers such as RTL/UVM/module names.
- Internally group by project, but default rendered report remains a flat concise numbered list.
- AI cannot add facts unsupported by evidence.
- MD/XLSX/plain text all render from one `WeeklyReport` model.
- Template/style imports: .xls, .xlsx, .md, .txt.

## Review Focus

1. A week with zero completed tasks but active progress/notes must still generate a useful draft rather than an empty/error report.
2. Duplicate evidence from task completion + activity + focus must not create duplicate work items.
3. Legacy .xls and modern .xlsx imports must decode without blocking the UI thread for normal files.
4. Export failure must keep the unsaved report draft in local DB.
5. AI output containing an unsupported new accomplishment must be rejected or stripped before preview.

---

### Task 1: Weekly report domain and local builder

**Files:**
- Create: `lib/domain/reports/weekly_report.dart`
- Create: `lib/domain/reports/report_evidence.dart`
- Create: `lib/features/reports/application/weekly_report_builder.dart`
- Create: `lib/features/reports/data/report_repository.dart`
- Test: `test/features/reports/weekly_report_builder_test.dart`

**Interfaces:**
- `WeeklyReportBuilder.build(DateRange week, ReportStyleProfile style) -> Future<WeeklyReportDraft>`.
- Draft sections: workItems, reflections QA, nextWeekItems, supervisorFeedback.
- Every generated item carries `List<ReportEvidenceRef>`.

- [ ] **Step 1: Write failing builder tests**

Fixture facts: completed task, 60% task, focus time, weekly note problem/cause/solution, next-week planned task. Assert deduped numbered items, exact completion formatting, preserved technical identifiers, and evidence refs.

- [ ] **Step 2: Implement builder and persistence**

Priority facts: explicit weekly notes/manual inclusion > milestone/task activity > focus corroboration. Never infer accomplishments from title alone if task has no qualifying progress/activity.

- [ ] **Step 3: Verify and commit**

Commit `feat: build factual weekly report drafts`.

---

### Task 2: Report style profile import

**Files:**
- Create: `lib/domain/reports/report_style_profile.dart`
- Create: `lib/features/reports/import/report_style_importer.dart`
- Create: `lib/features/reports/import/markdown_style_parser.dart`
- Create: `lib/features/reports/import/spreadsheet_style_parser.dart`
- Add fixture: `test/fixtures/report_style_sample.md`
- Add fixture: `test/fixtures/report_style_sample.xls`
- Test: `test/features/reports/report_style_importer_test.dart`

**Interfaces:**
- `ReportStyleImporter.importBytes({required String filename, required Uint8List bytes}) -> Future<ReportStyleProfile>`.
- `excel_plus` handles .xls/.xlsx; plain parser handles .md/.txt.

- [ ] **Step 1: Write failing import tests**

Assert sample extracts section headings, numbered work list, `[xx%]`, Q/A, numbered next-week plan, blank supervisor section, and preserve-technical-terms flag.

- [ ] **Step 2: Add `excel_plus: ^2.24.0` and implement importers**

Decode spreadsheet bytes asynchronously where supported. Use content/magic bytes, not extension alone, to detect spreadsheet format.

- [ ] **Step 3: Verify malformed-file behavior**

Malformed input returns a typed parse error and never overwrites current style profile.

- [ ] **Step 4: Commit**

`git commit -am "feat: import weekly report styles"`.

---

### Task 3: Markdown, plain-text, and XLSX renderers

**Files:**
- Create: `lib/features/reports/export/markdown_report_renderer.dart`
- Create: `lib/features/reports/export/plain_text_report_renderer.dart`
- Create: `lib/features/reports/export/xlsx_report_renderer.dart`
- Test: `test/features/reports/report_renderers_test.dart`

**Interfaces:**
- All expose `render(WeeklyReport report, ReportStyleProfile style)`.
- XLSX returns bytes; text renderers return String.

- [ ] **Step 1: Write failing canonical-content tests**

Normalize renderer outputs back to section/item text and assert identical semantic content across all three formats.

- [ ] **Step 2: Implement renderers**

XLSX styling should be restrained and submission-ready; no content may exist only in one output format.

- [ ] **Step 3: Verify and commit**

Commit `feat: export weekly reports in three formats`.

---

### Task 4: Optional AI rewrite adapter with evidence guard

**Files:**
- Create: `lib/features/reports/ai/report_rewriter.dart`
- Create: `lib/features/reports/ai/report_rewrite_guard.dart`
- Test: `test/features/reports/report_rewrite_guard_test.dart`

**Interfaces:**
- `ReportRewriter.rewrite(WeeklyReportDraft draft, ReportStyleProfile style)`.
- Guard validates returned items reference existing evidence IDs and cannot introduce an item without evidence.

- [ ] **Step 1: Write failing guard tests**

Accept wording changes that retain evidence IDs. Reject added accomplishment with unknown/no evidence. On network/error/invalid output, return original local draft unchanged.

- [ ] **Step 2: Implement adapter boundary and guard**

Do not hard-wire a provider API into domain; keep a `ReportRewriteClient` interface so local-only use remains complete.

- [ ] **Step 3: Verify and commit**

Commit `feat: guard optional report rewriting`.

---

### Task 5: Reports UI and export flow

**Files:**
- Create: `lib/features/reports/presentation/reports_page.dart`
- Create: `lib/features/reports/presentation/report_editor.dart`
- Create: `lib/features/reports/presentation/evidence_panel.dart`
- Test: `test/features/reports/reports_page_test.dart`

**Interfaces:**
- Generate -> edit -> optional rewrite -> preview evidence -> export MD/XLSX/copy plain text.
- Export uses file selector and persists draft before opening save UI.

- [ ] **Step 1: Write failing widget tests**

Generate draft, edit item, expand evidence, simulate export cancellation/failure, assert edited draft remains; copy plain text matches rendered preview.

- [ ] **Step 2: Implement page/export actions**

- [ ] **Step 3: Verify**

`flutter test test/features/reports -r expanded && flutter analyze` -> PASS.

- [ ] **Step 4: Commit**

`git commit -am "feat: add one-click weekly reports"`.
