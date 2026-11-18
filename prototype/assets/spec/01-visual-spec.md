# 01 · 视觉资源规范（Phase 1）

> 项目：StressWatch 健康 App｜编制：视觉设计架构师（visual-architect）｜阶段：Phase 1
> 依据：`docs/` 下 53 张 603×1306 截图（唯一视觉依据）、`prototype/src/styles/base.css`、`prototype/src/styles/components.css`、`prototype/src/charts.mjs`、`Healthy/Support/AppTheme.swift`
> 适用范围：`prototype/`（HTML 高保真原型）与 `Healthy/`（SwiftUI iOS 18+ / Swift 6）双端的插画、文章配图、空状态、图表与标注资源
> 边界：只定视觉方向/规范，不做体验流程分析、不定义数据口径、不写实现代码；不新增页面/功能，不改动截图可见文案，不引入外部字体、位图、图片 CDN。所有资源须为可内联 SVG 或纯数据。

**标记约定**：`【V·复刻】` = 截图可见、现有原型已有稿，按 1:1 资源化提取（现有稿本身是「按原图风格重绘的 SVG 占位」，见 `prototype/README.md` 第 103 行，属既有事实，本阶段不重画）；`【S·补齐】` = 截图缺失，按本规范风格化补齐。两者都必须在资源清单/manifest 中标注 `origin: screenshot | stylized`。

---

## 1. 总体美学方向

### 1.1 一致性边界（与 53 张截图的关系）

53 张截图**可见且必须 1:1 保持**的是：15 个页面的结构与卡片排布、`base.css :root` 全部色值与四档状态语义、卡片 22px 圆角与 `0 6px 22px rgba(38,50,44,.045)` 阴影、27/17/32/25/13.5/12.5/11.5 字阶、四档模块底色（`toneWhite/Mint/Lavender/Peach`）、今日页 390×292 顶部绿色角色插画的构图锚点、FAQ 卡 160×116 线描几何画的三种底色、行动页 6 张 60×60 习惯插画中的 4 张、趋势页 118×78 双人物横幅、以及 14 类图表 renderer 的图形语法（虚线网格 3 4、1.6px 折线、2px 白描边圆点、8.5px 轴标签）。**属于风格化补齐、截图没有依据**的是：hero 与 FAQ 的 SVG 重绘稿本身（`prototype/README.md` 明确声明「不是原截图」）、「晒太阳/呼吸正念」两张灰色空环、两篇文章的全部题图与内文示意图（当前完全没有配图）、所有空状态插画（当前只有 30px 图标 + 文字）、以及图表里由 `data-seed` 伪随机生成的连续数据点/单位/坐标含义/口径说明（数据本身由 Phase 2 体验成员定义，本阶段只定视觉）。因此本规范的立场是：**可见部分锁死数值不重画，缺失部分用同一套造型语言补齐并在 manifest 里显式标注来源，任何补齐都不得反向改写截图可见文案或新增功能**。

### 1.2 插画 / 图表共用的造型语言

一套语言，不分插画与图表：**几何化**（主体只由圆、椭圆、圆角矩形、圆弧、折线段构成，转角一律 ≥6px 圆角或 `stroke-linecap/linejoin="round"`，禁止尖角、斜切、贝塞尔尖端、手绘笔触）、**圆润**（所有外轮廓端点 round，卡片/容器 14–22px 圆角，柱顶 `rx=min(bw/2,5)`）、**扁平**（主体色块 100% 不透明，靠色阶区分层次而非描边/投影；主体禁止渐变填充）、**柔和渐变**（仅允许两类：插画背景层垂直两停渐变、图表面积图/迷你图垂直单色透明度渐变）、**无硬描边**（不给填充形叠加深色/黑色轮廓；FAQ 类「线描主体」允许 6–8px 同色系粗线，但那是主体本身不是描边；允许 1 处 ≤8% 画幅的深色点睛，如既有 hero 墨镜 `#202A26`）。图表沿用同一套 round 端帽、白描边圆点、虚线节奏，视觉上应与插画出自同一支笔，而不是「插画很软、图表很硬」。

### 1.3 设计原则（5 条，含具体数值）

| # | 原则 | 可执行约束 |
|---|---|---|
| P1 | 截图为界、补齐有据 | 每个资源必须有 `origin` 标记；`【V·复刻】` 资源不得改变 viewBox、色值、构图锚点；`【S·补齐】` 资源不得改变任何截图可见文案或新增页面 |
| P2 | 四档状态色是唯一语义色 | 绿 `#79C98E` / 紫 `#8D90E4` / 橙 `#F79B62` / 粉 `#EE6E88` 四档固定；`purple #6C5AD9`（睡眠）、`red #F0677E`（心率波形）、`teal #7BD3C4` / `sky #57BFE6`（数据系列）不得承载状态语义；禁止第五档状态色 |
| P3 | 白卡片 + 浅模块底 + 插画自带底色 | 卡片 `#FFFFFF` / 22px / padding 20 / margin 20 / 无描边 / 唯一阴影 `0 6px 22px rgba(38,50,44,.045)`；插画容器 16px；插画内部禁止 `filter`/`drop-shadow`/内阴影；禁止「色块上再叠色块」（容器已给底色时 SVG 背景层设 `fill="none"`） |
| P4 | 图表先可读再好看 | 网格 `#E4E7E9` 1px dash `3 4`；轴标签 8.5px `#9BA1A7`；折线 1.6px；数据点 r≤4.6 + 2px `#FFFFFF` 描边；绘图区 `x 8–312`；标题/单位/口径/来源一律放 DOM，不写进 SVG |
| P5 | 一致性优先于丰富度 | 同一资源类共用同一 viewBox / 线宽 / 端帽 / 留白；变体只换色调后缀，不改造型；单屏状态色面积 ≤10%，不得同时用 ≥2 种状态色做大填充 |

### 1.4 明确禁止的视觉手法

1. 写实/拟物/照片/位图/纹理/噪点/玻璃拟态/3D/等距投影/手绘笔触/毛玻璃叠加在插画上。
2. 硬黑或深灰 1–2px 轮廓描边、内阴影、发光、多重投影、霓虹/多色/径向/斜向渐变（插画背景只允许垂直两停；面积图只允许垂直单色透明度渐变）。
3. emoji、系统图标拼贴当作插画、文字入画（图表内除轴刻度与 disc 中心数值外禁止任何文字）、水印、署名、`<image>` / `<foreignObject>` / 外部 `<use href>` / `@font-face` / CDN 引用 / `<script>`。
4. 另造色系：不得引入 1.5 节 A 表与 4.2 节 B 表之外的任何 HEX；不得新增外部字体、可变字重动画、全大写英文标题。
5. 用伪随机点/柱冒充真实测量序列并标注为真实数据；用红色问号或纯留白表示缺失值；把单位、坐标含义、口径写进 SVG。
6. 新增页面/功能/状态档位；改动截图可见文案、数值格式与状态语义；给现有 `.empty-state` 文字换措辞。
7. 同一资源类出现两种造型语言；线宽/圆角/阴影超出第 5 节数值；把 8.5px 轴标签当成承载口径的文字。

### 1.5 色板（HEX + CSS 变量）与 HSL 推导

**唯一色源，原样复用，不得另造**。以下为 `base.css :root` 与 `AppTheme.swift` 已对齐的变量：

```css
:root {
  --ink:#292C30; --ink-2:#5C6268; --ink-3:#969CA2; --ink-4:#B7BCC1;
  --surface:#FFFFFF; --line:#ECEEF0; --line-2:#F3F5F5;
  --green:#79C98E; --green-deep:#4EA974; --green-soft:#E7F5EC;
  --lav:#8D90E4; --purple:#6C5AD9; --purple-soft:#EDE8FC;
  --orange:#F79B62; --pink:#EE6E88; --teal:#7BD3C4; --sky:#57BFE6; --red:#F0677E;
  --gray:#C9CDD2; --gray-line:#E4E7E9; --faint:#F0F1F3;
  --tone-white:#F8FAF9; --tone-mint:#EAF6EF; --tone-lavender:#EFEAFC; --tone-peach:#FFF2EC;
  --radius:22px; --radius-sm:14px;
  --shadow:0 6px 22px rgba(38,50,44,.045);
  --font:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Helvetica Neue","Microsoft YaHei",sans-serif;
  --font-num:-apple-system,BlinkMacSystemFont,"SF Pro Display","PingFang SC",sans-serif;
}
```

HSL 推导（用于判断同色系明度阶梯，非新增色）：

