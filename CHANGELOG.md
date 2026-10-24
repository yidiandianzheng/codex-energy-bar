# 更新日志

算力环的版本号、构建号、构建日期与改动记录，方便核对正在使用的版本。

- **版本号**：`Resources/Info.plist` 的 `CFBundleShortVersionString`，语义化版本（主.次.修订）。
- **构建号**：`Resources/Info.plist` 的 `CFBundleVersion`，每标记一次新的本地构建递增；当前为第 75 版。
- **构建日期**：打包时由 `scripts/build-app.sh` 写入 `CFBundleBuildDate`（Asia/Shanghai 当天），源码中不写死。
- 应用内查看位置：浮窗展开后的**顶部标题栏第三行**（`v1.4.0 · 第 75 版 · 构建 2026-10-23`）、**更多 → 关于 算力环**、以及 `energyctl status` 返回的 `version` / `build` / `buildDate` 字段。
- 应用包运行时按 App 包内的真实值显示；直接 `swift run` 或快照测试等未打包运行时显示「开发版」，不虚构版本号。

## 版本速查

| 版本 | 构建号 | 构建日期 | 状态 | 摘要 |
| --- | --- | --- | --- | --- |
| v1.4.1 | 76 | 2026-10-24 | 本地构建：未打 tag、未发布 | 新增 WorkBuddy AI（国际版）账户；今日用量改 3 列 2 行 |
| v1.4.0 | 75 | 2026-10-23 | 已公开发布（Apple Silicon），发布日 2026-10-24 | 多账户总览、今日用量、重置雷达；更名「算力环」；新增版本信息与省钱灯 |
| v1.3.4 | 72 | 2026-10-22 | 已公开发布（Apple Silicon） | 双源重置雷达；仓库更名后首个公开版 |

自上一公开版到本版：版本号 +1 个次版本（1.3.4 → 1.4.0）；构建号 +3（72 → 75），即第 73、74、75 版均为 v1.4.0 的构建，其中第 75 版为公开发布版。更早的本地构建（第 35 版、第 71 版）未公开发布、只在本机备份中可见，不在此追溯。

## v1.4.1（构建 76，构建日期 2026-10-24）· 本地构建

未打 tag、未发布。相对 v1.4.0：

### 新增账户

- **WorkBuddy AI（国际版）**：与国内版并列的独立账户。两者走同一套 WBIPC 本机通道协议，区别只在配置目录——国内版读 `~/.workbuddy`，国际版读 `~/.workbuddy-ai`。应用仍不读取或保存任何 token，只向运行中的客户端查询它自己的订阅积分面板。
- `WorkBuddyBalanceClient` 改为按 provider 参数化，不再硬编码国内版；`BalanceProvider` 新增 `workbuddyintl`。
- `sources.json` 新增 `workbuddyintl.enabled` 开关，默认开启。

### 界面

- 今日用量网格从单行 5 格改为 3 列 2 行，容纳 6 个账户；总览表按 provider 顺序自动多一行。
- 账户页顶部切换、Mini 条自动隐藏、使用建议标签都识别新账户（积分口径）。

### 文档

- README 账户列表、今日用量口径与数据来源补充 WorkBuddy AI。
- `docs/价格与折扣.md` 补充 WorkBuddy AI 积分口径。

### 未实现

- **百度搭子（DuMate）**：额度接口已定位（`api/dumate/points/quota_overview`），但登录态由原生模块 `cookie_crypto.node` 加密（`auth.json` 的 `encryptedCookies` + `.cookie-key`），常规 AES-GCM / CBC / ChaCha 组合均无法解密，逆向原生模块成本过高。本版不包含该账户。

### 验证

- `CodexPetEnergy --self-test` 通过。
- `energyctl status` 返回 6 个账户，`workbuddyintl` 状态 `ok`、读数为「350 积分 · Free · 已用 0 / 350」。

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
