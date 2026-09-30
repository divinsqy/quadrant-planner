# Quadrant Planner v1.0 设计规范

- 日期：2026-09-30
- 状态：Design approved in conversation; remaining low-level design decisions self-confirmed by user delegation
- 目标平台：Windows / macOS
- 产品定位：Local-first 的桌面任务规划工具，以“重要性 × 紧急性”实时象限、可解释的今日执行队列和可追溯周报为核心

## 1. 产品目标

Quadrant Planner v1.0 不再是“带象限字段的任务列表”，而是一个任务决策工作台。打开应用后，用户应立即看到：

1. 当前所有可执行任务在“紧急性 × 重要性”二维空间中的实时分布；
2. 当前最建议执行的下一项任务，以及清晰的推荐理由；
3. 基于工作时间、截止日期、预计时长和依赖关系生成的今日执行队列；
4. 项目、里程碑、任务、子任务之间的层级关系；
5. 本周工作事实可自动沉淀为周报草稿，并按用户既有周报风格导出。

核心原则：
- Local-first：本地数据永远先写成功，云同步不阻塞使用；
- Explainable：推荐必须可解释，不使用不可见的黑盒总分替用户做决定；
- Fast capture：允许先记录、后整理；
- Data ownership：支持标准格式导出和完整备份；
- Calm UI：视觉中心是任务态势，不做高噪声卡片堆叠；
- Human override：自动规划始终允许用户覆盖。

## 2. 信息架构

主导航：

1. Dashboard
2. Inbox
3. Tasks
4. Projects
5. Planner
6. Reports
7. Settings

默认首页为 Dashboard。

### 2.1 Dashboard
负责回答“现在局势怎样、现在该做什么”。

### 2.2 Inbox
用于快速记录尚未规划的事项，仅标题必填。

### 2.3 Tasks
完整任务库，支持过滤、搜索、批量操作和列表视图。

### 2.4 Projects
目标层，展示项目目标、截止日期、进度、里程碑和项目内任务。

### 2.5 Planner
时间层，负责将可执行任务安排进真实工作时间窗。

### 2.6 Reports
周报生成、编辑、历史归档和多格式导出。

### 2.7 Settings
昵称、主题、工作时间、象限阈值、同步、周报样式、备份与恢复。

## 3. UI Design System

### 3.1 视觉方向
参考高质量桌面效率工具而不是传统 CRUD 管理后台：
- Linear 的信息密度和克制感；
- Things 的任务可读性；
- Apple 桌面应用的留白、层级和动效节奏。

禁止：
- 大量高饱和渐变；
- 每个模块都套厚重 Card；
- 过量阴影；
- 依赖颜色作为唯一状态表达；
- 手机式超大圆角和过度动画。

### 3.2 基础视觉
- 8 px spacing grid；
- 常规容器圆角 10–14 px；
- 1 px 中性边界；
- 阴影仅用于浮层、Tooltip、Drawer；
- 页面背景与内容层仅做轻微明度差；
- 支持 Light / Dark / Follow system。

### 3.3 字体
优先系统字体：
- Windows：Segoe UI Variable / Segoe UI；
- macOS：SF Pro 系统字体；
- 中文跟随平台系统 CJK 字体。

层级：
- Page title：24–28 px / semibold；
- Section title：16–18 px / semibold；
- Body：13–14 px；
- Metadata：11–12 px；
- 数值和时间使用 tabular figures。

### 3.4 四象限视觉编码
四象限采用低饱和背景 tint：
- 重要且紧急：暖红 / coral tint；
- 重要不紧急：冷蓝 / indigo tint；
- 紧急不重要：amber tint；
- 不重要不紧急：slate tint。

任务点：
- 颜色：Project；
- 点大小：Workload；
- 状态：外圈 / icon / stroke；
- 选中：高对比 halo；
- 不以颜色作为唯一语义。

### 3.5 动画
- task point 移动：150–250 ms ease-out；
- drawer：180–220 ms；
- hover：100–150 ms；
- 尊重系统 Reduce Motion。

## 4. Dashboard

布局：
- 顶部 Header：64–72 px；
- 主工作区约 65–70% 高度；
- 左侧 2/3：实时象限；
- 右侧 1/3：Now + Today Queue；
- 下方：可折叠任务列表。

Header：
- 可编辑昵称问候语；
- 今日日期；
- 全局搜索；
- Quick Capture；
- 同步状态；
- 设置入口。

昵称保存在普通用户配置中，可同步，但不与任务内容耦合。