| 变量 | HEX | HSL | 相对 `#FFFFFF` 对比度 |
|---|---|---|---|
| `--ink` | `#292C30` | H214 S08% L17% | 14.03:1 |
| `--ink-2` | `#5C6268` | H210 S06% L38% | 6.17:1 |
| `--ink-3` | `#969CA2` | H210 S06% L61% | 2.77:1 |
| `--green` | `#79C98E` | H136 S43% L63% | 1.99:1 |
| `--green-deep` | `#4EA974` | H145 S37% L48% | 2.90:1 |
| `--lav` | `#8D90E4` | H238 S62% L72% | 2.90:1 |
| `--purple` | `#6C5AD9` | H249 S63% L60% | 5.12:1 |
| `--orange` | `#F79B62` | H023 S90% L68% | 2.14:1 |
| `--pink` | `#EE6E88` | H348 S79% L68% | 2.91:1 |
| `--teal` | `#7BD3C4` | H170 S50% L65% | 1.76:1 |
| `--sky` | `#57BFE6` | H196 S74% L62% | 2.10:1 |
| `--red` | `#F0677E` | H350 S82% L67% | 3.02:1 |
| `--tone-mint` | `#EAF6EF` | H145 S40% L94% | — |
| `--tone-lavender` | `#EFEAFC` | H257 S75% L95% | — |
| `--tone-peach` | `#FFF2EC` | H019 S100% L96% | — |

**关键推论**：四档状态色原色在白底上均 <3:1（1.99 / 2.90 / 2.14 / 2.91），因此**只能用于 ≥3px 粗的图形、直径 ≥9px 的圆点、或面积填充，禁止直接作为文字色**；`--purple` 5.12:1 与 `--ink-2` 6.17:1 是唯二可作强调正文的彩色/中性色。

**色值消歧（Phase 3 仅需改名，色值一律不动）**：`charts.mjs` 的 `C.greenDark #4FA976` 与 `--green-deep #4EA974` 为近似重复，`C.purpleSoft #A9A4F0` 与 `--purple-soft #EDE8FC` 同名不同值，`C.ink #2C2F33` 与 `--ink #292C30` 不一致 —— 三者统一以 `base.css` 为准，图表中两个局部色改称 `--chart-line-green` / `--chart-baseline-lav` 以消除歧义，禁止借机改色。

**图表专用中性 token（全部来自既有色值，不构成新色系）**：`--chart-axis #9BA1A7`（8.5px 轴标签）、`--chart-line-gray #C9CDD1`（对比折线，另有既有 `#C7CBD0`）、`--chart-empty-dot #E9EAEE`（点阵空点）、`--chart-track #F0EEFC` / `#F3F1FD`（睡眠双环轨道）、`--chart-band-sleep #EDE8FC`、`--chart-band-hr #FCEDEF`、`--chart-baseline #8C9298`。

### 1.6 字号阶梯（沿用现有，不得扩展）

| 层级 | 字号 / 字重 / 行高 | 字距 | 颜色 | 用途 |
|---|---|---|---|---|
| 页面标题 | 27 / 800 / 1.25 | −0.9px | `--ink` | `.page-head h1` |
| 卡片标题 | 17 / 750 | −0.4px | `--ink` | `.card h2`、`.section-title` |
| 大数值 | 32 / 700 / 1.15 | −1.2px | `--ink`，`.muted` 用 `--ink-3` | `.big-value`（数值用 `--font-num`） |
| 指标值 | 25 / 700 | −0.7px | `--ink` | `.metric-value`（`--font-num`） |
| 正文 | 13.5 / 400 / 1.78 | 0 | `#5A6065` | `.body-copy`；阅读器正文 14 / 2.05 `#414A51` |
| 辅助 | 12.5 / 400 | 0 | `--ink-2` / `--ink-3` | `.small`、`.metric-label`、图例 |
| 最小 | 11.5 / 400 | 0 | `--ink-3` | `.tiny`、`.metric-note`、角标 |
| 微标 | 9.5–11 / 650–800 | 0–0.04em | 视组件 | PRO 9.5px、日历 8.5px、vital small 9.5px |
| 图表轴 | 8.5 / 400 | 0 | `--chart-axis #9BA1A7` | 仅坐标轴刻度 |

字体栈固定 `--font` / `--font-num`，中文 PingFang SC、英文 SF Pro；禁止引入外部字体、全大写标题、字重动画。

---

## 2. 资源分类与尺寸比例矩阵

### 2.1 分类矩阵

| 资源类别 | ID 前缀 | 画面比例 | 设计基准 viewBox | 实际渲染尺寸 | 安全区 / 可裁切区域 | 适用页面 | 多主题变体 |
|---|---|---|---|---|---|---|---|
| Hero 插画 | `ill-hero-` | 390:292 ≈ 4:3（1.336） | `0 0 390 292` | 390×292（容器固定高 292px，宽度自适应 100%） | 安全 `x 40–350 / y 16–276`；可裁左右各 35px、上下各 15px | today | **是**：4 档 tone（渐变终色对齐 `tone*`）；状态变体可选，仅换背景起始色，禁止改角色 |
| FAQ 卡插画 | `ill-faq-` | 160:116 ≈ 1.38 | `0 0 160 116` | 容器 170×116（卡片 350 − gap 10）/2，SVG `meet` 居中，左右各 5px 露底色 | 主体 `x 24–136 / y 20–96`；四周 ≥16px；可裁 ≤8px | today ×2、vo2max ×2 | **是**：`green #DFF1E4` / `peach #FCEDE3` / `mint #E3F3EA` 三套底色 + 对应线色 |
| 习惯插画 | `ill-habit-` | 1:1 | `0 0 60 60` | 54×54（`.habit-art`）；环形外缘 r=27.5 → 直径 55 | 主体活动区 `x/y 4–56`；外缘留 ≥2.5px；不可裁 | actions ×6 | **是**：6 主题各 1 张；空值/有值由同一张图 + 进度环叠加实现，不另画插画 |
| 横幅插画 | `ill-promo-` | 118:78 ≈ 1.51 | `0 0 118 78` | 118×78 固定（`.promo-art`），背景透明由 `.promo` 渐变提供 | 主体 `x 18–100 / y 8–72`；左 12px / 上 8px 可裁，右、下 0 出血 | trends | 否（蜜桃渐变 `#FFF9F4→#FFF2E8` 固定） |
| 文章题图 | `art-<article>-cover` | 2:1 | `0 0 320 160` | 342×171（`.reader` 内容宽 390−48=342px），圆角 16px | 四周 ≥16px；左侧 ≥30% 留白；可裁 ≤16px；图内禁止压文字 | ai-article ×2 | **是**：hrv=绿/薄荷系，age=蜜桃/橙系；原型侧不做 `--dark`（R1/Q5，见 §3.6 与 §9） |
| 文章内文配图 / 章节示意图 | `art-<article>-<section>` | 16:9 | `0 0 320 180` | 342×192，圆角 14px | 四周 ≥12px；底部 24px 为标注带，主体不得入内；不可裁 | ai-article ×7 | 否（逐章节独立，但共用同一线宽/色/标注规范） |
| 状态空态插画 | `ill-empty-` | 120:88 ≈ 1.36 | `0 0 120 88` | 96×70，居中，替换现有 30px 图标位 | 四周 ≥10px；主体 ≤60% 画幅宽 | today-detail、actions、record-detail、trends、vo2max | **是**：3 语义 × 2 档 tone |
| 14 类图表 | `chart-<kind>` | 320 : h（见 2.2） | `0 0 320 h` | 宽 310px（卡片内宽 350−2×20），缩放 310/320=0.969，高 = h×0.969；例外：vital-tile `mini` 固定 34px、`ring` 最大宽 310、`disc` 最大宽 330 | 绘图区 `x 8–312`，顶部 8–20px、底部 16–28px 为标签留白；**禁止裁切**，轴标签不得被 overflow 截断 | 15 页中 12 页，约 50 处构建期展开 | **是**：4 档状态点色 + 睡眠紫 / 身体年龄橙 / VO2 浅紫主题（只换点色与参考线，不换色板） |
| PRO / 状态徽标 | `ui-badge-` | 文本胶囊 | 无 viewBox（DOM 组件） | PRO 9.5px / 状态 11.5px | padding `2px 7px` / `4px 10px` | 全页 | **是**：4 档状态色 + `star` |
| 图例色标 | `ui-legend-` | 14×2px 线段 | 无 viewBox（DOM） | 14×2px | 与文字间距 6px，行间距 12px，最多 3 项 | 图表卡下方 | **是**：实线 / 虚线 / 粉线 / 灰线 4 款 |
| 单位 / 数据来源角标 | `note-unit-` `note-source-` | 纯文本 | 无 viewBox（DOM） | 12.5–14px / 10.5–11px | 单位距数值 2–3px；来源角标距卡片右内边 20px、距图例 ≥8px | 全页 | 否 |

### 2.2 14 类图表 viewBox 明细（`charts.mjs` RENDERERS 一对一）

