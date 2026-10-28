# 更新日志

算力环的版本号、构建号、构建日期与改动记录，方便核对正在使用的版本。

- **版本号**：`Resources/Info.plist` 的 `CFBundleShortVersionString`，语义化版本（主.次.修订）。
- **构建号**：`Resources/Info.plist` 的 `CFBundleVersion`，每标记一次新的本地构建递增；当前为第 84 版。
- **构建日期**：打包时由 `scripts/build-app.sh` 写入 `CFBundleBuildDate`（Asia/Shanghai 当天），源码中不写死。
- 应用内查看位置：浮窗展开后的**顶部标题栏第三行**（`v1.5.0 · 第 84 版 · 构建 2026-10-28`）、**更多 → 关于 算力环**、以及 `energyctl status` 返回的 `version` / `build` / `buildDate` 字段。
- 应用包运行时按 App 包内的真实值显示；直接 `swift run` 或快照测试等未打包运行时显示「开发版」，不虚构版本号。

## 版本速查

| 版本 | 构建号 | 构建日期 | 状态 | 摘要 |
| --- | --- | --- | --- | --- |
| v1.5.0 | 84 | 2026-10-28 | 本地构建：未打 tag、未发布 | Mini 条新增 AI 通宵（夜间 AI 通宵模式）：一键阻止系统空闲睡眠并立即关闭显示器，屏幕关闭后 AI 后台任务继续运行；再次点击或退出应用恢复默认休眠；使用电池且电量 ≤15% 时自动关闭 |
| v1.4.4 | 83 | 2026-10-26 | 本地构建：未打 tag、未发布 | 新增 Gemini 账户（Gemini 应用登录态 + 官方 5 小时 / 每周限额）；十个账户的 Mini 条、总览、账户页与今日用量 |
| v1.4.3 | 82 | 2026-10-24 | 本地构建：未打 tag、未发布 | 省钱灯新增免费模型监控（Hy4 夜间免费 / Hy3 / Step-5 限免）；Mini 推荐改为能力门槛 + 最多两条强模型优惠；修复 Mini 窗口不随账户隐藏重算与 6pt 结构溢出；测试链修复 |
| v1.4.2 | 81 | 2026-10-24 | 本地构建：未打 tag、未发布（另一工作区副本） | 新增 Qoder CN 与 Trae CN 账户（本机登录态 + 官方 Credits 额度）；九个账户的 Mini 条、总览、账户页与今日用量 |
| v1.4.1 | 80 | 2026-10-24 | 本地构建：未打 tag、未发布 | 新增 WorkBuddy AI（国际版）与百度搭子账户；Mini 条 3 列多排、背景半透明；修好今日用量页裁切 |
| v1.4.0 | 75 | 2026-10-23 | 已公开发布（Apple Silicon），发布日 2026-10-24 | 多账户总览、今日用量、重置雷达；更名「算力环」；新增版本信息与省钱灯 |
| v1.3.4 | 72 | 2026-10-22 | 已公开发布（Apple Silicon） | 双源重置雷达；仓库更名后首个公开版 |

自上一公开版到本版：版本号 +1 个次版本（1.3.4 → 1.4.0）；构建号 +3（72 → 75），即第 73、74、75 版均为 v1.4.0 的构建，其中第 75 版为公开发布版。更早的本地构建（第 35 版、第 71 版）未公开发布、只在本机备份中可见，不在此追溯。

## 未发布（2026-10-27）· 省钱灯推荐口径修正

- **修正「最省」只看绝对低价的错误**：能力 78 的豆包 Mini 曾以 ¥0.5/M 成为「最省」，但它是轻量文本模型，低于能力门槛，不该作为省钱推荐。
- 新增 `PricingEngine.valueScore` / `bestValue`：只有能力 ≥88 的强模型参与，按**性价比（能力分 ÷ 折算单价）**取最高；免费额度仍严格优先于付费。
- 省钱灯详情页与 Mini 条的推荐文案改为「免费 …」优先，否则「性价比 <模型> ¥x/M · 能力 n」；价格行补上能力分与「达标 / 未达标」，弱模型不再隐身在低价后面。
- 折扣推荐从「绝对节省最多」改为「性价比最高」，避免贵模型仅因降价幅度大而插队。
- 自检同步：豆包 Mini 不再进入推荐位，DeepSeek Flash 成为付费性价比首选。

