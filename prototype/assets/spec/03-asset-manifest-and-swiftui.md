# 03 · 资源清单、manifest 与 SwiftUI 接入（Phase 3）

> 项目：StressWatch 健康 App｜编制：前端工程（fe-artworker）｜阶段：Phase 3｜版本：1.0.0
> 依据：`assets/spec/01-visual-spec.md`（视觉，定稿）、`assets/spec/02-usage-and-data-spec.md`（场景 / 口径，定稿）、`prototype/src/screens/*.html` 现有内联 SVG、`docs/` 53 张截图（唯一视觉依据）、主理人 Phase 3 契约。
> 交付物：`prototype/assets/ill/**`、`prototype/assets/art/**` 共 **24 个裸 SVG**、`prototype/assets/manifest.json`、本文件、`Healthy/Resources/Assets.xcassets/` 下 **24 个 `.imageset`**。
> 边界：不修改 `prototype/build.mjs`、`prototype/src/**`、`prototype/index.html`、`prototype/prototype.css|js`、任何 Swift 源码、`Healthy.xcodeproj/project.pbxproj`；不改动任何截图可见文案、不新增页面 / 功能、不引入依赖或外部资源。

---

## 1. 交付概览

| 项 | 数量 | 说明 |
|---|---|---|
| SVG 资源文件 | 24 | 10 个 `origin: screenshot`（1:1 提取）+ 14 个 `origin: stylized`（风格化补齐） |
| manifest `resources` | 24 | ID 唯一，`path` 全部指向真实文件 |
| manifest `charts` | 14 | 14 类 renderer ID；`seriesIds` 共 50 条，全部为 `chart-series.json#series[].id` 引用，不复制数值 |
| SwiftUI `.imageset` | 24 | `Illustrations/` 12、`ArticleArt/` 9、`EmptyStates/` 3 |
| `--dark` SVG 文件 | 0 | 截图无深色依据，本版不产出（见第 7 节） |

目录树（本成员产出部分）：

```
prototype/assets/
  spec/01-visual-spec.md  02-usage-and-data-spec.md  03-asset-manifest-and-swiftui.md(本文档)
  data/chart-series.json                  # 只读，未改动
  ill/hero/   ill/faq/   ill/habit/   ill/promo/   ill/empty/
  art/hrv/    art/age/
  manifest.json
Healthy/Resources/Assets.xcassets/
  AppIcon.appiconset/                    # 既有，未改动
  Illustrations/  ArticleArt/  EmptyStates/   # 三个分组 + 同名 .imageset
```

---

## 2. 资源总表（24 行）

`alt` 列取自 02 §1 总表第 7 列与 §3.2 逐张 alt（已填实），同时写入 SVG 根标签 `aria-label` 与 manifest `alt`；`变体` 列只记录后缀，不产出额外文件。