| chart ID | renderer | viewBox h | 绘图区 top→bottom | 渲染高 @310px | 主要页面 | 关键视觉参数 |
|---|---|---|---|---|---|---|
| `chart-line` | line | 132 | 14→104，x 轴标签 y=122 | 127.9px | today、today-detail、day-hrv、trends、sleep-vitals ×5、vo2max | 折线 1.6px；点 r4.6 + 2px 白描边；网格 4 条 |
| `chart-area` | area | 128 | 16→106，y 轴标签 x=315 | 124.0px | body-age ×2 | 面积渐变 `.34→.02`；线 1.8px；基线 `#8C9298` 1.2px |
| `chart-bars` | bars | 148（实例 150） | 14→h−32，双行标签 +13/+23 | 143.4 / 145.3px | trends、insights、sleep-month ×5 | 柱宽 ≤15、`rx=min(bw/2,5)`；平均线 1.3px |
| `chart-hist` | hist | 132 | 20→104 | 127.9px | today、day-hrv | 74 柱 w2.5；睡眠带 `#EDE8FC` opacity .66 + 顶 2.5px `--purple` |
| `chart-step` | step | 130 | 18→100 | 125.9px | sleep-day | 4 段色：wake 橙 / rem 青 / core 紫 / deep 深紫，opacity .92 |
| `chart-dots` | dots | 116 | 22→100 | 112.4px | trends | 7×24 点 r3.1；空点 `#E9EAEE` |
| `chart-ring` | ring | 220 | cx160 cy108，R78/R54 | 213.1px | sleep-day | 外环 24px `--purple` / 内环 17px `#A9A4F0`；轨道 `#F0EEFC` / `#F3F1FD` |
| `chart-disc` | disc | 250 | cx160 cy122，R96 | 242.2px（330px 宽时 257.8） | body-age | 环 7px；中心 13/39/11px 文字（既有例外） |
| `chart-stack` | stack | 20 | y 2→16 | 19.4px | sleep-day、sleep-month、sheets | 总宽 320、高 14、`rx=7`，底色 `#EDEBFA` |
| `chart-capsule` | capsule | 190 | 14→174 | 184.1px | trends | 宽 34、`rx=17`、x=232，底 `#EFF0F2` |
| `chart-spark` | spark | 34 | 5→27 | 32.9px | today ×2、health ×4 | 无坐标轴；渐变 `.20→0`；线 1.5px；末点 r3.4 |
| `chart-wave` | wave | 118（实例 120） | 12→h−22 | 114.3 / 116.3px | today-detail、sleep-day | `--red` 1.6px；高亮带 `#FCEDEF` opacity .6 |
| `chart-dualbars` | dualbars | 136 | 14→106 | 131.8px | sleep-month | 柱宽 13；a=`--teal`、b=`--purple`；平均线 1.2px |
| `chart-mini` | mini | 62 | 15→48 | 60.1px（vital-tile 固定 34px） | today ×5、sleep-day ×5 | 3 条网格；线 `#C9CCD1` 1.4px；末点 r3.6 + 白描边 |

---

## 3. 构图要点

### 3.0 四层结构与通用留白（所有插画/题图）

| 层 | 内容 | 允许色 | 不透明度 | 规则 |
|---|---|---|---|---|
| L1 背景层 | 整幅矩形 / 垂直两停渐变 | `greenSoft`、`tone*`、`faq*`、`soft` 系列 | 1.0 | 容器已提供底色时改 `fill="none"`，禁止色块叠色块 |
| L2 中景层 | 水面条带、池壁、植物剪影、云 | soft 色 + `#FFFFFF` | 0.55–0.90 | 只能作为「可裁切装饰」，不得承载信息 |
| L3 主体层 | 角色 / 物件 / 图表数据墨迹 | 主色 + 浅一档辅色 | **1.0** | 禁止半透明、禁止投影、禁止描边分隔 |
| L4 装饰层 | 星芒、高光、小圆点 | 第二色 / 白 | 0.60–0.85 | 面积 ≤5%，最多 6 个元素 |

禁止第 5 层；层与层靠明度阶差区分，不靠描边。主体外接框 ≤55% 画幅宽 / ≤65% 画幅高，四周留白 ≥12%（背景层不计入留白但不得包含信息）。

> **适用范围（R1 补充）**：本节四层结构与「L4 最多 6 个元素」只约束**插画与文章配图**（`ill-*` / `art-*`，含全部 `【S·补齐】` 资源）。**14 类既有图表不在此列**：尤其 `chart-disc` 由 `charts.mjs` 生成的 46 个装饰点属 `【V·复刻】` 既有稿，数量与位置一律保留、不得按「≤6 元素」删减或重排；这些点纯装饰、无数据语义（与 R1/Q19 及 `02-usage-and-data-spec.md` §5 disc 行一致）。

### 3.1 Hero 390×292 —— 375px 视口裁切安全区（重点）

现有 `.hero-art{height:292px}`、`svg{width:100%;height:100%}`。SVG 默认 `preserveAspectRatio` 为 `xMidYMid meet`；本规范**统一改为 `xMidYMid slice`（cover）**，让插画铺满容器、由容器渐变兜底，避免 375px 下出现上下 5.6px 的空白带。

| 视口宽 | slice 缩放 | 绘制尺寸 | 裁切量 | 结论 |
|---|---|---|---|---|
| 320pt（SE） | 1.000 | 390×292 | **左右各 35px** | 最坏横向裁切 |
| 375pt | 1.000 | 390×292 | **左右各 7.5px** | 本题指定场景 |
| 390pt（基准） | 1.000 | 390×292 | 0 | 完整显示 |
| 430pt（Pro Max） | 1.103 | 430×322 | **上下各 15px** | 最坏纵向裁切 |

> 若仍用 `meet`：375pt → 缩放 0.9615、绘制 375×280.8、上下各 5.6px 露出容器渐变；320pt → 上下各 26.2px。**不推荐**，如沿用则必须保证容器渐变与 SVG 背景顶色完全一致（`#E7F5EC → #F7F9F7`）。

**统一安全区：`x ∈ [40, 350]`、`y ∈ [16, 276]`**（覆盖 320pt 的 35px 横裁 + 5px 余量、430pt 的 15px 纵裁 + 1px 余量）。现有角色含墨镜与饮品的外接框约 `x 104–290 / y 74–226`，完全落在安全区内，复刻时不得移动。视觉重心在黄金分割偏右 `x≈195–215 / y≈160–190`。

- **可裁切区域**：左右各 35px、上下各 15px，只允许放 L1/L2 装饰层（顶部几何植物剪影 y 0–74、水波条带、右侧小鸭 x 336–384）。
- **状态栏约束**：顶部 0–46px 为状态栏/灵动岛覆盖区，禁止放角色五官、文字或关键识别元素（现有墨镜位于 y≈118–140，合规）。
- **底部融合**：y 276–292 为 L1 渐变向页面底色过渡带，不得放任何主体。
- **tone 适配**：渐变起始色固定 `--green-soft #E7F5EC`（品牌绿），终止色分别取 `--tone-white #F8FAF9` / `--tone-mint #EAF6EF` / `--tone-lavender #EFEAFC` / `--tone-peach #FFF2EC`；角色主体色恒为 `--green #79C98E` 一系，不随 tone 改动。

### 3.2 FAQ / 习惯 / 横幅

- **FAQ（160×116 → 容器 170×116）**：主体居中，线描主体外接框占 60–70% 宽 / 55–65% 高（现有 `x 28–132 / y 18–106` 合规）；四周 ≥16px 纯底色留白；四角 16px 圆角由容器裁切，主体不得进入 x<16 / x>144 / y<12 / y>104。三种底色变体只允许换「底色 + 主体线色」，造型与线宽（8/7/6px）保持一致：`green #DFF1E4` + `#5AA97B`/`#A7DDBC`，`peach #FCEDE3` + `#F0A36E`，`mint #E3F3EA` + `#6FC08C`。禁止给线描加白描边或投影。
- **习惯（60×60 → 54×54）**：视觉重心居中，若带进度环则环心 (30,30)、r=24、stroke=7（外缘 27.5，四边仅余 2.5px）；主体插画占 70–85% 画幅，位于环内 `r≤18` 区域，不得与环重叠；`ring-empty` 的 `#EEF1EF` 灰环仅作未采集态，补齐两张时保留「环 + 内部几何小图」双层结构，与现有 4 张（步数/环境音量/喝水/咖啡因）一致。
- **横幅（118×78）**：两个人物贴右、贴下出血（右 0 / 下 0），左 12px、上 8px 为可裁切区；`close-x` 位于容器右上 (10,9)，插画不得进入右上角 20×20px；背景透明，禁止自带底色矩形（底色由 `.promo` 的 `linear-gradient(100deg,#FFF9F4,#FFF2E8)` 提供）。

### 3.3 文章题图与章节示意图

- **题图（2:1）**：L1 用对应 soft 色垂直渐变；主体居中偏右（`x 150–300`），左侧 ≥30% 留白；四周 ≥16px 安全区被 16px 圆角裁切，主体不得贴边；图内**不放标题、不放章节名、不放数值**（`.reader h1` 在图上方，保持现有排版）。
- **章节示意图（16:9）**：主体居中，四周 ≥12px；底部预留 24px 标注带（用于图例/「示意，非真实测量数据」角标，文案由 Phase 2 给），主体不得入内；一张图只讲一个关系（如「RR 间期序列 → 标准差」），最多 3 个视觉元素 + 1 组引导线；引导线用 `--gray-line #E4E7E9` 1px dash `3 4`，端点 round，箭头禁止。7 张图共用同一线宽、同一标注位置、同一圆角，禁止每张换风格。
- **第 2 篇「什么是身体年龄」截断处的占位段落必须原样保留**，配图不得替代、覆盖或改写该占位文字。