### 4.1 实时象限
- X = urgency；
- Y = importance；
- 默认范围 0–100；
- 横/竖分界线可拖动；
- 拖动阈值仅改变分类，不修改任务坐标；
- Hover 显示 title / project / tags / deadline / remaining workdays / estimate / status / coordinates；
- 单击打开右侧 Task Preview；
- 双击进入完整 Task Detail；
- 相同/近似坐标采用 clustering；
- 支持 zoom / pan / reset；
- 选中任务可显示历史轨迹 tail；
- Task/List/Planner 选择状态双向联动。

### 4.2 Now
显示单个“现在建议做”的任务，并列出推荐理由：
- 当前象限；
- 截止剩余工作日；
- 预计剩余时长；
- 是否进行中；
- 前置依赖是否完成；
- 当前可用时间窗是否足够。

### 4.3 Today Queue
按当天可用时间窗排列，支持：
- 拖拽换序；
- 锁定时间块；
- pin to today；
- today skip；
- replan unlocked items。

## 5. 任务模型

Task 核心字段：
- id UUID
- title
- description
- status
- projectId nullable
- importance 0..100
- baseUrgency 0..100
- deadline nullable
- estimatedMinutes nullable
- workload enum: small / medium / large
- progress 0..100
- includeInWeeklyReport bool
- createdAt / updatedAt / completedAt / deletedAt
- sync metadata

状态：
- inbox
- planned
- in_progress
- waiting
- completed
- cancelled

默认只有 planned / in_progress 进入实时象限与 Planner 候选集。

### 5.1 子任务
支持 Task -> Subtask。普通任务不强制使用。

### 5.2 依赖
支持 task-to-task dependency。
依赖未满足时：
- 任务保留在项目中；
- 不进入 Planner 可执行候选；
- UI 显示 blocking reason。

### 5.3 里程碑
Project 可包含 Milestone，任务可关联里程碑。

## 6. Projects

Project：
- name
- objective
- deadline
- progress
- milestones
- tasks
- tags

一个任务最多属于一个 Project，同时允许多个 Tag。

Project 页面：
- Overview
- Tasks
- Milestones
- Timeline

项目进度优先按 estimated minutes 加权：
completedEstimatedMinutes / totalEstimatedMinutes

缺少时长时，使用 workload fallback weight。

## 7. Task Detail

右侧 Preview：快速查看和轻量编辑。
完整页面：
- Overview
- Subtasks
- Dependencies
- Activity

Activity 记录：
- 创建；
- 状态变化；
- importance / base urgency 修改；
- deadline 修改；
- progress 变化；
- focus session；
- completion；
- dependency change。

返回上级页面时保留：
- filter；
- scroll；
- quadrant zoom/pan；
- selection。

## 8. Focus Session

任务可进入 Focus Session。
显示：
- 当前任务；
- 子任务；
- 预计剩余；
- elapsed；
- 完成 / 暂停 / blocked。

记录 actual duration。
后续可以比较 estimate vs actual，但 v1.0 不做不可解释的机器学习预测。

## 9. Urgency Engine

### 9.1 无 Deadline
baseUrgency 随工作日年龄缓慢增长：

ageUrgency = clamp(baseUrgency + elapsedWorkDays * growthRate, 0, 100)

默认 growthRate = 1.5 / workday，可在高级设置中调整。

### 9.2 有 Deadline
增加 deadline pressure：

deadlineUrgency = clamp(100 * 2^(-remainingWorkDays / 3), 0, 100)

到期日及逾期：
deadlineUrgency = 100

最终：

currentUrgency = max(ageUrgency, deadlineUrgency)

currentUrgency 为计算值，数据库主要保存 baseUrgency、deadline 和时间锚点，避免无意义频繁写入。

### 9.3 重算触发
- create；
- edit；
- deadline change；
- base urgency change；
- importance change；
- dependency completion；
- work calendar change；
- app start；
- workday boundary。

## 10. Quadrant Engine

默认：
- importanceThreshold = 50
- urgencyThreshold = 50

用户可拖动阈值并保存。

分类：
- High importance + high urgency：立即处理
- High importance + low urgency：重点规划
- Low importance + high urgency：尽快处理
- Low importance + low urgency：低优先级

UI 可辅助显示 Q1–Q4，但不作为主文案。

## 11. Planner Engine

### 11.1 默认工作时间
工作日：
- 09:00–12:00
- 12:00–14:00 午休
- 14:00–18:00

每日默认 7 小时。

周末默认不可用，但允许按单日增加临时时段，不修改长期模板。

### 11.2 候选过滤
排除：
- completed；
- cancelled；
- inbox；
- waiting；
- dependency blocked。

候选：
- planned；
- in_progress。

### 11.3 优先级分层
第一层：
- overdue；
- deadline <= 1 workday。

第二层：
- important & urgent。

第三层：
- important & not urgent，且 deadline approaching。

第四层：
- urgent & not important。

最后：
- low importance & low urgency。

同层排序参考：
- deadline；
- importance；
- already in progress；
- milestone proximity；
- available-slot fit。