### 模型榜：性价比榜只收近半年上线

- 数据源 OpenRouter `/api/v1/models` 会返回全部 464 个在售模型（含 2023–2025 的旧模型）；页头的「更新于 10-27 12:40」是刷新时间，不代表模型新旧。
- 性价比榜此前对全部已标定收费模型排序，旧的低价模型（Llama 4 Scout 569 天、Qwen3 30B A3B 2507 454 天、GPT-5 Nano 445 天）长期霸榜。
- 新增 `ModelLeaderboardEngine.valueWindow = 180 天`：性价比榜只收近半年上线的已标定模型；更早的旧模型仍保留在能力榜与价格榜，不隐藏、不删数据。
- Python 报告脚本 `model_leaderboard.py` 同步同一口径；榜内说明与页脚注明「近半年」。
- 回归：`Tests/ModelLeaderboardTests.swift` 新增旧模型断言——旧模型在能力/价格榜可见，但不得进入性价比榜。

## v1.5.0（构建 84，构建日期 2026-10-28）· 本地构建

未打 tag、未发布。相对 v1.4.4（第 83 版），本版新增「AI 通宵」（夜间 AI 通宵模式），用于睡前让 AI 后台任务在屏幕关闭后继续运行。

### AI 通宵（夜间 AI 通宵模式）

- Mini 条底部新增「AI 通宵」行：未开启显示「关屏后 AI 继续跑」与「开启」；开启后显示已开启时长与「关闭」，一键切换。
- 核心机制 `NightWatchController` 使用 `ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated])`，只阻止系统因空闲睡眠（等同 `caffeinate -i`），不阻止显示器睡眠。
- 开启后异步调用系统自带 `/usr/bin/pmset displaysleepnow` 立即关闭全部显示器（含内置屏与外接屏），并在 1 秒、3 秒后各补一次，抵消点击残余键鼠事件造成的瞬间唤醒；不需要管理员权限，不修改 `pmset` 配置，不安装后台服务。
- 低电量保护：开启期间随应用时钟每 15 秒读取一次内置电池；使用电池且电量 ≤15% 时自动关闭并释放防休眠断言，Mini 条提示「电量 N%，已自动关闭」十分钟；插电或桌面 Mac 不会自动关闭。
- 再次点击关闭或退出应用时释放防休眠断言，恢复系统默认休眠；应用被强制结束时断言随进程消失，不会留下常驻进程。
- 「更多」菜单同步提供开启/关闭项并显示勾选状态；`energyctl status` 新增 `nightWatch.active`、`nightWatch.startedAt`、`nightWatch.autoStoppedAt`、`nightWatch.autoStopPercent` 与 `nightWatch.notice`。
- Mini 条底部固定增加 22 pt（建议、雷达、AI 通宵三行共 66 pt）；省钱灯行与倒计时行仍各 +22 pt，窗口高度按账户行数自动计算。
- 限制：合上 MacBook 上盖仍会休眠（macOS 独立规则），AI 通宵只在开盖时有效；长时间运行建议连接电源。文档已写清这两点。
- 测试：新增 `NightWatchSelfTest`，覆盖开关幂等、显示器关闭回调、Store 路由、耗时文案、低电量自动退出与提示过期；Mini 布局快照新增 `night` 与 `night-notice` 场景，AppKit 交互测试覆盖「AI 通宵」点击。

### 免费额度修正（2026-10-28）

- **Step-5-Preview 与 Hy3 均已恢复收费**：从 `PricingCatalog.freeOffers` 移除，不再显示「独家限免 / 推荐 / 0 倍率」，也不再占用 Mini 推荐位；免费额度只剩 Hy4 夜间免费（9/11–10/31）。
- **3 天核验窗口**：`PricingFreeOffer` 新增 `verifiedAt`，`PricingFreeOfferState` 新增 `isVerified`；没有明确结束日期的限免活动超过 3 天未复核会标「待核对」并退出推荐，避免把已结束的活动继续当免费。有官方结束日期的活动（Hy4）仍按日期判断。
- 免费额度区块与 Mini 条同步：待核对的活动不再显示「0 倍率」；页脚说明 3 天核验窗口。
- 回归：`PricingSelfTest` 覆盖 Step-5/Hy3 移除、自定义开放活动的 3 天窗口、以及推荐位不再出现免费 Step-5/Hy3。