### 3.4 空状态

现有 `.empty-state` 为 `padding 26px 18px` / 居中 / 12.5px `--ink-3` / 30px 图标 `--C6CDCA` / `strong 13.5px #5C6460`。本阶段**只把 30px 图标换成 96×70 的 `ill-empty-*` 插画**，文字内容、位置、字号、颜色全部不动。插画主体居中、占 ≤60% 宽，四周 ≥10px，L1 背景透明（由卡片白底提供），L4 点缀不超过 3 个。禁止用「大插画 + 新文案」把空状态做成引导页。

### 3.5 图表

绘图区严格 `x 8–312`（宽 304，占 viewBox 95%），网格线 `from=8 to=312`，y 轴标签右对齐于 `x=315` 且文字右缘不超过 `x=318`；顶部 8–20px、底部 16–28px 为标签留白，数据墨迹不得入内。所有图表 `vector-effect="non-scaling-stroke"`，`width:100%;height:auto`，**禁止任何裁切**（轴标签被截断视为不合格）。图表内不放标题、单位、口径、来源（`chart-disc` 既有中心文字为唯一例外，见 §5.3 R1/Q19，且**不承担口径载体职责**）；这些由 DOM 的 `.chart-legend`（图下 8px）、`.metric-note`、数据来源角标承载。

### 3.6 浅色模块底色适配 / 深色模式（预留，非本阶段交付物）

- **四档 tone（浅色模块底）**：`toneWhite #F8FAF9`（今日/趋势）、`toneMint #EAF6EF`（行动/洞察/健康/VO2）、`toneLavender #EFEAFC`（睡眠系列）、`tonePeach #FFF2EC`（身体年龄）。插画 L1 背景层改为透明或对齐对应 tone；主体色**恒不变**。在较饱和的 `toneLavender` / `tonePeach` 上，白色主体须加 ≥30% 不透明度的主色描边或与主色块的明度阶差，避免「白形消失」；禁止用纯黑 `#000` 或深灰描边补救。
- **iOS 深色模式（R1/Q5 裁决）**：53 张截图无深色依据，按 P1「截图为界」**原型 HTML 侧不启用深色、不产出任何 `--dark` SVG、不新增深色视觉值**；24 个资源总数不变。SwiftUI 侧由 Phase 3 仅在 `Assets.xcassets` 为同名资源预留 Any / Dark **槽位**（manifest 用 `darkVariant: reserved` 标记），不新增插画文件。槽位内的适配规则仅作预留、本阶段不执行：L1 背景层透明（交给 `Color(.secondarySystemGroupedBackground)`），L2 中景不透明度 0.35–0.60，L3 主体色仍取现有色板，L4 白色点缀改为 `--surface` 且面积 ≤3%，`--ink` / `--ink-3` 文字层改用系统 `primary` / `secondary` 反相，**不得新造深色专用色值**。
- **状态色在 tone 底上的实测对比**（供判断是否需要加深）：`--green` 对 `toneLavender` 1.69:1、`--purple` 对 `toneLavender` 4.35:1、`--orange` 对 `tonePeach` 1.95:1。结论：在浅色 tone 底上状态色只能做 ≥3px 图形/填充，不能做细线或文字；需要文字时用 `--purple`（5.12:1 对白）或 `--ink-2`（6.17:1 对白）。

---

## 4. 配色规则

### 4.1 面积分配（60 / 30 / 10）

| 层级 | 占比 | 内容 |
|---|---|---|
| 中性 | ≥60% | `--surface` 卡片、`tone*` 模块底、`--ink*` 文字、`--line*` 分隔 |
| 辅色 / soft | ≤30% | `greenSoft` / `purpleSoft` / faq 三底色 / 插画 L1+L2 背景与中景 |
| 状态 / 强调 | ≤10% | 四档状态色、`--purple` 睡眠主色、`--red` 心率波形；单屏不得同时出现 ≥2 种状态色作大填充 |

单张插画内部：L1+L2 60–70%、L3 主体 20–30%、L4 点缀 ≤5–8%。单个图表：网格/轨道 ≤15%、数据墨迹 ≤35%、留白 ≥50%。

### 4.2 每类资源允许使用的色值子集

全局只有**两张白名单**，任何资源不得使用第三张表的色值：

- **A 表（统一色板）** = 1.5 节 CSS 变量全部 HEX + 图表专用中性 token + `charts.mjs` 的 `#A9A4F0` / `#4FA976` / `#FFFFFF`。**所有 `【S·补齐】` 新资源只能取 A 表**。
- **B 表（既有内联资源遗留色，只读锁定）** = 现有 `【V·复刻】` 稿里已出现的色值，仅用于这 10 个资源按 1:1 保留，Phase 3 资源化时不得改动：
  - hero：`#E4F4EA #D9F0E9 #CDEBE3 #DDF3E7 #CBE9E6 #E1F3E6 #8FD0A5 #A1DCB2 #F4F8F4 #E7E2F8 #F6F3FC #C9C1F0 #73C493 #6ABB8B #8FD4A7 #202A26 #2B3B31 #F4F8EF #DDEB9C #9FBE6B #8AAF68 #E8864F #4B4A76 #F2D3A0 #5B4A34`，容器渐变 `#E7F5EC→#F7F9F7`
  - FAQ：`#DFF1E4 #FCEDE3 #E3F3EA #5AA97B #A7DDBC #28332C #8ED3A6 #F0A36E #6FC08C`
  - habit：`#E7F4EC #66BE8B #BFE3CC #F8C792 #74C69D #DCEEF4 #C6E3EC #F6E2DA #EEF1EF`
  - promo：`#F8C6A0 #FFF4E5 #79C98E #26302B #7A5540 #F6A96B`，容器 `#FFF9F4→#FFF2E8`
  - 图表既有辅助色：`#9BA1A7 #B9BEC6 #C7CBD0 #C9CCD1 #E9EAEE #F0EEFC #F3F1FD #FDECE0 #8FC9E8 #FBF8F5 #EDEBFA #EFF0F2 #FCEDEF #EEF0F2 #8C9298 #C7C4E8 #7BD3AC`

B 表中的近似色（如 `#73C493` 对 `--green #79C98E`、`#5AA97B` 对 `--green-deep #4EA974`）可在 Phase 3 一次性归并到 A 表明度阶梯（L 偏差 ≤±8%），但不得以「优化」为由改变可见观感；**新增资源禁止再引入这类近似色**。

| 资源类 | 允许色值 |
|---|---|
| hero 新增 tone 变体 | `--green-soft`、`tone*`、`--green`、`--green-deep`、`--lav`、`--purple-soft`、`--surface`、`--ink`（点睛 ≤8%） |
| FAQ 新增变体 | 三底色 + A 表 `--green`/`--green-deep`/`--orange`/`--teal`（线色），B 表线色仅复刻用 |
| 习惯补齐（晒太阳/呼吸正念） | `--orange`/`--sky` 主色，`--green-soft`/`--purple-soft` 底，`--faint` 空环，`--surface` 高光 |
| 文章题图 / 内文图 | hrv 篇：`--green`/`--green-deep`/`--green-soft`/`--sky`；age 篇：`--orange`/`--pink`/`--tone-peach`/`--purple`；共用 `--ink-2` 文字、`--gray-line` 引导线 |
| 空状态 | `--faint`、`--gray`、`--ink-4` 为主，点缀 ≤1 个状态色（≤5% 面积） |
| 图表 | 数据色仅四档状态色 + `--purple`/`--purple-soft`/`--teal`/`--sky`/`--red`；结构色仅 `--gray-line`/`--gray`/`--faint`/`--surface`/图表专用中性 token |
| 徽标 / 图例 / 角标 | 既有组件色（`#E6E5FA #5B5AC0 #FDE9DC #C96C32 #FCE3E8 #C34D66` 等）属 B 表只读；新增文字一律 `--ink-2` |

### 4.3 四档状态色语义（固定，不得扩档）

| 档位 | 主色 / HSL | 语义 | 徽标底 / 文字（既有） | 允许用法 |
|---|---|---|---|---|
| 状态优秀 | `--green #79C98E` H136 S43 L63 | 低压力、达标、恢复良好 | `#E7F5EC` / `#4EA974` | ≥3px 图形、r≥9px 点、填充块 |
| 状态正常 | `--lav #8D90E4` H238 S62 L72 | 基线、平均、正常波动 | `#E6E5FA` / `#5B5AC0` | 同上；也是 bars 平均线默认色 |
| 注意压力 | `--orange #F79B62` H023 S90 L68 | 偏高、需留意、待改善 | `#FDE9DC` / `#C96C32` | 同上；睡眠阶段 wake、睡眠心率柱 |
| 压力过载 | `--pink #EE6E88` H348 S79 L68 | 高风险、异常、需休息 | `#FCE3E8` / `#C34D66` | 同上；严禁与 `--red` 混用 |

`--red #F0677E` 只绑定心率波形本体与「晚睡分布」段，`--purple #6C5AD9` 只绑定睡眠主色/圆盘，`--teal`/`--sky` 只作数据系列色 —— 三者**不是**状态色，禁止出现在状态徽标、状态点、状态条里。