不对用户展示神秘总分；必须展示可解释理由。

### 11.4 自动拆分
- estimated duration >= 60 min 才可自动拆；
- 每段 >= 30 min；
- 可跨上午/下午/工作日；
- locked block 不被 replan 移动。

### 11.5 人工覆盖
支持：
- Pin to Today
- Skip Today
- Raise Priority
- Defer
- Lock Slot
- Replan

人工操作优先于自动建议。

## 12. Weekly Report Engine

### 12.1 原则
生成方式采用混合模式：
1. Local Rule Builder 先生成事实可靠的结构化初稿；
2. AI 为可选增强，只能改写表达，不得新增未记录事实；
3. 用户预览和编辑后再导出。

### 12.2 用户当前周报风格
参考样本：
- 短句、技术导向；
- 编号列事项；
- 具体交付物；
- 完成度使用 [xx%]；
- 复盘使用 Q/A；
- 下周计划使用编号行动项；
- 保留 RTL / UVM / dmac_regfile 等术语；
- 主管反馈默认留空；
- 避免空泛商务化总结。

内部按 Project 归并事实，但最终默认仍输出简洁编号列表，不强制项目分标题。

### 12.3 数据来源
- completed tasks；
- task progress；
- project milestones；
- focus sessions；
- weekly notes；
- activity；
- manually included tasks。

每个生成条目支持展开 evidence source。

### 12.4 周报笔记
Task / Focus Session 支持“记录本周笔记”，结构可包含：
- problem；
- cause；
- solution；
- learning。

### 12.5 导出
一键导出提供：
- Markdown；
- Excel .xlsx；
- Copyable plain text。

三种格式来自同一个内部 WeeklyReport model，避免内容分叉。

### 12.6 模板导入
支持导入：
- .xls
- .xlsx
- .md
- .txt

解析：
- section names；
- numbering；
- completion format；
- Q/A style；
- terminology policy；
- supervisor feedback section；
- output preference。

生成 ReportStyleProfile，可后续编辑。

## 13. Local-first Sync

本地 Drift/SQLite 为 source of truth。
所有用户写操作：
1. local transaction commit；
2. UI immediately updates；
3. append sync outbox；
4. background push to Supabase。

未登录也拥有完整功能。

### 13.1 同步实体
- tasks
- subtasks
- projects
- milestones
- dependencies
- tags
- task activity
- weekly reports
- report style profile
- work schedule
- quadrant thresholds
- planner configuration
- nickname / normal settings

设备本地：
- window geometry
- temporary filters/search
- scroll position
- cache
- tokens in plaintext

### 13.2 冲突
不同字段变化可自动 merge。
同字段冲突进入 Conflict Center，不静默覆盖。

长文本支持：
- keep local
- keep remote
- merge text

### 13.3 删除
soft delete：
deletedAt != null

回收站默认保留 30 天。

### 13.4 Sync status
Header 仅显示克制状态：
- Synced
- Syncing
- Pending
- Conflict

详细信息进入 Sync Center。

## 14. Data Architecture

建议技术栈：
- Flutter desktop
- Riverpod
- go_router
- Drift + SQLite
- Supabase optional sync
- flutter_secure_storage for credentials
- CustomPainter + Pointer/Mouse hit-test layer for quadrant

Feature-first 目录示例：

lib/
  app/
    router/
    theme/
  core/
    database/
    sync/
    backup/
    calendar/
  features/
    dashboard/
    inbox/
    tasks/
    projects/
    planner/
    reports/
    settings/
  domain/
    task/
    project/
    planning/
    urgency/
    quadrant/
  migration/

禁止继续把业务和 UI 堆入单一 main.dart。

## 15. Legacy Migration

v1.0 首次启动检测 v0.x 数据库。

迁移：
- tasks
- tags
- activity/history
- settings
- calendar-related config where mappable

流程：
1. scan；
2. show count preview；
3. migrate into new schema transactionally；
4. validate counts and essential fields；
5. keep old DB untouched；
6. only allow manual cleanup after user confirms。

迁移失败必须 rollback 新数据库该次 transaction，不破坏旧数据。

## 16. Backup / Restore

云同步不等于备份。

完整备份包：
- DB
- settings
- report styles/templates
- task activity
- projects

建议扩展名：
.qpb

另支持：
- JSON
- CSV
- Markdown
- Excel report

恢复前自动创建当前快照。

## 17. Accessibility

必须支持：
- keyboard-only navigation；
- visible focus ring；
- screen reader semantics for task points；
- tooltips not hover-only：keyboard focus 也可打开；
- minimum text contrast WCAG AA；
- reduced motion；
- color-independent status coding；
- scalable text without layout collapse。

象限点密集时提供 list alternative，不让可访问性依赖散点图。