## v1.4.4（构建 83，构建日期 2026-10-26）· 本地构建

未打 tag、未发布。相对 v1.4.3（第 82 版），本版新增 Gemini 账户，账户总数达到十个（Codex + 九个来源）。

### 新增 Gemini 账户

- `GeminiBalanceClient`：读取 Gemini macOS 应用（`com.google.GeminiMacOS`）的本地登录态。
  - 登录文件 `~/Library/Application Support/com.google.GeminiMacOS/Data/<user>/auth` 为「魔数 + preamble + AES-256-GCM」容器；解密密钥取自钥匙串条目「Gemini Safe Storage / Gemini Keys」的 `KEY_ID_CREDENTIALS`（key id 1，32 字节），`account_config` 决定当前 user 目录。
  - 解密后取 refresh token，经 Google `oauth2/v4/token` 换取访问令牌，再调用 `robinfrontend-pa.googleapis.com` 的 `RobinService/GetUsageInfo`，读取 `GXU_FIVE_HOURLY`（当前 5 小时窗口）与 `GXU_WEEKLY`（每周限额）的已用比例、重置时间与订阅档位。
  - token 只在内存中使用，不落盘、不外传；首次读取需要 macOS 钥匙串授权。
- 账户模型新增 `gemini`：Mini 条主数字为 5 小时窗口剩余、副行 7 天窗口；总览「用量」列显示本窗口已用百分比；账户页显示两个窗口、已用比例、订阅档位与来源说明；今日用量网格显示本窗口已用与周已用。
- Gemini 读取本机保存的登录态，不依赖 Gemini 应用保持运行，Mini 条始终显示（未登录时提示未配置）；其余客户端型账户仍按「自动隐藏未打开应用的账户」隐藏。
- Mini 条排序固定 Codex 第一：其余账户再按「手动置顶 → 使用频率 + 能力」排序，高频打开其他账户不会把 Codex 挤下首位。
- 测试：`Tests/BalanceParsingTests.swift` 新增 Gemini 用量解析、容器加解密、密钥提取与可见性断言；`scripts/test-balance.sh` 与 `test-reliability.sh` 编译新客户端。
- 文档：README、使用说明、隐私与数据同步 Gemini 的来源、读取方式与钥匙串授权说明。

## v1.4.3（构建 82，构建日期 2026-10-24）· 本地构建

未打 tag、未发布。本版基于 v1.4.1（第 80 版）源码线；第 81 版（Qoder CN / Trae CN）在另一工作区副本开发，合并时与本版无文件冲突。改动分三块：

### 免费模型监控（省钱灯扩展）

- `PricingCatalog` 新增 `freeOffers`：WorkBuddy 客户端模型列表 2026-10-24 核对——**Hy4 preview 夜间免费**（9/11–10/31，每晚 23:00–次日 8:00 享免费额度，平时倍率 0.29x）、**Hy3 限时免费**（0.00x）、**Step-5-Preview 独家限免**（0.00x，有限流标记）。
- `PricingEngine` 新增免费窗口判定：活动日期（含起止当天，Asia/Shanghai）→ 分时窗口（`dailyDiscount` 支持跨午夜 23:00–08:00）→ 下一个「免费开始 / 免费结束 / 限免结束」转换点；活动整体过期后不再倒计时。
- **Mini 省钱灯行免费优先**：免费窗口内该行显示「免费 Hy4 0 倍率 · 08:00 结束」（绿灯），免费结束前提示「23:00 Hy4 免费↓」，均优先于「最省」与 DeepSeek 谷时提示；无障碍标签同步。
- 省钱灯详情页新增「免费额度」区块：徽标、状态、有效期与转换倒计时逐行展示。
- `PricingSelfTest` 补 14 条免费窗口断言（半开区间、跨午夜、过期失效、active 优先级）。

### 推荐口径修正（2026-10-25）

