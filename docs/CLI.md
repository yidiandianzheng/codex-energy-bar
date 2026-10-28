# 本地 CLI

入口：项目中的 `scripts/energyctl`。控制已安装且正在运行的算力环；不启动第二个窗口，不修改账户数据，不开放 HTTP/TCP 端口。

```sh
./scripts/energyctl help
./scripts/energyctl status
./scripts/energyctl show radar
./scripts/energyctl show pricing
./scripts/energyctl show balance
./scripts/energyctl show compact
./scripts/energyctl size 2
./scripts/energyctl move 800 500
./scripts/energyctl refresh
./scripts/energyctl hide
```

也可直接调用应用二进制：

```sh
"$HOME/Applications/算力环.app/Contents/MacOS/CodexPetEnergy" --cli status
```

## 命令约定

- `status` 只读，返回 JSON：`schemaVersion`、`version`（版本号，如 `1.5.0`）、`build`（构建号，未打包运行时为 `development`）、`buildDate`（构建日期 `yyyy-MM-dd`，未知为 null）、`mode`、`visible`、`sizeLevel`、`selectedAccount`、`autoHideInactiveAccounts`、`frame`、`countdownRowVisible`、`refreshing`、`nightWatch`、`radar`、`quota`、`balances`、`advice`。`nightWatch` 给出 `active`（AI 通宵是否开启）、`startedAt`（开启时间，Unix 秒；未开启为 null）、`autoStoppedAt` / `autoStopPercent`（最近一次因低电量自动关闭的时间与电量；手动开关会清除）、`notice`（低电量自动关闭提示，约十分钟后消失）。`version` / `build` / `buildDate` 与标题栏第三行、「更多 → 关于 算力环」显示的一致，可用于核对当前构建；完整版本记录见 [CHANGELOG.md](../CHANGELOG.md)。`balances` 每个账户（含 `codex`）给出 `id`、`title`、`state`（ok/loading/unconfigured/failed/stale）以及可用时的 `value`、`caption`、`detail`、`lastSuccessAt`、`lastAttemptAt`；`stale` 可携带上次成功值及状态说明；`hidden` 表示该账户当前是否被 Mini 条自动隐藏（总览页和 `advice` 仍覆盖全部账户）；`autoHideInactiveAccounts` 是 Mini 条「自动隐藏未打开应用的账户」开关的当前值。`advice` 给出本机规则计算的使用建议：`recommended`（账户 id，全部不可用时为 null）、`headline`、`detail`、`compact` 与逐账户 `levels`（充裕/偏紧/告急）。不输出账号令牌、Cookie、完整本地日志或项目路径。
- `show` 支持 `compact`、`quota`、`balance`、`projects`、`radar`、`pricing`，显示并切换现有窗口。`pricing` 打开省钱灯页，与从 Mini 条点击进入同一页面。
- `size 1..5` 使用现有五档界面大小并持久化。
- `move X Y` 指定当前窗口左下角的屏幕逻辑点，原点是主屏左下角；坐标会限制在当前屏幕可见范围，并保存为后续 Mini 恢复位置。应读取返回的实际 `frame`，不能假定请求坐标一定被原样应用。
- `snapshot` 把当前浮窗按当前尺寸渲染为 PNG，写入 `~/Library/Caches/CodexPetEnergy/panel-snapshot.png`，返回 `snapshot` 路径；仅用于开发与样式检查。
- `refresh` 仅表示请求刷新当前页，不表示网络同步完成；来源仍有节流间隔。随后用 `status` 检查状态。
- `hide` 隐藏窗口，应用仍在运行；用 `show` 恢复。
- 成功时 `ok: true` 且退出码为 0；错误时返回 `ok: false`、`error`，退出码为 1。未启动应用时明确报错，不自动开启常驻进程。
- CLI 调整窗口尺寸与位置时直接应用，返回实际窗口尺寸；SwiftUI 内容更新由主线程随后完成。

## 给后续 AI 的操作顺序

先 `status` 保存当前 `mode`、`visible`、`sizeLevel` 和 `frame`，再调用需要的命令并回读。检查结束后按需要还原原尺寸、页面、坐标和可见性。使用此入口操作应用，无需模拟鼠标或直接改偏好文件。它控制现有 UI 设置；修改视觉样式、布局代码仍需编辑源码并构建。

通信使用同用户 Unix socket：`~/Library/Caches/CodexPetEnergy/control/app.sock`。目录权限 0700、socket 权限 0600，连接双方检查用户 ID，请求有大小与读写等待限制。服务随应用启动和退出，不创建独立后台任务。

## 倒计时布局

Mini 宽度固定 320 pt；账户区每行 58 pt（3 列），上下共 6 pt 内边距；底部固定 66 pt，含建议行、雷达行与 AI 通宵行（各 22 pt）；省钱灯行额外 22 pt（默认显示）；有效倒计时再增加 22 pt：预警行显示来源预告或概率及北京时间日期、时刻，单独的 22 pt 底行显示倒计时。倒计时失效后自动恢复原高度。`countdownRowVisible` 可用于查询当前状态。账户被自动隐藏后由剩余账户均分同一行，窗口宽度不变。

AI 通宵行固定占 22 pt，始终显示；点击切换开关，`status` 的 `nightWatch.active` 可核对状态。开启后系统保持唤醒并立即关闭显示器，但应用退出时自动解除；使用电池且电量 ≤15% 时自动关闭，并在 Mini 条提示约十分钟。

重置雷达参考 Codex Resets（https://codex-resets.com/zh-CN）和 codex-reset.com（https://codex-reset.com/zh/）。有效第三方时间预告使 `radar.sourceAnnouncement` 为 true 并显示倒计时。兼容字段 `radar.officialConfirmed` 保留但为 false；时间预告不会自动生成 100% 概率。预告撤回、完成、来源过期或超过预告时刻 2 小时后清除。预测值仍按有效来源计算：一站有效用该站，两站有效且均为 24 小时窗口时等权平均，`radar.averaged` 为 true。不同窗口不平均。

`radar.codexResetsProbability` 和 `radar.codexResetProbability` 分别给出两站当前有效原值；缺失或过期为 null，不填零。两个 URL 字段保留来源归属。`radar.fresh` 仍表示 Codex Resets 状态新鲜；`radar.probabilityFresh` 表示当前选用数值有效，两者相互独立。请求失败可暂留新鲜缓存并列出错误，重试不延长来源有效期。

兼容性：原命令与页面原始标识（`quota`、`balance`、`projects`、`radar`、`compact`）保持不变；Mini 内部账户导航扩展不改变 CLI 的 `show` 参数。`refresh` 遵循当前页及所选账户的刷新范围。
