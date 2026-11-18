# 交付汇编与验收 — StressWatch 视觉资源补全 v1.0.0

> 主理人（team-lead）收口文档。配套权威依据：
> - `01-visual-spec.md`（558 行，视觉规范，含 R1/R2 修订）
> - `02-usage-and-data-spec.md`（15:25 版，场景映射 + 图表数据口径）
> - `chart-series.json`（15:25 版，50 条序列唯一数值真源）
> - `03-asset-manifest-and-swiftui.md`（资源清单 + SwiftUI 接入）
> 本文件只做汇总、验收与缺失/待确认登记，不重复规范数值。

## 1. 交付总览

| 层 | 交付物 | 数量 | 状态 |
|---|---|---|---|
| 视觉规范 | `spec/01-visual-spec.md` | 1 | ✅ 冻结（558 行） |
| 场景+口径 | `spec/02-usage-and-data-spec.md` + `data/chart-series.json` | 2 | ✅ 15:25 版 |
| 资源清单 | `assets/manifest.json` | 1（24 resources + 14 charts） | ✅ `darkVariant: reserved` 已补齐 24/24 |
| 矢量资源 | `assets/ill/**`（15）+ `assets/art/**`（9） | 24 SVG | ✅ 全部可内联、无外部引用、无 SVG 内文字 |
| SwiftUI 接入 | `Healthy/Resources/Assets.xcassets/{Illustrations,ArticleArt,EmptyStates}/` | 24 imageset | ✅ 逐字节同原型侧 |
| 原型产物 | `index.html` / `prototype.css` / `prototype.js` | 1 套 | ✅ 重建通过、全量回归通过 |

**资源总数 = 24 个 SVG（10 复刻 + 14 风格化）+ 14 类图表 ID（不落文件，由 `chart-series.json` 承载 50 条序列）。**

## 2. 资源目录结构

```
prototype/assets/
├─ spec/
│  ├─ 01-visual-spec.md            # 视觉规范（权威，含 R1/R2）
│  ├─ 02-usage-and-data-spec.md   # 场景 + 图表数据口径（15:25）
│  └─ 03-asset-manifest-and-swiftui.md  # 资源清单 + SwiftUI 接入
├─ data/
│  └─ chart-series.json           # 50 条序列唯一数值真源
├─ ill/
│  ├─ hero/  (1)  faq/ (4)  habit/ (6)  promo/ (1)  empty/ (3)
├─ art/
│  ├─ hrv/  (6)   age/  (3)
└─ manifest.json                  # 24 resources + 14 charts
（注：`assets/chart/` 示意模板位未落地，按 R2 不作为验收项）
```

## 3. 24 个 SVG 资源清单（起源自 `manifest.json`）

| # | 资源 ID | 类 | 起源 | viewBox | 页面 | 说明 |
|---|---|---|---|---|---|---|
| 1 | `ill-hero-pool-relax` | ill | screenshot | 390×292 | today | 今日页 hero，唯一属性改动 = `preserveAspectRatio="xMidYMid slice"` |
| 2 | `ill-faq-stress-overload` | ill | screenshot | 160×116 | today | FAQ 卡插画（绿底） |
| 3 | `ill-faq-measure-principle` | ill | screenshot | 160×116 | today | FAQ 卡插画（绿底） |
| 4–7 | `ill-habit-steps/noise/water/caffeine` | ill | screenshot | 60×60 | actions | 4 张习惯卡插画 |
| 8 | `ill-promo-understand-trend` | ill | screenshot | 118×78 | trends | 趋势横幅插画 |
| 9 | `ill-faq-vo2max-what` | ill | screenshot | 160×116 | vo2max | 心形线描（#F0A36E） |
| 10 | `ill-faq-vo2max-improve` | ill | screenshot | 160×116 | vo2max | 心形线描（#6FC08C） |
| 11 | `ill-habit-sun` | ill | stylized | 60×60 | actions | 补「晒太阳」灰环空位 |
| 12 | `ill-habit-breath` | ill | stylized | 60×60 | actions | 补「呼吸正念」灰环空位 |
| 13 | `ill-empty-feeling` | ill | stylized | 120×88 | actions | 空状态（关联感受） |
| 14 | `ill-empty-range` | ill | stylized | 120×88 | trends | 空状态（时间范围） |
| 15 | `ill-empty-watch-pending` | ill | stylized | 120×88 | today-detail | 空状态（手表待连接） |
| 16 | `art-hrv-cover` | art | stylized | 320×160 | ai-article | 文章题图·HRV 分量解释 |
| 17 | `art-age-cover` | art | stylized | 320×160 | ai-article | 文章题图·身体年龄 |
| 18–22 | `art-hrv-{sdnn,mean-rr,pnn50,mxdmn,cv}` | art | stylized | 320×180 | ai-article | HRV 五节章节示意图 |
| 23 | `art-age-biological` | art | stylized | 320×180 | ai-article | 生物年龄章节图 |
| 24 | `art-age-aging-rate` | art | stylized | 320×180 | ai-article | 衰老速度章节图 |