- **积分型账户退出排名**：千问办公、Qoder CN 与 Trae CN 统一按「未定额」展示余额，不进入 `AIUsageAdvisor` 推荐池。修复 Qoder「498 / 498 = 100%」因百分比虚高被推荐第一的问题；套餐百分比只说明这一池用了多少，不代表跨账户可用余量。
- **Mini 省掉弱模型**：`PricingSnapshot` 用能力门槛后的 `recommendations` 取代单一 `activeFreeOffer`。免费额度优先，其次按每百万 token 绝对节省排序；能力分低于 88（DeepSeek Flash 90 基线）的 Hy3（86）不再占用 Mini 推荐位，只在省钱灯页展示。
- **评测数据标定**：`PricingCatalog` / `ModelLeaderboardEngine` 记录 Hy4 preview 94、Step-5-Preview 93、Hy3 86 的依据（Code Arena、Terminal Bench、Artificial Analysis、LMArena、DeepSWE 等公开数据），能力分与模型排行榜同源。
- **Mini 优惠行加长**：第二行最多展示两条强模型优惠（如「免费 Step-5 · 5折 DeepSeek Pro」），超过两条显示「共 N 条」；点行仍进入省钱灯页。行高保持 22 pt，窗口总高度不变。
- **中文口径**：千问办公、Qoder CN、Trae CN 的 `Credits` 全部改为「积分」（余额、后缀、套餐说明、今日用量、详情提示与无障碍文案）。
- 回归补强：`PricingSelfTest` 断言白天/夜间推荐顺序与能力门槛，`UpgradeSelfTest` 增加 Qoder 100% 不参与排名，解析与快照 fixture 同步「积分」后缀。

### Bug 修复（来自当日整体 Bug 检查）

- **Mini 窗口高度不随账户隐藏/显示重算**（B0 本体）：`EnergyPanelController` 新增 `compactAccountsObserver`，`hiddenBalanceIDs` / `balances` 变化即 resize 并保持底边；客户端启停、自动隐藏开关不再造成窗口空白或裁切。
- **Mini 内容恒比窗口高 6pt**：`compactBaseSize` 公式计入账户网格 3pt 上下内边距（`compactGridVerticalPadding = 6`）；此前所有场景上下各裁 3pt，即 10-23 截图「上下边界越过」的根因。
- **源码构建号对齐**：`Resources/Info.plist` 构建号从 77 同步到发布线（本版 82），避免重建时版本倒退。

### 测试链修复

- `scripts/test-reliability.sh` 补编译 `DuMateBalanceClient.swift`（新增百度搭子时脚本漏更）。
- `Tests/ReliabilityTests.swift` 读数总数断言从硬编码 5 改为 `BalanceProvider.allCases.count + 1`（deepseek 单独多刷一次），新增来源不再打破回归。
- 回归全量通过：self-test、test-rpc / balance / reliability / project-usage / mini-layout（121 项）/ dashboard-layout / check-ui-style。

## v1.4.2（构建 81，构建日期 2026-10-24）· 本地构建

未打 tag、未发布。相对 v1.4.1（第 80 版），第 81 版新增 Qoder CN 与 Trae CN 两个账户，账户总数达到九个（Codex + 八个来源）：

### 新增账户

- **Qoder CN**：读取 Electron safe-storage 登录文件 `~/Library/Application Support/com.qodercn.app.stable/auth.v1.dat`（`v10` 头 + AES-128-CBC），密钥由钥匙串条目「Qoder CN App Safe Storage」经 PBKDF2-HMAC-SHA1（`saltysalt`、1003 轮、16 字节）派生；解密在内存中完成，token 不落盘、不外传。
- 额度来自官方 `openapi.qoder.com.cn`：`/api/v2/quota/usage` 汇总套餐 `userQuota` 与附加包 `addOnQuota`，`/api/v2/user/plan` 提供套餐名称与到期日。剩余百分比由 `remaining / total` 自行计算，不采用接口中量级含糊的 `percentage` 字段。
- **Trae CN**：读取客户端全局状态 `~/Library/Application Support/Trae CN/User/globalStorage/storage.json` 的 `iCubeAuthInfo://icube.cloudide`。该值是 base64 的「6 字节头 + 32 字节随机密钥 + 密文」，AES 密钥与 IV 由随机密钥经 SHA-512 与内置掩码派生，全程不需要钥匙串；明文带 64 字节 SHA-512 校验，校验失败即拒绝使用。
- 额度来自 Trae 官方 `api.trae.cn/trae/api/v2/pay/ide_user_ent_usage`：优先采用 `usage_summary` 的总额/已用（与客户端自身显示一致），缺失时逐权益包累加 `quota.credits_limit` 与 `usage.credits_amount`；`credits_limit == -1` 显示「不限」且不伪造百分比，没有权益包时提示重新登录或在客户端领取。
- `sources.json` 新增 `qoder.enabled` 与 `trae.enabled` 开关，默认开启。
- 两个账户都按「本机客户端登录态」接入：客户端未运行时 Mini 条自动隐藏，总览页仍保留并给出恢复提示；换号后今日用量基线随之重置。

