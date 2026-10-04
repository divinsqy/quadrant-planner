# v1 Dashboard 性能回归

`flutter test test/performance/quadrant_benchmark_test.dart -r expanded` 使用确定性的1000个 planned 任务，验证成员完整性、空间网格索引的20000次命中，以及 hover 时重用聚类/索引、数据变更时正确失效。保守 CI 上限：聚类和20000次命中分别低于3000ms。此预算用于发现重大回归，不宣称测试模式达到60fps。

2026-10-03，本地 Flutter3.47.3 测试模式首次测量：聚类1000项11899µs，20000次索引命中26179µs。几何缓存修复前，hover 回归断言失败；修复后，hover 不重新生成 task points、聚类及命中索引。缩放/平移及输入更新仍使缓存失效。原有聚类和命中行为由独立测试继续覆盖。

## 真实桌面帧分析

1. 在主流目标 Windows x64/macOS 机器用 `flutter run --profile -d windows` 或 `-d macos` 启动，使用临时工作区，导入/创建1000个 planned/inProgress 任务；不操作日常数据。
2. DevTools Performance 启用帧记录，预热后分别记录30秒 hover、密集聚类展开、连续平移/滚轮缩放，保持窗口尺寸和文本倍率一致。
3. 检查 UI/raster frame p95 与最慢帧，60fps 的单帧预算为16.67ms；记录机器型号、分辨率、架构、Flutter版本、原始 trace 和丢帧数。
4. 以无网络配置编辑任务，记录提交至 UI 可见更新时间，目标感知延迟低于100ms。

自动回归通过仅证明以上测试预算和缓存行为。真实 GPU/显示器的60fps及编辑延迟属于需在目标机器记录的性能验收，不能用测试 Stopwatch 或 CI 构建代替。
