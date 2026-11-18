# 验证记录 — StressWatch 界面原型 v1.0.0

## 1. 构建期静态检查

- 构建命令：`node build.mjs`；结果见 `lint-report.json`。
- 源图 53 张，SHA-256 全部记录于 `page-spec.json` / `build-record.json`；映射唯一且完整，无重复、无遗漏。
- 页面片段 15 个，全部为语义化 `<section>`；图标 216 处、图表 50 处均在构建期展开为内联 SVG。
- 无外链资源、无 javascript:/data: URL、无内联事件、无 iframe、无 fetch/XHR；本专家 runtime `lintGeneratedHtml` 全部通过。

## 2. 无头浏览器交互回归（1440×900，verify.html + verify.js）

- 逐页切换 15 个页面：全部成功，`visibleScreens === 1`（修复了 AI 聊天页 `display:flex` 串页缺陷）。
- 水平溢出：0 处。
- 无名称的可交互元素：0 处。
- 运行时错误：0 条。
- 交互断言：tooltip=true, sheetOpen=true, sheetClosed=true, sendDisabledWhenEmpty=true, sendEnabledWhenTyped=true, emptyStateVisible=true, sleepMonthSwitch=true。

## 3. 真实视口取证（Chrome CDP Emulation.setDeviceMetricsOverride）

| 取证名 | 视口 | 当前页 | 横向溢出 | 页面异常 | 底部标签栏 |
|---|---|---|---|---|---|
| viewport-1440-today | 1440×900 | today | 无 | 0 | 显示 |
| viewport-1440-trends | 1440×900 | trends | 无 | 0 | 显示 |
| viewport-1440-sleep-day | 1440×900 | sleep-day | 无 | 0 | 隐藏 |
| viewport-375-today | 375×812 | today | 无 | 0 | 显示 |
| viewport-375-health | 375×812 | health | 无 | 0 | 显示 |
| viewport-375-sleep-day | 375×812 | sleep-day | 无 | 0 | 隐藏 |

- 桌面 1440×900：手机画布 390×782（窗口较矮时自动压缩高度），整机完整可见，左右面板正常。
- 手机 375×812：手机画布 375×756，底部标签栏位置 734–800，页面全宽铺满。
- 截图文件：`viewport-*.png`（仅作为本地验收材料，未在会话中展示）。

## 4. 未验证 / 未运行

- 平台导入、Test Run、头像显示、发布：`not_run`。
- 真实账号、登录、健康数据源、持久化、系统分享、AI 模型调用：`not_verified`（均为本地 mock）。
- 未在 53 张截图中出现的页面 / 时间范围 / FAQ 正文：以明确标注的空状态呈现，未补绘。