### 界面与口径

- `BalanceProvider` 新增 `qoder` / `trae`，余额页、总览、账户页、今日用量、使用建议与本地控制接口自动包含九个账户。
- **账户页切换改三列网格**：九个账户排成三行，标题不再被挤成省略号；Credits 类账户的主数字优先显示余额，百分比只画进度条，避免 100% 盖掉实际余额。
- Mini 条按实际账户数自动增行（九个账户为 3 × 3），默认档窗口高度 320 × 224，其余尺寸档等比放大；快照回归覆盖九账户的多排布局。
- 今日用量页改为三列三行；Qoder / Trae 与千问办公同为 Credits 口径，按余额减少累计今日观测值，身份未确认时显示未知。

### 文档

- README、`docs/使用说明.md`、`docs/隐私与数据.md` 补充 Qoder CN 与 Trae CN 的登录态位置、额度接口与隐私边界。

### 验证

- `CodexPetEnergy --self-test` 通过；`scripts/test-balance.sh`、`test-reliability.sh`、`test-mini-layout.sh`（九账户）、`test-dashboard-layout.sh`、`test-mini-interaction.sh`、`test-project-usage.sh`、`test-rpc.sh`、`check-ui-style.sh` 全部通过。
- 真实读数：Qoder 为「398 Credits · Pro Trial · 至 11月7日」；Trae 为「576.9 Credits · 96% · 每月登录积分 500 · 每日签到 100 · 已用 23.1 / 600 · 至 10月31日」。

## v1.4.1（构建 76 → 80，构建日期 2026-10-24）· 本地构建

未打 tag、未发布。相对 v1.4.0，第 76 版加入 WorkBuddy AI 与多排界面，第 77 版调整透明度，第 78 版加入百度搭子，第 79 版把 Mini 条背景改为半透明，第 80 版修好今日用量页被裁切的问题：

### 新增账户

- **WorkBuddy AI（国际版）**：与国内版并列的独立账户。两者走同一套 WBIPC 本机通道协议，区别只在配置目录——国内版读 `~/.workbuddy`，国际版读 `~/.workbuddy-ai`。应用仍不读取或保存任何 token，只向运行中的客户端查询它自己的订阅积分面板。
- `WorkBuddyBalanceClient` 改为按 provider 参数化，不再硬编码国内版；`BalanceProvider` 新增 `workbuddyintl`。
- `sources.json` 新增 `workbuddyintl.enabled` 开关，默认开启。
- **百度搭子（DuMate）**：读取客户端本机登录态后查询官方积分接口 `api/dumate/points/quota_overview`，返回总积分、已用积分、套餐与赠送包到期时间、模型限流状态。Mini 条与详情页按积分口径展示。
- `DuMateBalanceClient`：登录态解密在内存中完成（`auth.json` 的 `cookies` 为 base64，布局 `iv(12) + tag(16) + 密文`，密钥为同目录 32 字节 `.cookie-key`，AES-256-GCM、无 AAD），Cookie 不落盘、不外传；与豆包一致，只用登录态哈希作为「同一账户」判据，换号后今日用量自动重算基线。
- `sources.json` 新增 `dumate.enabled` 开关，默认开启。

### 界面