| # | ID | 路径 | 尺寸 viewBox | origin | 页面 | alt | 变体 | 复用关系 |
|---|---|---|---|---|---|---|---|---|
| 1 | `ill-hero-pool-relax` | `assets/ill/hero/ill-hero-pool-relax.svg` | `0 0 390 292` | `screenshot` | `today` | 绿色卡通角色戴墨镜在泳池中放松；按截图风格重绘的示意插画，非原始数据截图。来源：截图复刻 | `--tone-white`、`--tone-mint`、`--tone-lavender`、`--tone-peach` | today 首屏常驻；4 档 tone 仅换 L1 渐变终色，角色不变 |
| 2 | `ill-faq-stress-overload` | `assets/ill/faq/ill-faq-stress-overload.svg` | `0 0 160 116` | `screenshot` | `today` | 线描对话气泡与向右箭头组成的几何画；FAQ 示意插画，非原始数据截图。来源：截图复刻 | — | today FAQ 卡 1，点击整卡进入 ai-article |
| 3 | `ill-faq-measure-principle` | `assets/ill/faq/ill-faq-measure-principle.svg` | `0 0 160 116` | `screenshot` | `today` | 手表与弧形刻度组成的线描几何画；FAQ 示意插画，非原始数据截图。来源：截图复刻 | — | today FAQ 卡 2，点击整卡进入 ai-article |
| 4 | `ill-habit-steps` | `assets/ill/habit/ill-habit-steps.svg` | `0 0 60 60` | `screenshot` | `actions` | 绿色进度环与两枚脚印组成的步数插画；习惯卡示意插画，非原始数据截图。来源：截图复刻 | — | actions 习惯「步数」；归零态复用 ring-empty，不新增插画 |
| 5 | `ill-habit-noise` | `assets/ill/habit/ill-habit-noise.svg` | `0 0 60 60` | `screenshot` | `actions` | 喇叭与对勾组成的环境音量插画；习惯卡示意插画，非原始数据截图。来源：截图复刻 | — | actions 习惯「环境音量」；无「异常」变体 |
| 6 | `ill-habit-water` | `assets/ill/habit/ill-habit-water.svg` | `0 0 60 60` | `screenshot` | `actions` | 水滴与水纹组成的喝水插画；习惯卡示意插画，非原始数据截图。来源：截图复刻 | — | actions 习惯「喝水」 |
| 7 | `ill-habit-caffeine` | `assets/ill/habit/ill-habit-caffeine.svg` | `0 0 60 60` | `screenshot` | `actions` | 咖啡杯与杯柄组成的咖啡因插画；习惯卡示意插画，非原始数据截图。来源：截图复刻 | — | actions 习惯「咖啡因」 |
| 8 | `ill-promo-understand-trend` | `assets/ill/promo/ill-promo-understand-trend.svg` | `0 0 118 78` | `screenshot` | `trends` | 橙色与绿色两个人物并排的横幅插画；趋势提示示意插画，非原始数据截图。来源：截图复刻 | — | trends 周视图 promo；关闭后由 .empty-state 承担，不补绘替代插画 |
| 9 | `ill-faq-vo2max-what` | `assets/ill/faq/ill-faq-vo2max-what.svg` | `0 0 160 116` | `screenshot` | `vo2max` | 蜜桃底色上线描心形组成的几何画；FAQ 示意插画，非原始数据截图。来源：截图复刻 | `--peach` | vo2max FAQ 卡 1（--peach） |
| 10 | `ill-faq-vo2max-improve` | `assets/ill/faq/ill-faq-vo2max-improve.svg` | `0 0 160 116` | `screenshot` | `vo2max` | 薄荷底色上线描心形组成的几何画；FAQ 示意插画，非原始数据截图。来源：截图复刻 | `--mint` | vo2max FAQ 卡 2（--mint） |
| 11 | `ill-habit-sun` | `assets/ill/habit/ill-habit-sun.svg` | `0 0 60 60` | `stylized` | `actions` | 太阳与光芒组成的晒太阳插画；按同套风格补齐的示意插画，非截图内容。来源：风格化补齐 | `--tone-mint` | actions 习惯「晒太阳」（--tone-mint）；补齐 ring-empty 空位 |
| 12 | `ill-habit-breath` | `assets/ill/habit/ill-habit-breath.svg` | `0 0 60 60` | `stylized` | `actions` | 莲花与呼吸弧线组成的正念插画；按同套风格补齐的示意插画，非截图内容。来源：风格化补齐 | `--tone-mint` | actions 习惯「呼吸正念」（--tone-mint）；补齐 ring-empty 空位 |
| 13 | `ill-empty-feeling` | `assets/ill/empty/ill-empty-feeling.svg` | `0 0 120 88` | `stylized` | `actions` | 空的气泡与几何线描组成的空状态插画；示意插画，非真实测量数据。来源：风格化补齐 | `--tone-mint`、`--tone-white` | actions 感受记录 / insights 感受趋势（--tone-mint）；record-detail 关联感受（--tone-white） |
| 14 | `ill-empty-range` | `assets/ill/empty/ill-empty-range.svg` | `0 0 120 88` | `stylized` | `trends` | 日历与趋势线组成的线描空状态插画；示意插画，非真实测量数据。来源：风格化补齐 | `--tone-white`、`--tone-mint` | trends 月/年、sleep 周（--tone-white）；vo2max 90日/1年（--tone-mint） |
| 15 | `ill-empty-watch-pending` | `assets/ill/empty/ill-empty-watch-pending.svg` | `0 0 120 88` | `stylized` | `today-detail` | 手表与等待弧线组成的线描空状态插画；示意插画，非真实测量数据。来源：风格化补齐 | — | today-detail「暂无今日静息心率数据」；aria 注明「无数据」 |
| 16 | `art-hrv-cover` | `assets/art/hrv/art-hrv-cover.svg` | `0 0 320 160` | `stylized` | `ai-article` | 心跳 RR 间期序列在时间轴上起伏；知识文章示意插画，非真实测量数据。来源：风格化补齐 | — | 文章1「HRV 分量解释」封面（h1 之后 / sec-sdnn 之前） |
| 17 | `art-age-cover` | `assets/art/age/art-age-cover.svg` | `0 0 320 160` | `stylized` | `ai-article` | 两条并列年龄刻度，一条标实际年龄、一条标生物年龄；知识文章示意插画，非真实测量数据。来源：风格化补齐 | — | 文章2「什么是身体年龄」封面（h1 之后） |
| 18 | `art-hrv-sdnn` | `assets/art/hrv/art-hrv-sdnn.svg` | `0 0 320 180` | `stylized` | `ai-article` | 一组 RR 间期柱分布在均值线两侧；HRV 分量示意插画，非真实测量数据。来源：风格化补齐 | — | 文章1 sec-sdnn |
| 19 | `art-hrv-mean-rr` | `assets/art/hrv/art-hrv-mean-rr.svg` | `0 0 320 180` | `stylized` | `ai-article` | 多个 RR 间期箭头汇入一条平均间期；HRV 分量示意插画，非真实测量数据。来源：风格化补齐 | — | 文章1 sec-meanrr |
| 20 | `art-hrv-pnn50` | `assets/art/hrv/art-hrv-pnn50.svg` | `0 0 320 180` | `stylized` | `ai-article` | 相邻间期差值条与 50ms 阈值线对照；HRV 分量示意插画，非真实测量数据。来源：风格化补齐 | — | 文章1 sec-pnn50 |
| 21 | `art-hrv-mxdmn` | `assets/art/hrv/art-hrv-mxdmn.svg` | `0 0 320 180` | `stylized` | `ai-article` | 差值区间的最大值端与最小值端由标尺相连；HRV 分量示意插画，非真实测量数据。来源：风格化补齐 | — | 文章1 sec-mxdmn |
| 22 | `art-hrv-cv` | `assets/art/hrv/art-hrv-cv.svg` | `0 0 320 180` | `stylized` | `ai-article` | 两条波动程度不同的曲线与「标准差/均值×100」分数式；HRV 分量示意插画，非真实测量数据。来源：风格化补齐 | — | 文章1 sec-cv |
| 23 | `art-age-biological` | `assets/art/age/art-age-biological.svg` | `0 0 320 180` | `stylized` | `ai-article` | 两位同龄人剪影与健康指标对照；身体年龄示意插画，非真实测量数据。来源：风格化补齐 | — | 文章2 生物年龄段落（h1 后首节，无 id） |
| 24 | `art-age-aging-rate` | `assets/art/age/art-age-aging-rate.svg` | `0 0 320 180` | `stylized` | `ai-article` | 长期生物年龄曲线上的近两周短窗放大与趋势箭头；身体年龄示意插画，非真实测量数据。来源：风格化补齐 | — | 文章2 衰老速度章节；必须插在截断占位段落之前，占位段落原样保留 |