## 18. Desktop Interaction

快捷键建议：
- Cmd/Ctrl + K：Global Search / Command Palette
- Cmd/Ctrl + N：Quick Capture
- Cmd/Ctrl + Enter：Save
- Esc：Close drawer/dialog
- Cmd/Ctrl + 1..7：主导航
- Space/Enter：选中 task point 时打开 Preview
- Cmd/Ctrl + Shift + P：Replan Today

支持右键上下文菜单，但所有功能必须同时有可发现的普通 UI 入口。

## 19. Performance

目标：
- 1,000 active tasks 下 Dashboard 可交互；
- 常规 DB mutation < 100 ms perceived latency；
- quadrant pan/zoom target 60 fps on mainstream desktop；
- clustering 降低大量点 hit-test 成本；
- urgency 计算使用 derived state / memoization；
- activity history 分页；
- sync batching；
- app launch 不等待网络。

## 20. Error Handling

原则：
- local save failure：明确阻止假成功并提示；
- sync failure：本地继续可用，显示 pending；
- report AI failure：保留本地规则稿；
- export failure：不丢编辑内容；
- migration failure：rollback；
- conflict：显式解决；
- corruption detection：提示 restore/backup，不自动覆盖。

## 21. Testing Strategy

### 21.1 Unit
重点覆盖：
- urgency formula；
- workday calendar；
- quadrant classification；
- threshold changes；
- planner filtering；
- priority layers；
- task splitting；
- project progress；
- weekly report builder；
- conflict merge；
- legacy migration mapping。

### 21.2 Widget
- quadrant hover/click/double click；
- threshold drag；
- task preview drawer；
- Planner drag/lock；
- Weekly Report preview；
- theme switching；
- keyboard navigation。

### 21.3 Golden
关键 UI：
- Dashboard light/dark；
- dense quadrant；
- empty states；
- Task Detail；
- Planner；
- Weekly Report。

### 21.4 Integration
- create -> plan -> focus -> complete -> report；
- offline edits -> reconnect -> sync；
- cross-device conflict；
- backup -> restore；
- legacy DB -> v1 migration。

## 22. Packaging and Release

继续使用 GitHub Actions 生成：
- Windows x64 installer .exe；
- macOS .dmg。

发布前必须：
- analyze；
- unit/widget/integration tests；
- build release；
- package artifact；
- smoke test installer output。

macOS 若没有 Developer ID，构建可以完成但明确标记“not notarized”。有凭据后启用签名和 notarization。

DMG 名称不得错误宣称 universal；只有实际包含 arm64+x86_64 时才使用 universal。

## 23. v1.0 非目标

为控制首个重构版本规模，v1.0 不包含：
- 团队协作/多人项目；
- 完整 Calendar provider 双向同步；
- 移动端客户端；
- AI 自动创建事实或自动更改任务优先级；
- 复杂 Gantt；
- 计费系统；
- 不可解释的机器学习推荐。

这些可在 v1.x 后续迭代。

## 24. v1.0 验收标准

v1.0 可发布需满足：

1. 新建/编辑任务后象限位置立即更新；
2. 分界线可拖动并持久化；
3. hover 显示详情，单击 Preview，双击 Task Detail；
4. Projects / Subtasks / Dependencies / Milestones 可用；
5. Planner 按 09:00–12:00、14:00–18:00 生成今日计划；
6. 周末默认不排，可临时开放；
7. >=60 分钟任务可按 >=30 分钟切块；
8. 用户能覆盖 Planner 自动结果；
9. Focus Session 记录 actual time；
10. Weekly Report 可从事实生成并导出 MD/XLSX/纯文本；
11. Report Style Profile 可从样本导入；
12. 未登录/离线完整可用；
13. Supabase 同步失败不影响本地操作；
14. 同字段冲突不静默丢失；
15. v0.x 数据可安全迁移且旧 DB 保留；
16. Light/Dark 和键盘操作可用；
17. Windows EXE 和 macOS DMG CI 构建通过。

## 25. 实现优先级

建议按风险而不是页面顺序实施：

Phase 1：Domain + Drift schema + legacy migration + tests  
Phase 2：Urgency / Quadrant / Planner engines  
Phase 3：Design system + shell + Dashboard interactive quadrant  
Phase 4：Tasks / Projects / Detail / Focus  
Phase 5：Planner UI  
Phase 6：Weekly Report + template/style import/export  
Phase 7：Supabase sync/conflicts  
Phase 8：backup/restore/accessibility/performance hardening  
Phase 9：desktop packaging and release verification

此规范作为 v1.0 implementation plan 的上游设计基线。任何改变核心数据模型、Urgency 算法、Planner 规则、同步语义或周报事实约束的实现变更，应先更新本设计规范。