- **Mini 条账户区改 3 列多排**：每行 3 个账户，行数按实际显示的账户数自动计算（3 个以内仍是一行），标题和数值不再被截断；窗口高度随之自适应（6 个账户为 320 × 182，7 个为 320 × 240）。
- **浮窗背景更透**：浅色主题的白色叠加从 0.72 降到 0.52，深色从 0.16 降到 0.10，减少对桌面内容的遮挡；开启「降低透明度」辅助功能时仍使用不透明背景。
- **Mini 条背景改半透明**：紧凑条是常驻在桌面上的那一层，改用单独的「瞥视」表面——毛玻璃本身降到 0.78 不透明度，叠加色浅色 0.52 → 0.26、深色 0.10 → 0.04，分隔改由细描边和柔和投影负责，工作时不再挡住背后的内容；展开后的详情页仍用原来的实底，保证密集数字的对比度。开启「降低透明度」辅助功能时两层都不透明。
- 今日用量网格从单行 5 格改为多列多排，容纳 6 个以上账户；总览表按 provider 顺序自动多一行。
- 账户页顶部切换、Mini 条自动隐藏、使用建议标签都识别新账户（积分口径）。
- **修好「今日用量」页底部被裁切**：这一页原先在固定高度的窗口里又套了一层内嵌滚动，「今日各 AI 用量」卡片会把项目列表压到只剩一行、其余被窗口底边切掉。现在改为和其他页签一致的整页滚动；账户网格同时收紧为 4 列（7 个账户两行），展开窗口高度 500 → 540，项目列表能直接看到两三名再滚动。

### 文档

- README 账户列表、今日用量口径与数据来源补充 WorkBuddy AI 与百度搭子。
- `docs/价格与折扣.md` 补充 WorkBuddy AI 积分口径。
- `docs/隐私与数据.md` 补充百度搭子登录态解密说明。

### 验证

- `CodexPetEnergy --self-test` 通过。
- `energyctl status` 返回 7 个账户：`workbuddyintl` 为「350 积分 · Free · 已用 0 / 350」，`dumate` 为「10,612.2 积分 · 套餐 剩 9,959.7 / 10,000 · 至 10月31日 · 赠送包 4 个」。
- 第 79 版：Mini 条窗口 320 × 240，7 个账户全部可见，背景半透明；`--self-test` 通过。
- 第 80 版：展开窗口 420 × 540，今日用量页整页滚动、项目列表不再被裁切；`--self-test` 通过。

## v1.4.0（构建 75，构建日期 2026-10-23，发布日 2026-10-24）· 已公开发布

下载包：`CodexEnergyBar-v1.4.0-macOS-arm64.zip`（本地 ad hoc 签名，未经 Apple 公证）。发布地址：<https://github.com/yidiandianzheng/codex-energy-bar/releases/tag/v1.4.0>。相对上一公开版 v1.3.4：

### 信息架构与页面

- 详情页改为「总览 / 账户 / 今日用量 / 重置雷达」四个页签，汇总在前、账户详情其次；总览四列为账户与状态 / 剩余 / 用量 / 恢复，点任意一行进入该账户详情。
- 账户页顶部在 Codex / DeepSeek / 豆包 / WorkBuddy / 千问办公之间切换，选中账户后展示额度窗口、重置时间与用量细节。
- Mini 紧凑条按需显示：豆包、WorkBuddy、千问办公客户端未运行时自动隐藏，打开后自动出现；「更多」可关闭自动隐藏。

### 账户与余额

- Codex：额度窗口、重置时间与接口提供的重置券信息；重置券只展示、不自动使用。
- DeepSeek：官方 `user/balance` 接口，金额保留人民币原币种。
- 豆包：读取客户端本机登录态后查询会员额度窗口，Cookie 不落盘。
- WorkBuddy：通过客户端本机 IPC 只读查询订阅积分。
- 千问办公：通过客户端本机 MCP 通道（Unix socket）只读查询 Credits 余额；有套餐总额时附剩余百分比，免费版不虚构百分比。
- 读数失败保留上次成功值并标记旧数据；各来源独立刷新、互不影响。

### 今日用量与使用建议