> 计数口径：24 = 10 复刻 + 14 补齐**基础 ID**；`--tone-mint` / `--tone-white` / `--peach` / `--mint` 是同一 ID 的变体后缀，写进 manifest `variants`，不另计资源、不生成额外 SVG（01 §7 / 02 §1 计数口径）。

---

## 3. 与主理人契约相关的尺寸 / 字段裁定

| 冲突点 | 02 §1 表格写法 | 定稿依据 | 本版采用 |
|---|---|---|---|
| 文章题图 `art-hrv-cover` / `art-age-cover` | `320×180` | 01 §2.1 题图 2:1 `0 0 320 160`；主理人裁定「02 §1 表格 320×180 是笔误」 | **`0 0 320 160`** |
| 章节示意图 7 张 `art-hrv-*` / `art-age-biological` / `art-age-aging-rate` | `320×160` | 01 §2.1 章节示意图 16:9 `0 0 320 180`；主理人裁定「统一 320×180」 | **`0 0 320 180`** |
| 空状态 3 张 `ill-empty-*` | `160×116` | 01 §2.1 空状态 120:88 `0 0 120 88`、§3.4 渲染 96×70；主理人任务书写明 120×88 | **`0 0 120 88`** |
| `art-age-cover` 的「需 --dark 变体」列 | 标「是」 | 主理人 Q5 裁定：原型 HTML 侧不启用深色，24 个资源 `dark` 一律 `false` | **`dark: false`**（全部 24 个） |
| 逐资源 palette | 02 §1 部分行给出 `--lav` / `--purple` / `--sky` 等 | 01 §4.2 A 表 + 分篇色板（hrv＝绿 / 薄荷系、age＝蜜桃 / 橙系），主理人「只用 01 §4.2 的 A 表色值、禁止第三套色系」 | **以 01 §4.2 为准**，manifest `palette` 记录实际使用的 A 表 HEX |