### 4.4 图表的「基线 / 参考线 / 高亮点 / 缺失值」

| 角色 | 色值 | 线宽 / 形态 | 说明 |
|---|---|---|---|
| 网格线 | `--gray-line #E4E7E9` | 1px，`dash 3 4`，`non-scaling-stroke` | 水平 3–4 条；垂直仅 line 图 3 条 |
| 数据主色（基线系列） | `--gray #C9CDD1` / `#C7CBD0` | 1.6px 实线、round | 「近 N 日平均」等对比系列；非状态语义 |
| 平均 / 目标参考线 | `--lav #8D90E4` | 1.3px 实线（bars avg） | 睡眠时长/质量/连续性平均线 |
| 阈值 / 基准参考线 | `#A9A4F0` | 1.4px `dash 2 3`（line baseline） | `chart-line` 的 `data-baseline` 水平参考线（today-detail、vo2max 等）；**视觉侧只定义形态与色值，指标语义一律以 DOM 图例与 02 口径表为准**（R1/Q21，见 §9） |
| 目标线（绿色） | `--green-deep #4EA974` | 1.2px `dash 4 4` | 仅当明确为「目标值」时使用；禁止用 `--red` 作参考线 |
| 面积图基线 | `#8C9298` | 1.2px 实线 | `chart-area` 既有，保留 |
| 高亮点 / 最新点 | 四档状态色填充 + 2px `#FFFFFF` 描边 | r=4.6（普通）/ r=5.5（高亮，可加 1px 同色外圈） | tooltip 热区 34×34px 透明圆，不得盖住相邻点 |
| 缺失值 | `--faint #F0F1F3`（柱高 0）/ `#E9EAEE`（点阵空点） | 保持与真实柱同宽同 rx / 同 r | 必须在 `aria-label` 注明「无数据」；**禁止**留白假装无数据、禁止红色问号、禁止 `—` 混入 SVG |
| 睡眠时段高亮带 | `--purple-soft #EDE8FC` opacity .66 + 顶部 2.5px `--purple` | 矩形 | `chart-hist`；心率异常带 `#FCEDEF` opacity .6 属 `chart-wave` |
| 睡眠阶段 | wake `--orange` / rem `--teal` / core `--lav` / deep `--purple` | opacity .92 | `chart-step` 固定映射，不得改 |

> **§4.4 适用边界（R1/Q21）**：本表「说明」列只描述**视觉角色**（哪条线、什么色、多粗、什么虚线节奏），不定义任何指标名称、数值或口径。数值（如 40 / 30 / 38）与「今日平均 / 近 30 日平均 / 平均值」等语义全部归 Phase 2 的 `02-usage-and-data-spec.md`；若二者有出入，以 DOM 可见图例与 02 口径表为准，**视觉规范不据此改动 SVG 或数值**。

### 4.5 渐变与透明度允许范围

- 允许且仅允许：`linearGradient x1=0 y1=0 x2=0 y2=1` 的**垂直单色透明度渐变**；面积图 `.34→.02`（area）、`.20→.02`（wave）、`.20→0`（spark）；插画 L1 垂直两停色相渐变（hero `#E4F4EA→#D9F0E9` / 容器 `#E7F5EC→#F7F9F7`、promo 容器 `100deg #FFF9F4→#FFF2E8` 为既有例外）。
- 禁止：径向渐变、斜向/多色/霓虹渐变、主体形渐变填充、渐变上再叠渐变。
- 透明度：L1 1.0 / L2 0.55–0.90 / L3 1.0 / L4 0.60–0.85；图表 0.02–0.85（深色模式下 L2 降至 0.35–0.60 属 §3.6 **SwiftUI 侧预留规则**，原型侧不执行）。禁止 <0.02、禁止两层半透明主体叠加、禁止用 opacity 代替色阶做层次。

### 4.6 对比度要求（实测值，不得凭感觉）

| 对象 | 最低对比度 | 允许色 |
|---|---|---|
| 图形 / 粗线（≥3px）/ 填充块 / r≥9px 点 | 3:1（对实际底色） | 四档状态色在白底仅 1.99–2.91:1 → **只能靠「粗」与「面积」成立，禁止做细线** |
| 正文 / 口径 / 单位 / 来源文字 | 4.5:1 | `--ink-2 #5C6268`（6.17:1）、`--ink #292C30`（14.03:1）、`--purple #6C5AD9`（5.12:1） |
| 装饰性轴标签 | 允许 2.61:1 | 8.5px `#9BA1A7`，**仅限坐标轴刻度**；一旦承载单位/口径必须升级为 ≥11.5px `--ink-2` |
| 徽标文字 | 允许既有 2.6–3.0:1 | 维持 `base.css` 既有配色不改；新增承载信息文字用 `--ink-2` |

状态色原色**禁止直接作文字色**（最高 2.91:1）。`--ink-3`（2.77:1）/ `--ink-4`（1.91:1）仅用于辅助与装饰文字，不得承载关键读数或口径。

---

## 5. 线条 / 圆角 / 标注视觉规范

### 5.1 线宽、端点、虚线节奏

| 对象 | 线宽 | 端点 / 连接 | 备注 |
|---|---|---|---|
| FAQ 线描主体 | 6–8px（既有 8/7/6px） | `round` / `round` | 同色系粗线，非描边 |
| 习惯插画主体描边 | 5–7px（既有环 7px） | `round` | 内部图形 ≤3px |
| Hero 装饰 / 点睛 | 3–5px（墨镜腿 4px、吸管 5px） | `round` | 植物剪影无描边 |
| Promo 细部（嘴、星芒） | 1.6px | `round` | 既有值，保留 |
| 文章示意图引导线 | 1px `--gray-line` `dash 3 4` | `round` | 禁止箭头 |
| 图表主数据线 | 1.6px（area 1.8 / spark 1.5 / mini 1.4） | `round` / `round` | 全部 `vector-effect="non-scaling-stroke"` |
| 参考 / 平均 / 目标线 | 1.2–1.4px | `round` | 虚线 `2 3`（baseline）/ `4 4`（目标） |
| 网格线 | 1px | `round` | `dash 3 4` |
| 数据点白描边 | 2px | — | `stroke="#FFFFFF"` |
| 睡眠环 / 身体年龄环 | 24 / 17 / 7px | `round` | `chart-ring` / `chart-disc` 既有 |
| 堆叠条 | 高 14px（stack）/ 宽 34px（capsule） | — | `rx=7` / `rx=17` |

全局：`stroke-linecap="round"`、`stroke-linejoin="round"`；禁止 `butt` / `square` / `miter`；虚线节奏只允许 `3 4`、`2 3`、`4 4` 三种。

### 5.2 圆角与阴影

| 元素 | 圆角 | 阴影 |
|---|---|---|
| 卡片 | 22px | `0 6px 22px rgba(38,50,44,.045)`（唯一） |
| 小卡 / 文章内文图 / `.radius-sm` | 14px | 无 |
| FAQ / 横幅插画容器 / 文章题图 | 16px | 无（插画内部禁止 filter） |
| 习惯卡 | 18px | 同卡片；hover `0 10px 26px rgba(38,50,44,.10)` + `translateY(-2px)`（仅桌面） |
| 图表柱顶 | `rx=min(bw/2,5)` | 无 |
| 徽标 | 999px（PRO 6px） | 无 |
| tooltip | 12px | `0 5px 18px rgba(40,50,45,.14)`（唯一例外） |

禁止：内阴影、发光、多重阴影、插画内 `drop-shadow`、卡片描边（`.card.flat` 的 1px `#EEF0F1` 为既有例外）。

### 5.3 图表文字、图例

- 轴标签：8.5px `#9BA1A7`，`font-family="-apple-system,BlinkMacSystemFont,PingFang SC,sans-serif"`；x 轴首 `text-anchor="start"` / 中 `middle` / 末 `end`；双行柱标签 y=`bottom+13` / `+23`；y 轴标签 `x=315 text-anchor="end"`；字数 ≤6 汉字/8 字符，超出由 Phase 2 精简，禁止缩小字号解决。
- `chart-disc` 中心 13/39/11px 文字（含 11px `#5D6266` 的「多5.9岁」）为**截图可见的既有例外，视觉值一律保留、不放大不换色**；其他图表禁止任何 SVG 文字。该 11px 文本**只作装饰性读数，不承担单位 / 口径 / 来源职责**；口径与来源必须在 DOM 提供 ≥11.5px `--ink-2` 的副本作为唯一口径载体（R1/Q19，见 §9）。Phase 4 验收以 DOM 副本为准，不因 §8-5 / 验收第 6 条回改 SVG。
- 图例 `.chart-legend`：11px `--ink-3`，位于图下 8px，左右两端对齐；色标 `<i>` 14×2px，实线 `#B9BEC6`、虚线 `repeating-linear-gradient(90deg,var(--lav) 0 3px,transparent 3px 6px)`、`pinkline` `--red`、`grayline` `#B9BEC6`；与文字间距 6px；**最多 3 项**，超出改用 sheet 说明，禁止折行堆叠。
- `.legend`（卡内状态点）：11.5px `--ink-2`，8px 状态圆点，项间距 14px。

