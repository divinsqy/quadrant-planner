# 象限计划 / Quadrant Planner v1.0

面向 Windows x64 和 macOS 的本地优先 Flutter 桌面任务工作区。

- Dashboard：实时重要性/紧急性象限、聚类、任务预览、详情、项目筛选、持久阈值、Now 推荐与快速记录。
- Tasks/Projects：收集箱、任务库、子任务、依赖、活动分页、项目/里程碑/时间线与加权进度。
- Planner/Focus：可编辑今日计划、锁定/Pin/Skip/移动/重排、可恢复的单一专注会话及实际耗时。
- 周报：依据任务、活动、Focus、里程碑和笔记生成；导入 XLS/XLSX/MD/TXT 样式，导出 Markdown、XLSX 和纯文本。可选 AI 只改写措辞，拒绝无依据事实。
- Settings：昵称、浅色/深色主题、工作日模板、单日周末开放、同步与冲突中心、回收站、`.qpb` 备份/安全恢复、JSON/CSV 导出。

## 数据与迁移

Drift/SQLite `quadrant_v1.sqlite` 是事实来源。普通编辑先提交本地事务、更新 UI，再由 outbox 后台同步；未登录和断网可正常使用。Access/refresh token 只存 OS 安全存储，不进入 SQLite、日志或备份。

首次启动检测同一应用数据目录中的 v0 `quadrant.sqlite`，显示迁移预览。迁移会校正旧评分范围、导入任务/标签/事件，支持重试且不重复导入；**保留旧数据库，不覆盖或删除它**。

`.qpb` 为含版本、SHA-256 和逻辑用户数据的 ZIP。恢复前自动创建当前快照；无效文件回滚。恢复后云同步暂停，需明确重新启用。更换云账户须使用独立工作区。

默认工作时段为周一至周五 09:00–12:00、14:00–18:00；午休不可安排。周末默认关闭，单日开放不改变模板。自动拆分仅适用于至少60分钟任务，每块至少30分钟；重新规划保留锁定块。

## 开发与验证

Flutter **3.47.3**，Dart **>=3.13.0 <4.0.0**。在 `v1-rewrite` 开发，遵循根目录 `AGENTS.md` 与批准的 `docs/superpowers/` 文档。

```sh
flutter create . --empty --platforms=windows,macos --project-name quadrant_planner --org com.divins
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
```

首次生成 macOS runner 后，将 `DebugProfile.entitlements` 和 `Release.entitlements` 的 `com.apple.security.files.user-selected.read-write`、`com.apple.security.network.client` 设为 `true`，删除 `keychain-access-groups`。CI 使用相同配置；`--empty` 保留已有应用代码并避免重新生成计数器样例测试。

```sh
flutter run -d macos   # Windows 使用 -d windows
```

四条跨功能旅程既在普通 `flutter test` 中运行，也支持目标桌面的实际集成绑定：

```sh
flutter test integration_test/v1_journeys_test.dart -d macos
flutter test integration_test/v1_journeys_test.dart -d windows
flutter test test/accessibility test/performance -r expanded
```

性能测量与 60fps 帧分析步骤见 [性能记录](docs/performance/v1-dashboard-benchmark.md)。

## 键盘与无障碍

| 操作 | Windows / macOS |
|---|---|
| 搜索 / Command Palette | Ctrl / Cmd + K |
| 快速记录 | Ctrl / Cmd + N |
| 保存任务 / 快速记录 | Ctrl / Cmd + Enter |
| 关闭预览 / 对话框 / 详情 | Esc |
| 切换七个导航页 | Ctrl / Cmd + 1..7 |
| 重新规划所选日期 | Ctrl / Cmd + Shift + P |
| 遍历控件 | Tab / Shift + Tab |
| 象限遍历任务 / 打开详情 | 方向键 / Enter |
| Planner 移动15分钟 | Alt + 上 / 下 |
| Planner 重排 | Ctrl / Cmd + 上 / 下 |

任务/聚类有标题、坐标、状态语义及列表替代；焦点可见。系统减弱动画信号关闭详情页标签插值，桌面路由保留即时状态反馈。

## 可选 Supabase

部署 `supabase/migrations/0002_v1_local_first_sync.sql`，邮箱 OTP 模板需包含验证码。构建时可传公开配置：

```sh
flutter run -d macos --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
```

未配置时保持完整本地模式。真实项目的 migration/RLS、OTP、双设备同步及原生安全存储仍需环境联调；适配边界、断网、冲突、删除保护有自动化测试。

## 安装包

GitHub Actions 的 `Build desktop installers` 工作流完成代码生成、分析、测试和桌面集成测试后，构建 Windows x64 EXE 及 macOS DMG。产物名称包含真实架构；仅 `lipo` 确认同时含 arm64 和 x86_64 时使用 `universal`。

没有 Apple Developer ID 时使用可验证的 ad-hoc 签名，DMG 明确标记 **not-notarized**。首次打开可能被 Gatekeeper 提醒，可在核实来源后通过系统“隐私与安全性”允许打开。只有经过 Developer ID 签名并成功公证、staple/validate 后才标记 notarized。Windows 安装包未配置代码签名时可能有 SmartScreen 提醒。

macOS 使用标准 OS Keychain 保存会话，不启用需要 provisioning profile 的跨 App Keychain Sharing；无 Developer ID 的构建也保留 OS 安全存储边界。

本次构建结果、精确文件名、架构、摘要和限制以 [v1.0 发布验证](docs/releases/v1.0.0-verification.md) 为准；构建通过不等同于已在所有干净电脑人工验证。