> 空状态尺寸补充说明：02 §2.4 / §7.2 提到的「160×116 线描几何画」与 01 §2.1 的 120×88 冲突；本版按 01 尺寸矩阵与主理人任务书取 `0 0 120 88`，实际渲染 96×70，替换现有 30px 图标位，**空态文字、位置、字号、颜色一律不动**（01 §3.4）。

---

## 4. `manifest.json` 字段说明

结构固定为 `{ "version", "resources": [...], "charts": [...] }`，字段名不可改（构建器按此读取）。

| 字段 | 类型 | 说明 |
|---|---|---|
| `version` | string | `1.0.0` |
| `resources[].id` | string | 稳定 kebab-case ID，与 01 §6.1/§7 一致，24 条唯一 |
| `resources[].kind` | `ill` \| `art` | 资源类别（按主理人契约，未采用 02 §2.2 的 `illustration/article/empty/chart` 枚举） |
| `resources[].path` | string | 相对 `prototype/assets/` 的真实文件路径 |
| `resources[].origin` | `screenshot` \| `stylized` | 语义值；DOM `data-origin` 字面值与之**相同**（02 §1 的 `replica` 已映射为 `screenshot`）。`screenshot` 10 条、`stylized` 14 条 |
| `resources[].viewBox` | string | `0 0 W H`，与 SVG 根标签逐字一致 |
| `resources[].page` | string | 页面 / 文章定位：`today` / `actions` / `trends` / `vo2max` / `today-detail` / `ai-article` |
| `resources[].scenario` | string | 一句话使用场景（02 §1 第 5 列） |
| `resources[].alt` | string | 填实后的 alt / aria 文案（02 §1 第 7 列、§3.2），**同时写入 SVG 根 `aria-label`**；不写进 `<text>` |
| `resources[].caption` | string | 图注；9 篇文章资源填 02 §3.2 的 ≤30 字图注，其余为空串（`""`）。FAQ 图注由 DOM `.faq-caption` 承担，故留空以免重复 |
| `resources[].sourceNote` | string | 来源 / 标注角标文案；9 篇文章资源填 02 §3.2 的**底部 24px 标注带**全文（如 `HRV 分量 · 单位 ms · 示意图，非真实测量数据`），其余按 02 §1 第 8 列取角标文案，无则 `""`。**全部落 DOM，不进 SVG** |
| `resources[].palette` | string[] | 该资源实际使用的 HEX；10 个复刻资源为 01 §4.2 B 表遗留色（只读锁定），14 个补齐资源只用 A 表 |
| `resources[].variants` | string[] | 变体后缀数组，**不生成额外 SVG 文件** |
| `resources[].dark` | boolean | 原型 HTML 侧是否需要 `--dark`，Q5 裁定 24 个全部 `false` |
| `resources[].swiftuiDark` | boolean | **全部 24 个为 `true`**：SwiftUI 侧需要 Any + Dark 两套的规划位（预留标记，不代表已有文件） |
| `resources[].swiftui` | string | xcassets 中同名 imageset 的相对路径，如 `Illustrations/ill-hero-pool-relax.imageset` |
| `charts[].id` / `.kind` | string | 14 类 renderer ID 与 renderer 名，一一对应 `charts.mjs` RENDERERS |
| `charts[].seriesIds` | string[] | 按 `chart-series.json#series[].chartKind` 聚合的序列 ID 引用，**只存 ID，不复制任何 `points` / 数值 / 颜色副本** |