- 今日用量区分口径：Codex 今日本机日志 Token、豆包本时段用量、DeepSeek 今日观测消耗；WorkBuddy 与千问办公无法确认身份或基线时明确显示「今日观测未知」。
- 项目 Token 按上海时区自然日统计本机 `~/.codex/sessions` 与 `archived_sessions`，总量为输入 + 输出，缓存输入与推理输出不重复相加。
- 使用建议由本机规则计算，按各账户最紧的限制窗口判断，不调用外部推荐 API；所有账户都不可用时不指定推荐。

### 重置雷达

- 参考两个免费公开来源（Codex Resets、codex-reset.com），单源有效时自动回退；两源同为未来 24 小时窗口时等权平均。
- 来源预告与预测概率分开显示；预告撤回、重置完成、来源过期或超过预告时刻 2 小时后清除预告与倒计时。
- 主数字优先采用站点公布的承诺信号（commitment signal），节奏模型值仅作参考；接口返回 HTTP 200 错误负载时保留上一份有效数据，不再用空对象覆盖。

### 省钱灯（价格灯）

- Mini 条常驻一行「省钱灯」：显示此刻最省的模型、DeepSeek 峰谷状态与绿灯数量；点这一行进入价格详情。
- 详情页展示各模型/渠道的折算价（含缓存命中价）、峰谷时段、下次变价时间与价格日历；单价按人民币与积分分开列出。
- 价格数据为本地内置、不联网抓价，核对日期 2026-10-23 20:50；超过 30 天未核对时提示「价格待核对」。

### 版本信息与更新日志

- 新增 `AppVersionInfo`：从 App 包读取版本号、构建号与构建日期，统一按 Asia/Shanghai 格式化。
- 标题栏第三行显示版本摘要；「更多 → 关于 算力环」显示完整版本与构建日期；`energyctl status` 增加 `version`、`buildDate` 字段。
- 构建脚本在打包时写入 `CFBundleBuildDate`，可用 `CODEX_PET_ENERGY_BUILD_DATE` 覆盖；布局快照的演示包沿用真实版本信息。
- 新增本更新日志，并在 README、使用说明、UI 设计规范、CLI 文档中补充版本信息的查看位置。
- 变更规模：v1.4.0 主体提交 `da08076` 涉及 88 个文件（+5114 / −559）；省钱灯、千问办公、版本信息与文档随后由提交 `dd70d09` 补齐（54 个文件，+2865 / −130）并据此发布。

### 验证

- `CodexPetEnergy --self-test` 通过（额度解析、余额解析、重置雷达、布局几何、版本信息等套件）。
- `./scripts/check-ui-style.sh`、`./scripts/test-mini-layout.sh`、`./scripts/test-mini-interaction.sh`、`./scripts/test-dashboard-layout.sh` 通过；标题栏版本信息在浅色/深色、长数值、失败与旧值场景下都完整显示。
- `./scripts/test-balance.sh`、`./scripts/test-reliability.sh`、`./scripts/test-project-usage.sh`、`./scripts/test-rpc.sh` 通过。
- 兼容性：macOS 13 及以上 Apple Silicon；Intel 与旧版 macOS 未逐一验证。

## v1.3.4（构建 72，构建日期 2026-10-22）· 已公开发布

- 桌面查看账户额度、今日项目 Token 与双源重置参考；独立浮窗、五档界面大小、额度/项目/雷达详情与本地 CLI。
- 两个免费公开来源：单源有效自动回退，同为 24 小时窗口时等权平均；预测仅供参考，不视为官方确认。
- 会话与项目统计在本机处理，公开截图使用演示数据。
- 下载包：`CodexEnergyBar-v1.3.4-macOS-arm64.zip`（本地 ad hoc 签名，未经 Apple 公证）。
- 发布地址：<https://github.com/yidiandianzheng/codex-energy-bar/releases/tag/v1.3.4>

## 更早版本

- **v1.3.3（第 71 版）**：更名前「Codex 算力条」时期的本地备份，未公开发布。
- **v1.0.0（第 35 版）**：早期本地版本，未公开发布。
- 公开仓库从 v1.3.4 起提供下载；更早版本只存在于本机，不在本文件追溯。

---

维护约定：发布新版本或标记新候选时，在「版本速查」表顶部追加一行，并新增对应小节（新版本在上）；同时更新 `Resources/Info.plist` 的版本号与构建号，以及 README、`docs/使用说明.md` 中的版本说明。