### 5.4 单位与数据来源角标

- **单位**：紧随数值之后，`12.5–14px / 600`，`margin-left 2–3px`，色 `#4C5358`（大数值 14px、指标值 12.5px），与数值基线对齐；用 `--font-num`；禁止把单位写进 SVG、禁止换行、禁止加括号。本身已 ≥11.5px 且对比高于 4.5:1，**不另造数值**。
- **数据来源角标 / 口径说明（R1/Q20 裁决，以 §8-5 为准）**：位置固定在**图表卡右下角**（与卡片右内边距 20px 对齐）或图例行末，距图例 ≥8px，单行不折行；**`≥11.5px / 400`，色 `--ink-2 #5C6268`（6.17:1）**，行高 1.5；格式模板（**文案内容由 Phase 2 定义，本阶段只定排版**）：`数据来自 {来源} · 更新于 {时间}` / `口径：{说明}`；禁止叠加在图表墨迹上、禁止 8.5px、禁止用状态色、禁止 `--ink-3`。原 §5.4 的「10.5–11px / --ink-3」已废止。
- **既有可见样式只读例外**：截图已存在的 `.update-note`（today 页「数据更新于 10:05」，11px `#B0B6BA`）、`.metric-note`（11.5px `--ink-3`）等 DOM 文字属截图可见，**保持原样、不得按本节高对比要求「升级」**；本节只约束 Phase 2 新增的 `note-source-*` / 口径说明文字。此例外不推翻 §8-5。
- `aria-label` 里概括结论即可，禁止把整串数值序列读出来；图表需有 DOM 表格或 sheet 作为数据兜底（由 Phase 2/3 落实）。

### 5.5 必要标注徽标

| 徽标 | 规格 | 状态 |
|---|---|---|
| `ui-badge-pro`（PRO） | 9.5px / 800 / letter-spacing .04em，`--green` 底白字，radius 6px，padding `2px 7px`，`vertical-align:2px` | 默认；disable 不用 |
| `ui-badge-state-*`（4 档） | 11.5px / 650，radius 999px，padding `4px 10px`，底/字见 4.3 表 | 默认 / hover 不变 / 不设 disable |
| `ui-badge-star` | 同状态徽标，`--green` 底白字 | 默认 |
| `i` 说明按钮 | 22px 圆，色 `#AEB4B9`，图标 14px | hover → `--green-deep` + `--green-soft` 底 |
| 焦点态 | `outline:3px #4C8FE8; outline-offset:3px; border-radius:6px` | 沿用 `base.css`，不得改 |

### 5.6 关键组件状态（与体验 / 前端对齐，不改动截图可见样式）

| 组件 | 默认 | 悬停（仅桌面） | 禁用 |
|---|---|---|---|
| 卡片 | `#FFFFFF` / 22px / padding 20 / margin 20 / 无描边 / `--shadow` | 不变（卡片非可点）；`.habit` 例外见 5.2 | 不设 |
| 胶囊按钮 `.pill-btn` | radius 999 / padding `8px 13px` / 13px 600 / `rgba(255,255,255,.86)` + 1px `#E9EEEA` / 字 `--green-deep`（`.is-purple` 用 `--purple`） | 白底 + `0 4px 14px rgba(60,120,85,.14)` + `translateY(-1px)` | `opacity .45`，无位移无阴影 |
| 圆形按钮 `.circle-btn` | 46px（detail 42px）/ 白 80% + 1px `#EAECEF` / 图标 20px | 白底 + `translateY(-1px)` + `0 4px 14px rgba(0,0,0,.08)` | `opacity .4` |
| 分段控件 `.segmented` | radius 999 / 底 `--green-soft` + 1px `rgba(255,255,255,.7)` / 14px 600 | 字色 `#244B34` | 选中：白底 + `0 2px 8px rgba(50,80,60,.1)`；睡眠系 `.is-purple`：底 `#E9E3FA`、选中 `#D8D0F0` 字 `#3C3270` 无阴影 |
| 标签栏 `.tabbar` | 66px / radius 999 / 白 94% + 1px `#EDF0EE` + `0 8px 28px rgba(30,45,36,.13)` / 图标 21px / 10.5px | 项 `translateY(-1px)` + `#F3F6F4` 底 | `.is-disabled` 字/图标 `#B4BAB7` |
| 空状态 | 见 3.4 | 无 | 无 |

**错误态**：53 张截图无表单错误态，禁止自行设计「错误红」样式；若 Phase 2 确需提示，用 `--orange` 作提示点 + `--ink-2` 12.5px 文案，不得动用 `--red`（已绑定心率波形）。

---

## 6. 命名与文件规范

### 6.1 kebab-case 命名规则

```
<类别前缀>-<页面|文章>-<语义>[--<变体>[--<变体>]].svg
```

- 全小写、单词间单连字符 `-`，变体用双连字符 `--` 分隔，**最多 2 段变体**，顺序固定为「先色调 / 再状态或皮肤」。
- 类别前缀：`ill-`（插画：hero / faq / habit / promo / empty）、`art-`（文章题图与章节示意图）、`chart-`（图表资源 ID）、`ui-`（徽标 / 图例等 DOM 组件，不产出 .svg 文件）、`note-`（单位 / 来源角标，纯文本规范项）。
- 禁止：`-2` `-copy` `-final` `-v2` `-new`、下划线、驼峰、中文、空格、日期戳、数字序号结尾（章节编号用语义词，如 `sdn` 用 `sdnn`）。

### 6.2 ID 与页面 / 文章章节的对应规则

| 规则 | 示例 |
|---|---|
| 页面级插画 = `ill-<类>-<page>-<语义>` | `ill-hero-pool-relax.svg`、`ill-promo-understand-trend.svg` |
| FAQ = `ill-faq-<语义>`（跨页复用时不带 page） | `ill-faq-stress-overload.svg`、`ill-faq-vo2max-what.svg` |
| 习惯 = `ill-habit-<habit>`，habit 取截图可见名称的英文语义词 | `ill-habit-sun.svg` / `breath` / `steps` / `noise` / `water` / `caffeine` |
| 空状态 = `ill-empty-<语义>` | `ill-empty-watch-pending.svg` / `ill-empty-feeling.svg` / `ill-empty-range.svg` |
| 文章题图 = `art-<article>-cover` | `art-hrv-cover.svg`、`art-age-cover.svg` |
| 章节示意图 = `art-<article>-<section>`，section 与 `data-scroll-to` / 章节 id 同名 | `art-hrv-sdnn.svg`、`art-hrv-mean-rr.svg`、`art-hrv-pnn50.svg`、`art-hrv-mxdmn.svg`、`art-hrv-cv.svg`、`art-age-biological.svg`、`art-age-aging-rate.svg` |
| 图表 = `chart-<renderer>`；`data-chart` 值即 renderer 名 | `chart-line` / `chart-ring` / `chart-mini` …（14 个，见 2.2） |
| 变体后缀 | `--tone-mint` `--tone-lavender` `--tone-peach` `--tone-white`；`--green` `--peach` `--mint`；`--state-excellent` `--state-normal` `--state-caution` `--state-overload`；`--dark`（**仅预留命名，本阶段 24 个资源一律不使用**，R1/Q5）；例：`ill-faq-vo2max-what--peach.svg` |

**图表特别说明**：50 处图表在构建期由 `charts.mjs` 把 `<div class="chart" data-chart="...">` 展开为内联 SVG，**不落独立 `.svg` 文件**；`chart-*` 是资源 ID，写在 manifest 里并与「页面 + 指标 + 数据口径条目」绑定。`prototype/assets/chart/` 只放「示意模板 / 口径标注示例」，不得放运行期图表。

> **R1/Q5 深色后缀裁决**：`--dark` 保留为合法后缀语法，但**原型 HTML 侧不产出 `--dark` 文件**（53 张截图无深色依据）。Phase 3 仅在 manifest 为全部 24 个资源写 `darkVariant: reserved`，并在 SwiftUI `Assets.xcassets` 预留 Any / Dark 槽位；不新增插画文件、不新增深色视觉数值。详见 §3.6 与 §9。

### 6.3 目录组织（按 Phase 3 实际落盘结构核对，R2 校正）

```
prototype/assets/
  spec/
    01-visual-spec.md             # 本文档
    02-usage-and-data-spec.md     # Phase 2 场景 / 口径表（体验成员产出，已落盘）
  data/
    chart-series.json            # Phase 2 数据序列定义（实际落盘位置，非 spec/）
  ill/
    hero/  faq/  habit/  promo/  empty/      # 15 个 SVG
  art/
    hrv/  age/                              # 9 个 SVG
  manifest.json                   # id → 文件 / viewBox / 页面 / 变体 / origin / alt / aria / darkVariant
Healthy/Resources/Assets.xcassets/
  Illustrations/  ArticleArt/  EmptyStates/   # 同名资源（去 .svg）；预留 Any / Dark 槽位，本阶段不产出深色 SVG
```