`charts` 聚合明细（50 条引用，与 `chart-series.json` 的 50 条 `series` 一一对应且不重复）：

| chart ID | kind | 序列数 | seriesIds |
|---|---|---|---|
| `chart-line` | `line` | 11 | `today-hrv-line`、`today-detail-hrv-line`、`day-hrv-line`、`trends-week-hrv-line`、`trends-week-rhr-line`、`sleep-vitals-hrv-line`、`sleep-vitals-hr-line`、`sleep-vitals-resp-line`、`sleep-vitals-spo2-line`、`sleep-vitals-wrist-line`、`vo2max-line` |
| `chart-area` | `area` | 2 | `body-age-week-area`、`body-age-aging-rate-area` |
| `chart-bars` | `bars` | 8 | `trends-week-stress-bars`、`insights-action-vs-stress-bars`、`sleep-month-duration-bars`、`sleep-month-quality-bars`、`sleep-month-regularity-bars`、`sleep-month-continuity-bars`、`sleep-month-efficiency-bars`、`sleep-month-hr-dip-bars` |
| `chart-hist` | `hist` | 2 | `today-stress-hist`、`day-hrv-hist` |
| `chart-step` | `step` | 1 | `sleep-day-stage-step` |
| `chart-dots` | `dots` | 1 | `trends-week-stress-dots` |
| `chart-ring` | `ring` | 1 | `sleep-day-ring` |
| `chart-disc` | `disc` | 1 | `body-age-disc` |
| `chart-stack` | `stack` | 3 | `sleep-day-recovery-stack`、`sleep-month-late-bedtime-stack`、`sheet-sleep80-stack` |
| `chart-capsule` | `capsule` | 1 | `trends-week-stress-capsule` |
| `chart-spark` | `spark` | 6 | `today-hrv-spark`、`today-rhr-spark`、`health-vo2-spark`、`health-hrv-baseline-spark`、`health-rhr-baseline-spark`、`health-weight-spark` |
| `chart-wave` | `wave` | 2 | `today-detail-rhr-wave`、`sleep-day-hr-wave` |
| `chart-dualbars` | `dualbars` | 1 | `sleep-month-recovery-dualbars` |
| `chart-mini` | `mini` | 10 | `today-vital-mini-hrv`、`today-vital-mini-hr`、`today-vital-mini-resp`、`today-vital-mini-spo2`、`today-vital-mini-wrist`、`sleep-day-vital-mini-hrv`、`sleep-day-vital-mini-hr`、`sleep-day-vital-mini-resp`、`sleep-day-vital-mini-spo2`、`sleep-day-vital-mini-wrist` |

> 02 §2.2 / §6-1 所列 `source` / `units` / `range` / `dataset` / `trigger` 等字段未写进本 manifest：主理人契约把字段固定为上表，且这些口径字段属于 50 条**图表序列**（由 `chart-series.json` 承载、构建期按 `seriesIds` 注入 `data-*`），不属于 24 个 SVG 资源。若构建器需要，可从 `chart-series.json` 按 ID 直接读取，不在 manifest 复制。

---

## 5. 构建器接入约定（`data-art` 占位如何内联）

1. **占位形式**（由构建器 / HTML 侧写入，本成员不改 HTML）：
   - 插画：`<div class="hero-art" data-art="ill-hero-pool-relax"></div>`、`<div class="faq-art green" data-art="ill-faq-stress-overload"></div>`、`<div class="habit-art" data-art="ill-habit-steps"></div>`、`<div class="promo-art" data-art="ill-promo-understand-trend"></div>` 等；
   - 文章配图：`<figure class="article-figure" data-art="art-hrv-sdnn">…</figure>`。