**笔误裁定（已固化于 03 §5）**：题图 `320×160`（2:1），章节图 `320×180`（16:9），空状态 `120×88`——以 01 §2.1 为准，02 §1 表格中对应尺寸为笔误。

## 4. 图表数据序列总览（50 条，`chart-series.json`）

| 页面 | 序列数 | renderer 分布 | 关键硬锚点（与页面可见数值自洽） |
|---|---|---|---|
| today / today-detail / day-hrv | 8 | line×3 / area×2 / wave×2 / bars×1 | 平均 HRV 40 / 基准 30.7 / 静息心率 69 |
| actions | 4 | mini×4（含 10 处实例共用 VITAL14） | 生命体征 14 日序列 |
| insights | 3 | line×3 | 同源 HRV5 |
| trends | 6 | line×2 / bars×2（周）/ spark×2 | 周 02–08；体重 spark 14 点 |
| health | 2 | spark×1 / area×1 | 34.2 岁「多 5.9 岁」 |
| sleep-day | 11 | ring×1 / step×1 / bars×3 / dots×1 / capsule×1 | 时段 02:47–07:42 |
| sleep-month | 6 | bars×6 | 时长 6.15h / 质量 75 / 连续性 79 |
| sleep-vitals | 5 | line×5（14 点） | 有效睡眠占比 96 / 恢复性 2.6h |
| body-age | 2 | area×2 / disc×1 | 衰老速度 0.2× |
| vo2max | 1 | line×1（浅紫 #C7C4E8 既有例外） | 平均 38 / 范围 28–67 |
| sheets（sleep-80） | 1 | stack×1 | 睡眠阶段占比 |
| **合计** | **50** | 14 类全覆盖 | 26 行修正表全部落实 |

完整连续数值、坐标含义（x 轴时间粒度 + 采样点数）、单位、取值范围、`baseline`、`missing`、`source`、`caliber`、`aria` 见 `chart-series.json` 逐条记录与 02 §5。

**3 个缺失点**（均为 trends 周折线第 7 日「11/08 无数据」）：JSON 记 `null`，落地时已转 `0 + data-colors=faint + aria「第 7 点无数据」`，**未把文本 null 传入 data-values**（避免 `nums()` 丢弃造成点数错位）。

## 5. 使用场景、标注与口径（摘要）

- **使用场景总表 + alt/aria 填实 + manifest 14 字段 + 空/加载/禁用/无数据四态** → 02 §1、§2。
- **文章配图**：9 张逐张的章节映射、画面三要素、≤30 字图注、底部 24px 标注带内容 → 02 §3。**第 2 篇文末「（截图在此处截断…）」占位段原样保留，`art-age-aging-rate` 固定插在其之前**。
- **来源/单位/口径/图例**全部落 DOM（`.note-source-*` / `.chart-source` / `.source-note` / `.figure-note`），不写进 SVG。字号 ≥11.5px、色 `--ink-2 #5C6268`（6.17:1）；8.5px `#9BA1A7` 仅坐标轴刻度；四档状态色禁止作文字色；图例 ≤3 项。
- **演示数据声明**：所有序列属「原型演示数据（非真实健康测量）」；`{来源}` 仅取「原型演示数据 / 截图可见值」，不与 Healthy/ 真实 HealthKit 链路混淆（02 §5.3 / JSON `caliber`）。

## 6. 接入指南