> **R2 路径校正**：`chart-series.json` 实际位于 `prototype/assets/data/`，此前目录树误写为 `spec/`，已更正。`chart/`（示意模板位）当前**未落地，不作为 Phase 4 验收项**；运行期图表仍由 `charts.mjs` 构建期内联展开，不落独立 SVG。`ill/` + `art/` 合计 24 个 SVG，与 §7 清单一致。

SwiftUI 侧资源名与 prototype 侧 ID 保持一致（仅去扩展名），便于双端比对；`origin` 字段与 `source-hashes.txt` 共同用于 Phase 4 验收。

### 6.4 alt / aria 文案模板

| 类型 | 模板 | 规则 |
|---|---|---|
| 插画（有信息） | `role="img" aria-label="风格化插画：{主体}在{场景}{动作}"` | 例：`风格化插画：绿色卡通角色戴墨镜在泳池中放松` |
| 插画（纯装饰） | `aria-hidden="true"` | manifest 仍须写完整 alt，供 iOS `accessibilityLabel` 兜底 |
| 文章题图 | `alt="文章题图：{文章标题}（示意，不含数据）"` | 不得写数值 |
| 章节示意图 | `alt="{章节名}示意：{一句话说明图中关系}，非真实测量数据"` | 关系一句话 ≤30 字，由 Phase 2 提供 |
| 空状态 | `alt="空状态插画：{语义}（页面可见文案保持不变）"` | 不得复述或改写页面文案 |
| 图表 | `role="img" aria-label="{指标}{时间范围}{图表类型}：{关键结论}；单位 {unit}；口径见下方说明"` | 口径文案由 Phase 2 提供；禁止把整串数值序列写进 aria；缺失值须注明「无数据」 |
| 徽标 / 角标 | 文本本身即可读，不额外加 aria | PRO 需 `aria-label="PRO 功能"`（若 Phase 2 要求） |

禁止 alt 出现「图片」「icon of」「点击查看」等无信息量措辞；所有资源必须带 `data-origin="screenshot|stylized"`（或 manifest `origin` 字段），便于验收区分复刻与补齐。

---

## 7. 应覆盖资源清单（草案）

**合计 24 个 SVG 资源：10 个 `【V·复刻】` + 14 个 `【S·补齐】`；另 14 类图表为资源 ID（不落文件）**。图表实例按页面列出，视觉规范本阶段定稿，数据/口径由 Phase 2 补齐。

### today 今日
| 资源 ID | 标记 | 说明 |
|---|---|---|
| `ill-hero-pool-relax` | 【V·复刻】 | 390×292，保留现有重绘稿全部色值与构图；补 4 档 tone 渐变终点变体 |
| `ill-faq-stress-overload` | 【V·复刻】 | green 对话气泡 + 星芒，`--green` |
| `ill-faq-measure-principle` | 【V·复刻】 | green 手表/云线描，`--green` |
| `chart-spark` ×2 / `chart-line` ×1 / `chart-hist` ×1 / `chart-mini` ×5 | 【V·复刻】 | 今日 HRV / 静息心率迷你趋势、HRV 折线、实时压力直方图、5 个生命体征迷你图 |
| `ui-badge-pro` / `note-unit-` / `note-source-` | 规范项 | DOM，不产出 SVG |

### actions 行动
| 资源 ID | 标记 | 说明 |
|---|---|---|
| `ill-habit-sun` | 【S·补齐】 | 60×60，橙色系，保留「灰环 + 内部几何小图」结构 |
| `ill-habit-breath` | 【S·补齐】 | 60×60，sky 系，同上 |
| `ill-habit-steps` / `ill-habit-noise` / `ill-habit-water` / `ill-habit-caffeine` | 【V·复刻】 | 4 张现有内联 SVG 按 1:1 提取 |
| `ill-empty-feeling--tone-mint` | 【S·补齐】 | 感受记录空状态，96×70，文字不动 |

### insights 洞察 / health 健康
| 资源 ID | 标记 | 说明 |
|---|---|---|
| `chart-bars` ×1（insights）/ `chart-spark` ×4（health） | 【V·复刻】 | 行动与压力对照柱、VO2 / HRV 基线 / 静息心率基线 / 体重迷你趋势 |

### trends 趋势
| 资源 ID | 标记 | 说明 |
|---|---|---|
| `ill-promo-understand-trend` | 【V·复刻】 | 118×78 双人物，右/下出血 |
| `ill-empty-range--tone-white` | 【S·补齐】 | 月/年视图「该时间范围未提供截图」空状态，文字不动 |
| `chart-bars` ×1 / `chart-line` ×2 / `chart-capsule` ×1 / `chart-dots` ×1 | 【V·复刻】 | 周趋势全套 |

### today-detail 详细解读 / day-hrv HRV 日详情 / record-detail 压力记录详情
| 资源 ID | 标记 | 说明 |
|---|---|---|
| `ill-empty-watch-pending` | 【S·补齐】 | 「等待 Apple Watch 采集数据」空状态（today-detail），文字不动 |
| `ill-empty-feeling--tone-white` | 【S·补齐】 | 关联感受空状态（record-detail），与 actions 共用同一 ID 的 tone 变体；保留标题处既有 `icon-ghost` |
| `chart-line` ×3 / `chart-wave` ×1 / `chart-hist` ×1 | 【V·复刻】 | today-detail 折线+波形、day-hrv 折线+直方图 |

> `icon-ghost` 属 `icons.mjs` 现有 216 处图标体系，不纳入本清单，禁止重画；空状态插画不替换标题处的 ghost 图标。

### sleep-day / sleep-month / sleep-vitals 睡眠系列
| 资源 ID | 标记 | 说明 |
|---|---|---|
| `chart-ring` ×1 / `chart-step` ×1 / `chart-stack` ×1 / `chart-wave` ×1 / `chart-mini` ×5 | 【V·复刻】 | 睡眠日报告全套 |
| `chart-bars` ×5 / `chart-stack` ×1 / `chart-dualbars` ×1 | 【V·复刻】 | 睡眠月报告全套 |
| `chart-line` ×5 | 【V·复刻】 | 睡眠生命体征 5 项近 14 日趋势 |

### body-age 身体年龄 / vo2max 最大摄氧量
| 资源 ID | 标记 | 说明 |
|---|---|---|
| `ill-faq-vo2max-what--peach` | 【V·复刻】 | 心形线描，`#F0A36E` |
| `ill-faq-vo2max-improve--mint` | 【V·复刻】 | 心形线描，`#6FC08C`；与上一张造型相同属截图可见，不擅自差异化 |
| `ill-empty-range--tone-mint` | 【S·补齐】 | VO2 90日/1年空状态，复用 trends 空态 ID 的 tone 变体 |
| `chart-disc` ×1 / `chart-area` ×2 / `chart-line` ×1 | 【V·复刻】 | 圆盘、身体年龄/衰老速度面积图、VO2 折线（浅紫既有例外：`#C7C4E8` 线 + white 首点，保留但禁止推广到其他页） |

### ai-article 知识文章（当前完全没有配图，全部风格化补齐）
| 资源 ID | 标记 | 对应章节 |
|---|---|---|
| `art-hrv-cover` | 【S·补齐】 | 「HRV 分量解释」题图，绿/薄荷系 |
| `art-age-cover` | 【S·补齐】 | 「什么是身体年龄」题图，蜜桃/橙系 |
| `art-hrv-sdnn` | 【S·补齐】 | `sec-sdnn` SDNN |
| `art-hrv-mean-rr` | 【S·补齐】 | `sec-meanrr` Mean RR |
| `art-hrv-pnn50` | 【S·补齐】 | `sec-pnn50` pNN50 |
| `art-hrv-mxdmn` | 【S·补齐】 | `sec-mxdmn` MxDMn |
| `art-hrv-cv` | 【S·补齐】 | `sec-cv` HRV CV |
| `art-age-biological` | 【S·补齐】 | 生物年龄 |
| `art-age-aging-rate` | 【S·补齐】 | 衰老速度（第 2 篇截断处的占位段落原样保留，配图不得覆盖/改写） |

### ai-chat 问问 AI
无插画资源；现有 `icon-ghost` 与对话气泡属 DOM/图标体系，不纳入清单。

### 14 类图表 ID 全集（资源 ID，不落文件）
`chart-line`、`chart-area`、`chart-bars`、`chart-hist`、`chart-step`、`chart-dots`、`chart-ring`、`chart-disc`、`chart-stack`、`chart-capsule`、`chart-spark`、`chart-wave`、`chart-dualbars`、`chart-mini`。

---

## 8. 给下一阶段（Phase 2 体验设计）的视觉约束清单