2. **内联方式**：按 `resources[].id` 找到 `resources[].path`，读取文件内容**整体替换占位元素的 `innerHTML`**（即插入裸 `<svg>…</svg>`），**不要包 `<img src>`、不要 `fetch`、不要 `<object>`**；保持 file:// 可打开。
   - 24 个文件均是可直接插入 DOM 的裸 SVG：根标签为 `<svg …>…</svg>`，无 XML 声明 / DOCTYPE、无 `<script>` / `<image>` / `<foreignObject>` / 外部 `<use href>` / `@font-face` / 外部字体 / CDN，无 `<text>` / `<title>`；全部带 `xmlns`、`role="img"`、`aria-label`。
   - SVG 内**不得出现标题、单位、口径、来源文字**；图注（`caption`）、来源角标（`sourceNote`）、24px 标注带、图例、空态文字全部由 DOM（`.faq-caption` / `.figure-note` / `.source-note` / `.empty-state`）承担。
   - `aria-label` 与 `alt` 已落在 SVG 根标签；若外层容器原本也带 `role="img" aria-label`（今日 hero 的 `.hero-art` 即如此），内联后应去掉外层的 `role` / `aria-label`，避免读屏重复播报同一资源。
3. **origin → data-origin**：`manifest.origin` 已是 DOM 字面值（`screenshot` / `stylized`），构建器直接写成 `data-origin`，无需再做 `replica → screenshot` 转换；01 §6.4 / 02 §1 要求的来源可追溯性由该属性 + `source-hashes.txt`（Phase 4）保证。
4. **变体**：`variants` 只是元数据，构建期**不得**拼出 `ill-empty-feeling--tone-mint.svg` 之类的路径去读文件；24 个基础 ID 就是 24 个文件。tone / peach / mint 差异由容器 class 或 CSS 变量承担，不换 SVG。
5. **hero 特例**：`ill-hero-pool-relax.svg` 根标签带 `preserveAspectRatio="xMidYMid slice"`（01 §3.1，覆盖 320 / 375 / 390 / 430pt 四种视口，安全区 `x 40–350 / y 16–276`）；其余 23 个保持默认 `xMidYMid meet`。构建器不要覆盖或剥离该属性。
6. **图表不落文件**：`charts` 的 14 个 ID 只有元数据，仍由 `charts.mjs` 构建期展开 `<div class="chart" data-chart="…">`；构建器按 `seriesIds` 从 `assets/data/chart-series.json` 取数值注入 `data-*`（02 §6-3），与本次 SVG 资源互不干扰。
7. **ID 唯一性**：同页仅一份的 `<defs>` id（hero 的 `sw-sky`、两张题图的 `art-hrv-cover-bg` / `art-age-cover-bg`）已做全局唯一命名，单页 / 双文章体共存时不会冲突；若构建器把两篇文章体同时放进 DOM，仍只有一份同名 defs。

---

## 6. SwiftUI 侧同名资源接入映射

### 6.1 分组与命名

| 分组 | 资源 | 数量 | imageset 命名规则 |
|---|---|---|---|
| `Illustrations/` | `ill-hero-*` / `ill-faq-*` / `ill-habit-*` / `ill-promo-*` | 12 | 与 prototype ID 同名（去 `.svg`），如 `Illustrations/ill-hero-pool-relax.imageset` |
| `ArticleArt/` | 9 个 `art-*` | 9 | `ArticleArt/art-hrv-sdnn.imageset` |
| `EmptyStates/` | 3 个 `ill-empty-*` | 3 | `EmptyStates/ill-empty-feeling.imageset` |

每个 `.imageset/` 内含：`Contents.json` + 同名 `.svg`（内容与 `prototype/assets/` 下对应文件**逐字节一致**，便于双端比对）。三个分组目录各有一份分组级 `Contents.json`（`{"info":{"author":"xcode","version":1}}`），不开启 `provides-namespace`，因此 SwiftUI 侧直接用 `Image("ill-hero-pool-relax")` 即可，无需 `Illustrations/` 前缀。

### 6.2 `Contents.json` 模板

```json
{
  "images": [
    { "filename": "<资源 ID>.svg", "idiom": "universal", "scale": "1x" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "original"
  }
}
```

- `template-rendering-intent: original`：保留插画自身配色，不被 tint 成单色模板。
- `preserves-vector-representation: true`：SVG 矢量保留，任意分辨率不失真。
- 只有 **1x / universal / Any** 一份，没有 2x/3x、没有 `appearances` 条目 —— 即当前只落 Any 一套（见第 7 节）。

### 6.3 工程文件

`Scripts/gen_xcodeproj.py` 把 `Assets.xcassets` 整体作为 `folder.assetcatalog` 资源扫描（`RESOURCE_SUFFIXES = (".xcassets",)`），新增分组 / imageset 属于目录内变更，**不需要改 `Healthy.xcodeproj/project.pbxproj`**；本次也未改动任何 `.swift` 文件。

