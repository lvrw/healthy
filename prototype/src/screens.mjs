// 页面清单与 53 张截图的对应关系。每条 source 均为 docs/ 下的实际文件名（不含扩展名后缀）。
// evidence 标注：图中观察 / 人工更正 / 推断 / 待确认。
const S = (name) => `${name}_1_105_c.jpeg`;

export const screens = [
  {
    id: 'today', file: 'today.html', title: '今日', group: '主导航', tab: 'today', tone: 'white', time: '10:05', tabbar: true,
    subtitle: '首页 · 状态总览与今日数据',
    sources: ['6C47517B-2B82-4CC4-B252-135FD1BF0081', 'FD350AED-A537-47F6-B8E9-EDE3B05624D3', '294A6146-DD01-43D7-B73F-D1F1DF4BF447', 'D48F130E-1760-4DC4-85C7-C7EF8F84D60B', '6876F2A2-7CA5-447F-B21D-922CB83F36DA'].map(S),
    states: ['默认', '底部导航选中', '图表点选中/悬停提示', '卡片与链接悬停'],
    notes: ['观察：顶部插画、状态优秀、40ms、4小时47分钟、状态条四段配色均来自截图。', '观察：D48F130E 为图表浮层选中态，原型中点击 HRV 折线点可复现。', '推断：插画为依据原图风格重绘的 SVG 占位（非截图铺底）；状态栏时间统一取 10:05。', '待确认：真实数据来源与刷新规则未提供，所有数字为截图中的静态值。'],
  },
  {
    id: 'actions', file: 'actions.html', title: '行动', group: '主导航', tab: 'actions', tone: 'mint', time: '10:09', tabbar: true,
    subtitle: '行动 · 当日习惯卡片',
    sources: ['7B8C67A9-A6D0-4B94-8F6A-4BAB834E906E', 'FFD32EA8-8057-4947-9DC5-0E1CF78BCC1C'].map(S),
    states: ['默认', '子页签选中（行动/洞察）', '习惯卡片悬停', '加水/咖啡因计数 + 成功提示', '拖拽排序说明（静态）'],
    notes: ['观察：周历条、智能建议、睡眠/健身/感受记录及 6 张习惯卡片。', '推断：+ 按钮的计数行为为本地 mock，截图未展示点击后状态。', '待确认：长按拖拽排序的真实交互未提供，仅保留说明文案与视觉。'],
  },
  {
    id: 'insights', file: 'insights.html', title: '洞察', group: '主导航', tab: 'actions', tone: 'mint', time: '10:10', tabbar: true,
    subtitle: '行动 · 洞察子页',
    sources: ['FA252A5D-3251-4760-AE33-49880758472D', 'ACABD5F9-5EEC-463D-9B6F-A7251B6EE1F1', '7540A8A5-DEC1-41AC-B3C2-542EE69C6EC8', 'CB5C9B74-B32D-4F2F-8B0B-4F4AA57F12B9', 'DF7BFF44-C02C-442F-9BD1-ADD27C3041C8'].map(S),
    states: ['默认', 'ⓘ 说明弹层', '关键行动详情弹层', '列表空状态（感受趋势 0 天）'],
    notes: ['观察：三张底部说明弹层分别对应关键行动、行动 v.s. 压力趋势、睡眠质量 80 分以上。', '观察：感受趋势「过去60天里，你记录了0天感受」为原图空状态。', '推断：筛选器「睡够7小时」的下拉选项未提供，点击仅提示未包含该数据。'],
  },
  {
    id: 'trends', file: 'trends.html', title: '趋势', group: '主导航', tab: 'trends', tone: 'white', time: '10:11', tabbar: true,
    subtitle: '趋势 · 周视图',
    sources: ['C3B070F9-0C3C-4AA2-B402-B962AC43B06A', '5C2528EE-3038-40C1-9434-57C9C91F315A', 'A0611BA6-E0EF-48B0-93B1-080A9F0F6FE1', '3156C1B4-D8CD-4D07-A21C-DF0AB15FCA25'].map(S),
    states: ['周/月/年页签选中', '月、年视图空状态（截图未提供）', '推广横幅可关闭', '分享按钮 mock'],
    notes: ['观察：仅「周」视图有截图；压力分布 63 次、压力时段点阵、HRV 与静息心率数值均照录。', '观察：C3B070F9 顶部有可关闭的「如何理解压力趋势？」横幅。', '推断：月/年视图未提供，切换后明确显示占位空状态，不虚构数据。'],
  },
  {
    id: 'health', file: 'health.html', title: '健康', group: '主导航', tab: 'health', tone: 'mint', time: '10:11', tabbar: true,
    subtitle: '健康 · 身体指标总览',
    sources: ['5C88A429-DB63-45DC-A34E-851CBA89241B', '6EF55158-73D8-48AD-95B1-0926B8DF5D64'].map(S),
    states: ['默认', '卡片入口悬停/跳转', '身体测量 + 按钮禁用提示'],
    notes: ['观察：身体年龄 34.2、心脏健康三项、消耗 1956 千卡、身体测量三项。', '推断：+ 按钮对应的新增表单未提供截图，点击仅显示明确标注的占位提示。', '观察：两张截图为同一页面不同滚动位置。'],
  },
  {
    id: 'today-detail', file: 'today-detail.html', title: '详细解读', group: '今日链路', tab: '', tone: 'white', time: '10:06', tabbar: false,
    subtitle: '今日 · 详细解读弹层',
    sources: ['E4D81D53-9C1A-4585-B426-E4C87E744492', '4FE53804-3B05-4343-9A61-9FFFF71C8888', '69FD1DDA-ABE7-44A8-B068-C431DE1207BD'].map(S),
    states: ['默认', '「暂无今日静息心率数据」空状态', 'FAQ 链接悬停/跳转', '关闭返回今日'],
    notes: ['观察：三张截图为同一弹层自上而下的连续滚动位置。', '观察：含状态总结、HRV 40ms 基准线对比、8 条常见问题。', '推断：了解更多/问问AI 的跳转目标按同链路页面连接，均为本地切换。'],
  },
  {
    id: 'record-detail', file: 'record-detail.html', title: '压力记录详情', group: '今日链路', tab: '', tone: 'white', time: '10:07', tabbar: false,
    subtitle: '08:42 · 注意压力记录',
    sources: ['8C6CF90F-CB4A-4933-B243-2FEA8BD66761', 'AC6C7D4E-68F1-45AA-B929-85F6A2440D9F'].map(S),
    states: ['默认', '关联感受空状态', '相关心率数据定义链接'],
    notes: ['观察：24ms·注意压力、由 StressWatch 计算得出、08:42:15 - 08:43:13。', '观察：所有数据 PRO 共 7 项（SDNN / Heart Rate / Mean RR / pNN50 / MxDMn / Moda / CV）。', '推断：两张截图为同一页面不同滚动位置。'],
  },
  {
    id: 'day-hrv', file: 'day-hrv.html', title: 'HRV 日详情', group: '今日链路', tab: '', tone: 'white', time: '10:06', tabbar: false,
    subtitle: '2026年11月7日 · 全部记录',
    sources: ['00B0986D-AC81-49D8-B973-79329F5DD9D4', '57975CDC-8E5F-43F9-8BF8-E7D3E5B5AC6C'].map(S),
    states: ['默认', '压力水平四档图例', '所有数据列表', '分享 mock'],
    notes: ['观察：今日 HRV 趋势折线、实时压力 PRO 直方图、压力水平四档阈值与 5 条记录。', '观察：包含 RMSSD 与 SDNN 计算方式差异的说明段落。', '推断：两张截图为同一页面不同滚动位置。'],
  },
  {
    id: 'ai-chat', file: 'ai-chat.html', title: '问问 AI', group: '今日链路', tab: '', tone: 'white', time: '10:06', tabbar: false,
    subtitle: '问问 AI · 对话弹层',
    sources: ['30CE4AB3-C608-44A4-B001-54401ABE6B5F'].map(S),
    states: ['默认', '输入框为空 → 发送禁用', '发送加载中 → mock 回复', '复制/赞/踩选中', '建议问题填充输入框'],
    notes: ['观察：回答正文、复制/赞/踩、两条建议问题、输入占位文案。', '推断：发送后的回复为合成 mock，明确标注，不代表真实模型输出或接口。', '观察：顶部关闭与复制图标、底部输入框圆角样式。'],
  },
  {
    id: 'ai-article', file: 'ai-article.html', title: '知识文章', group: '今日链路', tab: '', tone: 'white', time: '10:07', tabbar: false,
    subtitle: 'HRV 分量解释 / 身体年龄科普',
    sources: ['F9EB1D2F-43DA-4705-9BD5-AA79F3DE93D8', '2F37852E-DA2A-42B6-9800-CAED56A3A741', '1A8631B4-6408-4F7B-B80C-12917863C218', '0D9C1245-07A0-4E8D-995E-EA1D49A2CA39', '29151EDE-5FB2-4BCC-886C-3B3EF27C00D7', '3C207838-9665-4BDC-B3FD-B183D2345D39'].map(S),
    states: ['默认', '章节导航选中/滚动定位', '返回顶部按钮', '菜单/亮度按钮占位'],
    notes: ['观察：5 张截图为「HRV 分量解释」长文不同滚动段落；3C207838 为「什么是身体年龄」文章。', '观察：顶部固定栏为菜单、绿色幽灵 logo、亮度图标。', '推断：用章节标签还原滚动位置对应关系；章节标题与正文按截图录入。'],
  },
  {
    id: 'sleep-day', file: 'sleep-day.html', title: '睡眠报告 · 天', group: '健康 / 睡眠', tab: '', tone: 'lavender', time: '10:08', tabbar: false,
    subtitle: '睡眠报告 · 2026年11月7日',
    sources: ['C542FADB-04AC-4973-84C9-E15E7D5992D5', '08C0FB22-C76E-456B-86B1-554BCE44C8A1', 'EFD06EB1-B37C-4366-8FD3-9EFE68ACD753', '7DEAF6A5-46C5-4A63-8F1F-56F6656985CF', 'E9D1B627-EDAC-4FC6-9C33-A51157B332E8', 'F9A6E2F1-9320-4B49-9F35-D7DAAC023B3D', 'A5E2D992-B302-4ED7-8F1E-EF6B5081CA81'].map(S),
    states: ['天/周/月页签选中', '睡眠心率变化说明弹层', '日期切换上一日禁用', '问问 AI / 分享 mock'],
    notes: ['观察：紫色双环、「需要重视睡眠了」、49 分、5 项睡眠质量维度、睡眠阶段、睡眠时心率。', '观察：A5E2D992 为「睡眠心率变化」底部说明弹层，含三段阈值条。', '推断：天/周/月切换中「周」无对应截图，切换后显示占位空状态。'],
  },
  {
    id: 'sleep-month', file: 'sleep-month.html', title: '睡眠报告 · 月', group: '健康 / 睡眠', tab: '', tone: 'lavender', time: '10:09', tabbar: false,
    subtitle: '睡眠报告 · 11月1日 - 11月30日',
    sources: ['18F0001D-CC8E-47D0-B9CA-E809438CDF39', '4F7B83B5-1B7B-4AAC-B5CF-9D0F7AB95ECF', 'CB72BAC8-5168-46B5-8086-1FFE61251068', 'FC0A93AE-558F-4A71-893F-9F6F3D966975', 'E53C21A8-DF9E-4CF1-B66F-68143108B372'].map(S),
    states: ['月视图选中', '晚睡日历空日期', '质量最佳/最差标记', '时长&占比排序下拉占位'],
    notes: ['观察：5 张截图为月视图不同滚动段：有效睡眠占比、睡眠心率变化、晚睡日历、睡眠规律性、睡眠时长与恢复性睡眠。', '观察：晚睡日历中大量 "--" 空日期格，属于原图的空状态。', '推断：图表数值按截图上的柱状高度近似重绘。'],
  },
  {
    id: 'sleep-vitals', file: 'sleep-vitals.html', title: '睡眠生命体征', group: '健康 / 睡眠', tab: '', tone: 'lavender', time: '10:09', tabbar: false,
    subtitle: '2026年11月7日 · 共 14 天趋势',
    sources: ['904B504F-FF11-475C-9DA3-28EFAB38CC55', 'FC849382-5B6D-4D21-8CD4-3939265C531A', '467B9CCE-7AAE-46D9-84E3-FED38CB34FC5', '53A32893-38A0-4318-81DB-C3756B64D98A', '39217ADE-BF04-4355-BBA6-B5994BB3293E'].map(S),
    states: ['默认', '优秀 / 正常状态徽标', '了解更多链接', '底部免责声明'],
    notes: ['观察：HRV 40ms 优秀、心率 59bpm 正常、呼吸频率 12br/min、血氧 96.3%、手腕温度 34.9°C。', '观察：5 张截图为同一页面不同滚动位置；904B504F 与 FC849382 内容相同。', '推断：14 日趋势折线按截图节点位置重绘，非真实数据序列。'],
  },
  {
    id: 'body-age', file: 'body-age.html', title: '身体年龄', group: '健康 / 睡眠', tab: '', tone: 'peach', time: '10:11', tabbar: false,
    subtitle: '身体年龄 · 34.2 岁',
    sources: ['DA404064-CE70-4682-9194-D8C22306E964', '4EBB8A86-B02D-40B5-BCF6-EDB5EC6E9765', '52362CA1-8507-443C-95EC-0C2446B4B708'].map(S),
    states: ['默认', '影响因素 9 项列表', '身体年龄 / 衰老速度周趋势', '关于身体年龄入口'],
    notes: ['观察：圆形仪表盘 34.2 / 多5.9岁、衰老速度 -0.2x、影响因素各项 ±岁 数值。', '观察：周趋势最高 36.7 / 最低 33.3 / 平均 35，衰老速度 1x / -0.4x / 0.3x。', '推断：仪表盘与渐变条为风格化 SVG 重绘；趋势曲线按截图走势近似。'],
  },
  {
    id: 'vo2max', file: 'vo2max.html', title: '最大摄氧量', group: '健康 / 睡眠', tab: '', tone: 'mint', time: '10:11', tabbar: false,
    subtitle: '最大摄氧量 · 30 日',
    sources: ['E80542AB-452F-492B-BF1F-779B4D74C28C'].map(S),
    states: ['30日/90日/1年页签选中', '90日、1年空状态（截图未提供）', '建议卡片问问 AI'],
    notes: ['观察：38（11月6日 周五 · 尚可）、最新正常范围 38-57、平均线 38、说明与建议文案。', '推断：仅 30 日视图有截图，其余页签显示明确标注的空状态。', '观察：底部「常见问题」卡片仅露出标题与部分插画，按可见范围还原。'],
  },
];

export const screenById = Object.fromEntries(screens.map(s => [s.id, s]));