1. **口径必须落在 DOM，不进 SVG**：每张图表需给出指标名、单位、时间范围、x/y 坐标含义与 min/max、数据来源与更新时点、缺失值语义；文案放 `.chart-legend` / `.metric-note` / 数据来源角标，位置、字号、颜色按 5.3–5.4 固定，不得改动，也不得写进 SVG。
2. **四档状态色语义锁死**：绿优秀 / 紫正常 / 橙注意 / 粉过载；`purple` / `red` / `teal` / `sky` 不是状态色；禁止第五档状态色；禁止把状态色原色用作文字色（最高 2.91:1）。
3. **资源 ID 与页面/章节一一对应**：补齐资源必须标 `origin: stylized`，并提供 alt 模板所需的「主体 / 场景 / 关系」三要素（章节示意图一句话 ≤30 字）；不得改变截图可见文案，不得新增页面/功能。
4. **数据序列不得由视觉侧臆造**：`data-seed` 伪随机图（`chart-hist` / `chart-dots` / `chart-mini` / `chart-wave` / `chart-ring` / `chart-step` / `chart-stack` 等）若需真实口径，须由体验侧说明「每个点/柱/段代表什么、时间粒度、缺失如何标记」；视觉侧只保证网格、点径、白描边、缺失值样式一致，不代为编造数值。
5. **承载信息的文字走高对比（本条为 §5.4 的最终裁决口径，R1/Q20）**：单位/来源/口径 ≥11.5px 且用 `--ink-2 #5C6268`（6.17:1）；8.5px `#9BA1A7` 仅限坐标轴刻度；图例最多 3 项，超出改用 sheet。**截图已存在的 `.update-note` / `.metric-note` 保持原样，不按本条升级**；`chart-disc` 11px SVG 文字保留但不作口径载体，口径以 DOM 副本为准（R1/Q19）。
6. **适配只换背景层**：4 档 tone 只允许改 L1/L2 与文字反相，主体造型与状态色恒定；变体后缀按 6.2 固定顺序命名。**原型 HTML 侧不启用深色**（R1/Q5）。
7. **技术边界**：全部资源为可内联 SVG 或纯数据；禁止 `<image>` / `<foreignObject>` / 外部 `<use href>` / 位图 / CDN / `@font-face` / `<script>` / 外部字体；SwiftUI 侧仅在 `Assets.xcassets` **预留 Any / Dark 槽位**（manifest 记 `darkVariant: reserved`），不产出深色 SVG、不新增深色视觉值（R1/Q5）。
8. **消歧不换色**：`charts.mjs` 中 `greenDark` / `purpleSoft` / `ink` 与主色板的命名冲突按 1.5 节改名即可，色值一律保持，不得以「统一」为由改动任何可见颜色。

### 附：视觉验收 8 条（供 Phase 4 引用）

1. 所有 `【V·复刻】` 资源 viewBox、色值、构图锚点与现有内联稿逐项一致（含 hero 角色 bbox `x104–290 / y74–226`）。
2. 所有 `【S·补齐】` 资源带 `origin` 标记且未改动任何截图可见文案。
3. 无 A/B 两表之外的 HEX；无外部字体、位图、CDN、脚本。
4. 线宽 / 圆角 / 阴影 / 端帽 / 虚线节奏全部落在第 5 节数值内。
5. 图表绘图区 `x 8–312` 完整、轴标签未被裁切、缺失值用 `--faint` / `#E9EAEE` 且 aria 注明「无数据」。
6. **Phase 2 新增**的单位 / 来源 / 口径文字 ≥11.5px 且对比 ≥4.5:1；除 `chart-disc` 既有中心 13/39/11px 文字外，SVG 内无标题、单位、口径、来源文字；disc 的口径以 DOM 副本验收。截图既有 `.update-note` / `.metric-note` 不按此条改造。
7. hero 在 320 / 375 / 390 / 430pt 四种视口下，主体均落在 `x40–350 / y16–276` 安全区内。
8. 每个资源有 alt/aria 与 manifest 条目；manifest 为 24 个资源预留 `darkVariant: reserved`，**原型侧无 `--dark` 文件即视为合格**（R1/Q5）。

---

## 9. 修订记录

### R1 · 规范内部一致性修订（响应 Phase 2 待确认清单 Q19 / Q20 / Q21 / Q5）

由 `ux-designer` 在 `02-usage-and-data-spec.md` §4 提出 4 项冲突；经核对 `prototype/src/screens/today-detail.html`、`charts.mjs`、`components.css` 后，由本规范作者裁决并直接修订 01，**Phase 2 的 4 条「默认处理」全部转正，无需再等用户确认**。01 的其余数值、24 个资源清单、14 类图表 viewBox 均未改动。

| 编号 | 冲突点 | 裁决（已写入 01） | 涉及章节 |
|---|---|---|---|
| Q20 | §5.4 来源角标 `10.5–11px / --ink-3` 与 §8-5 / 验收 6「≥11.5px / --ink-2」冲突 | **以 §8-5 为准**：新增 `note-source-*` / 口径文字 `≥11.5px / 400 / --ink-2 #5C6268`（6.17:1），位置仍按 §5.4（卡片右下角 / 图例行末，距图例 ≥8px）。§5.4 旧值废止。**新增保护**：截图可见的 `.update-note`（11px `#B0B6BA`）/ `.metric-note`（11.5px `--ink-3`）属既有只读样式，不得被「升级」改写 | §5.4、§8-5、验收 6、§4.6 |
| Q19 | §5.3 保留 `chart-disc` 13/39/11px SVG 文字 与 验收 6「SVG 内无口径文字」冲突 | **两者并存且明确分工**：SVG 既有文字视觉值一律保留（不放大、不换色），只作装饰性读数；口径/来源唯一载体为 DOM 中 ≥11.5px `--ink-2` 副本。验收 6 加「除 `chart-disc` 既有中心文字外」限定，Phase 4 以 DOM 副本为准 | §3.5、§5.3、§8-5、验收 6 |
| Q21 | §4.4 把 today-detail 虚线标为「近 30 日平均 HRV 40」，与 DOM 图例「今日平均HRV / 近30日平均HRV」、正文「今日平均 40ms，高于近30日平均线(基准线) 30ms」冲突 | **规范侧彻底退出数据语义**：§4.4「说明」列改为只描述视觉角色（`chart-line` 的 `data-baseline` 水平参考线），并新增「§4.4 适用边界」声明——指标名、数值、口径一律以 DOM 图例与 `02-usage-and-data-spec.md` 为准，视觉规范不据此改动 SVG 或数值。40 / 30 / 38 等数值全部不做改动，也不在图中另画第二条基线 | §4.4、§4.5 前注 |
| Q5 | §6.2 / §8-7 要求 `--dark` 与 SwiftUI Any+Dark 两套，但 53 张截图无深色依据 | **采纳 Phase 2 默认**：原型 HTML 侧不启用深色、不产出 `--dark` SVG、不新增深色视觉值，24 个资源总数不变；`--dark` 仅保留为合法后缀语法；SwiftUI 侧由 Phase 3 在 `Assets.xcassets` 预留 Any / Dark 槽位并在 manifest 记 `darkVariant: reserved`。§3.6 深色适配规则降级为「预留、本阶段不执行」 | §2.1、§3.6、§4.5、§6.2、§6.3、§8-6/7、验收 8 |

**顺带校正**：§6.3 目录树中 Phase 2 文件名由占位 `02-usage-and-caliber.md` 更正为实际已落盘的 `02-usage-and-data-spec.md`，并补入 `chart-series.json`。

**给 Phase 3 的净影响**：`prototype/` 侧资源总数仍为 24 个 SVG + 14 类图表 ID，无新增文件；唯一需新增的是 manifest 的 `darkVariant: reserved` 字段；CSS/SVG 属性改动仍只有 hero 的 `preserveAspectRatio="xMidYMid slice"` 一处。Phase 2 的 Q19/Q20/Q21/Q5 可从「待确认」移入「已裁决」。

### R2 · 作用域与路径校正（响应 Phase 2 的 46 点悬空指针修复）

| 项 | 内容 | 涉及章节 |
|---|---|---|
| R2-1 | §3.0 补「适用范围（R1 补充）」：四层结构与「L4 最多 6 个元素」只约束 `ill-*` / `art-*`；14 类既有图表不在此列，`chart-disc` 的 46 装饰点属 `【V·复刻】` 既有稿，数量/位置一律保留、纯装饰无数据语义 | §3.0 |
| R2-2 | **修正 01 自身的悬空路径**：`chart-series.json` 实际落盘于 `prototype/assets/data/`，此前 §6.3 误写为 `spec/`；目录树改为按 Phase 3 实际结构（`spec/` 2 份 md、`data/` 1 份 json、`ill/` 15 SVG、`art/` 9 SVG、`manifest.json`），并标注 `chart/` 示意模板位当前未落地、不作验收项 | §6.3 |
| R2-3 | 交叉核对 Phase 2 的 15:25 修复：`chart-series.json` 中 `decoration.dots` 悬空引用残留 0；`sharedSeries.discDecorativeDots.dots` 为 46 项，与 `02-usage-and-data-spec.md` §5.3 ⑤ 同值；01 §3.0 的「生成侧真源 = `charts.mjs` 的 `disc()`」与「口径侧真源 = `sharedSeries.discDecorativeDots.dots`」是同一批点的两种表述，互不冲突，无需任何一方再改 | §3.0、§6.3 |

R2 只改说明性文字与路径，**未改动任何色值、尺寸、线宽、24 个资源清单、14 类图表 viewBox 或 R1 的 4 条裁决**。01 现为唯一权威版本，Phase 4 按此版验收。