### 6.4 Any / Dark 规划位

manifest 中全部 24 个资源带 `swiftuiDark: true`，表示 SwiftUI 侧需为同名资源规划 **Any + Dark 两套**：将来在对应 `Contents.json` 增加一条 `appearances: [{"appearance":"luminosity","value":"dark"}]` 的 image 条目并放入 `--dark.svg`。适配规则仅作预留、本版不执行（01 §3.6 / 02 Q5）：L1 背景层透明交给 `Color(.secondarySystemGroupedBackground)`，L2 中景不透明度 0.35–0.60，L3 主体仍取现有色板，L4 白色点缀改为 `--surface` 且面积 ≤3%，文字层用系统 `primary` / `secondary` 反相，**不得新造深色专用色值**。

---

## 7. 深色模式：本版未产出 `--dark` 文件

- 53 张截图**无深色依据**，按 01 §1.3 P1「截图为界」与主理人 Q5 裁定：**原型 HTML 侧不启用深色、不产出任何 `--dark` SVG、不新增深色视觉值**，24 个资源总数不变，`resources[].dark` 全部为 `false`。
- 02 §1 表格 `art-age-cover` 行「需 --dark 变体：是（若 01 §8 --dark 变体启用…当前默认不启用）」按同一裁定统一取 `false`；01 视觉验收第 8 条「深色模式资源有 --dark 变体」在本版解释为**SwiftUI 侧槽位预留**（`swiftuiDark: true`），而非原型文件。
- `assets/` 与 `Assets.xcassets/` 下均不存在文件名含 `--dark` 的文件；`Contents.json` 也无 `appearances` 条目。
- 若后续启用深色，按 01 §6.1/§6.2 命名 `<ID>--dark.svg`，并同步在 manifest 增加 `dark: true`、在 imageset 增加 Dark 条目；本版不预建空文件。

---

## 8. 14 张 `stylized` 资源的造型与语义取舍

造型语言统一：几何化圆 / 椭圆 / 圆角矩形 / 圆弧 / 折线段，圆角 ≥6px，`stroke-linecap` / `stroke-linejoin` 全为 `round`，扁平主体 100% 不透明（禁止主体渐变填充），无硬描边、无投影、无 `<text>`；只用 01 §4.2 **A 表** HEX；L1+L2 / L3 / L4 按 60/30/10 分配；引导线 `#E4E7E9` 1px `dash 3 4`、端点 round、**无箭头**。

| 资源 | 语义取舍（逐张照抄 02 §3.2 / §1，未换主题） |
|---|---|
| `ill-habit-sun` / `ill-habit-breath` | 保留「灰环 `#F0F1F3` + 环内几何小图」双层结构；sun 用 `--orange` + `--green-soft` 底，breath 用 `--sky` + `--purple-soft` 底；补的是 `actions.html` 两个 `ring-empty` 空位，不新增变体文件 |
| `ill-empty-feeling` / `ill-empty-range` / `ill-empty-watch-pending` | 120×88 线描几何画；主体居中、≤60% 画幅宽、四周 ≥10px、L1 透明、L4 ≤3 个点缀（各 1 个状态色点）；不替换标题处 `icon-ghost`、不改写任何空态文案 |
| `art-hrv-cover` | RR 间期柱（高低起伏）+ 时间轴 + sky 折线；L1 `#E7F5EC→#F8FAF9` 垂直两停渐变；主体偏右 `x150–296`，左侧 ≥30% 留白，图内无文字 |
| `art-age-cover` | 两条并列刻度轨（橙 / 紫进度长度不同）+ 端点圆点 + 虚线对照；L1 `#FFF2EC→#F8FAF9`；「实际年龄 / 生物年龄」标签由图注 DOM 承担，不写进 SVG |
| `art-hrv-sdnn` | 7 根 RR 间期柱分布在 sky 均值线两侧 + 离散标尺；虚线引导线为柱顶到均值线 |
| `art-hrv-mean-rr` | 02 §3.2 写「多个 RR 间期**箭头**汇入」，但 01 §3.3 明确「箭头禁止」：改为 4 条**无箭头虚线汇聚线** + 1 条平均间期长条，语义「汇入」不变、造型合规 |
| `art-hrv-pnn50` | 6 根差值条 + 一条 50ms sky 阈值线；超阈值条用 `--green-deep` 区分并加白色端点 |
| `art-hrv-mxdmn` | 最大值端 / 最小值端两根柱 + 虚线 L 形标尺 + sky 差值竖线，表达「最大值 − 最小值」 |
| `art-hrv-cv` | 两条波动程度不同的折线 + 纯图形化「分数式」（上下圆点 + round 端帽横线），**不含任何文字**；虚线为两条均值参考线 |
| `art-age-biological` | 两位同龄人几何剪影（橙 / 紫）+ 4 条健康指标条 + 中央虚线对照；剪影只用圆 + 圆角矩形，无写实细节 |
| `art-age-aging-rate` | 长期橙色曲线 + 圆角短窗放大 + 窗内玫红上升折线（**无箭头**，用 round 端帽与端点白点表达趋势）；虚线标注近两周短窗；必须插在截断占位段落之前 |