**原型侧（HTML）**：容器加 `data-art="<ID>"`，构建器内联对应 SVG 并写 `data-origin="screenshot|stylized"`；图表 `<div class="chart" data-series="<id>">`，构建期从 `chart-series.json` 注入数值、null→faint、46 装饰点由 `charts.mjs disc()` 生成（`seed` 仅保留给 disc）。

**SwiftUI 侧**：资源已落入 `Assets.xcassets/{Illustrations,ArticleArt,EmptyStates}/*.imageset`，直接 `Image("资源ID")`；`preserves-vector-representation` 已开，矢量缩放无损；`darkVariant: reserved` 表示本版不产出深色文件、待后续按截图补充。

**复用边界**：资源为纯矢量、无外部依赖、命名 kebab-case 稳定，跨页面/文章/原生复用无需改色（局部配色由 01 §4.2 A 表锁定）。

## 7. 验证结果（文本证据）

| 验证项 | 结果 |
|---|---|
| `node build.mjs` | exit 0；screens 15 / screenshots 53 / icons 211 / charts 50 / series 50 / artResources 24 / discDots 46 |
| 静态检查 11 项 | 全 true（无外链/无 javascript:/data: URL/无内联事件/无 iframe/无 fetch/语义 section 等） |
| runtime `lintGeneratedHtml` | passed=true |
| `manifestContract` | resources 24 / chartKinds 14 / seriesIdsCovered 50 / **darkVariantReserved 24/24** / prototypeDarkSvgFiles 0 |
| 产物残留 | data-art 残留 0 / data-series 残留 0 / chart-svg 50 / data-origin 仅 `screenshot|stylized` |
| 无头 Chrome（1440×900, verify.html） | 15 页 visibleScreens=1；overflow 0；unnamed 0；errors 0；12 项交互断言全 True |
| SVG 合规（24 文件） | 可解析、根含 xmlns/role/aria、0 真实外部引用、0 SVG 内文字 |
| SwiftUI imageset | 24/24 合法 Contents.json，与原型侧逐字节一致 |
| 数据自洽 | 50 序列均值/极值与页面硬锚点断言通过；46 装饰点三方同值 |

## 8. 缺失项与待确认信息

**已裁决（4 条，源自 01 §9 R1，已落地）**：Q5 深色不启用 / Q19 disc 中心文字保留+DOM 口径副本 / Q20 来源角标 ≥11.5px `--ink-2` / Q21 视觉规范退出数据语义。

**主理人追加裁定（纳入工程落地）**：Q10 睡眠连续性第 7 柱改有效值 77（无数据示例由 trends 08 日柱承担）/ Q11 仅 rhr-wave 补 90/0 / Q12 sleep-vitals 13 刻度保留并注明「首点无标签」/ Q13 取整值不重算。

**仍未确认（17 条，详见 02 §4，附默认处理）**：真实 HRV 采样频率与 RMSSD 窗口、睡眠分期判定算法、VO2 测量来源、文章示意图是否允许、深色模式是否必需、各图表实测口径边界等。默认统一标注「原型演示数据（非真实健康测量）」、不推断算法、不写入 App 真实链路；逐项默认处理见 02 §4「状态」列。

**结构性边界（非缺失）**：`assets/chart/` 示意模板位未落地（按 R2 不算缺项）；原型 HTML 侧不产出 `--dark` 文件（按 Q5 合格）；App 真实图表仍由 HealthKit/SwiftData 驱动，本套演示序列仅供原型预览，二者不互通。

## 9. 受影响文件（本次新增/修改）

- 新增：`prototype/assets/{ill/**,art/**,manifest.json,spec/03-*.md}`、24 个 SwiftUI imageset、`spec/04-assembly-delivery.md`
- 修改（fe-engineer）：`prototype/build.mjs`、`prototype/src/charts.mjs`、`prototype/src/styles/components.css`、`prototype/src/screens/*.html`(14)、`prototype/src/sheets.html`
- 重建产物：`prototype/index.html`、`prototype/prototype.css`、`prototype/prototype.js`、`evidence/verify.html|js`、`lint-report.json`、`build-record.json`、`README.md`、`state-matrix.md`、`page-spec.json`
- 未改：`Healthy/**` Swift 源码、`Healthy.xcodeproj/project.pbxproj`、`assets/data/chart-series.json`(15:25)、`assets/spec/01|02`(权威版)