- **章节图底部 24px 标注带不画在 SVG 内**：7 张 320×180 章节图的主体最高只到 `y≈148`，`y 156–180` 全部留空，由 HTML `.figure-note` DOM 承担（文案见 `sourceNote` 字段 / 02 §3.2）。
- **复用关系不新增文件**：`ill-empty-feeling` / `ill-empty-range` 的 tone 差异、`ill-faq-vo2max-*` 的 peach / mint 差异、`ill-habit-sun` / `ill-habit-breath` 的 tone 差异，全部只记录在 `variants`，由容器 class / CSS 变量体现。
- **文章配图不参与数据**：9 张 `art-*` 是插画，不写入 `chart-series.json`，`charts` 数组也不含它们。

---

## 9. 验收自检（Phase 4 可直接复用）

用 XML 解析 + 字符串校验对 24 个 SVG、manifest、24 个 imageset 做了全量检查，结果 **0 错误**：

| 检查项 | 结果 |
|---|---|
| `manifest.json` 合法 JSON；`resources` 恰好 24 条、ID 唯一 | 通过 |
| 24 个 `path` 全部指向真实存在文件 | 通过 |
| 每个 SVG 可被 XML 解析、根标签为 `{http://www.w3.org/2000/svg}svg` | 通过 |
| 根标签带 `xmlns` / `role="img"` / `aria-label`，且 `aria-label === resources[].alt` | 通过 |
| `viewBox` 与 manifest 逐字一致；hero 带 `xMidYMid slice`、其余不带 `preserveAspectRatio` | 通过 |
| 无 XML 声明 / DOCTYPE / `<script>` / `<image>` / `<foreignObject>` / `<text>` / `<title>` / `<use>` / `@font-face` / 外部 URL / CDN；`url()` 仅内部 `#id` 引用 | 通过 |
| 色值只在 01 §4.2 A / B 两表内（`#fff` 为既有内联稿的 `#FFFFFF` 简写，1:1 保留） | 通过 |
| 10 个 `screenshot` 的 `<defs>`、渐变、全部 path / 色值 / 构图锚点与 `src/screens/*.html` 内联稿逐项一致（仅新增 a11y 根属性；hero 另加 `preserveAspectRatio`） | 通过 |
| `dark === false` 且 `swiftuiDark === true`（24/24）；无任何 `--dark` 文件 | 通过 |
| `charts` 14 条、50 个 `seriesIds` 与 `chart-series.json` 一一对应、无数值副本 | 通过 |
| 24 个 `.imageset` 的 `Contents.json` 为 1x universal Any、`template-rendering-intent: original`、`preserves-vector-representation: true`，且 SVG 与原型侧逐字节一致 | 通过 |
| Chrome headless 渲染 24 张 SVG 目视检查：无空白、无未闭合、无主体溢出 | 通过 |

> 未改动文件复核：`prototype/build.mjs`、`prototype/src/**`、`prototype/index.html`、`prototype/prototype.css`、`prototype/prototype.js`、任何 `.swift`、`Healthy.xcodeproj/project.pbxproj`、`prototype/assets/data/chart-series.json`、`assets/spec/01-visual-spec.md`、`assets/spec/02-usage-and-data-spec.md` 均保持原样。
