# 本地 CLI

入口：项目中的 `scripts/energyctl`。控制已安装且正在运行的 Codex 算力条；不启动第二个窗口，不修改账户数据，不开放 HTTP/TCP 端口。

```sh
./scripts/energyctl help
./scripts/energyctl status
./scripts/energyctl show radar
./scripts/energyctl show compact
./scripts/energyctl size 2
./scripts/energyctl move 800 500
./scripts/energyctl refresh
./scripts/energyctl hide
```

也可直接调用应用二进制：

```sh
"$HOME/Applications/Codex算力条.app/Contents/MacOS/CodexPetEnergy" --cli status
```

## 命令约定

- `status` 只读，返回 JSON：`schemaVersion`、`build`、`mode`、`visible`、`sizeLevel`、`frame`、`countdownRowVisible`、`refreshing`、`radar`、`quota`。不输出账号令牌、完整本地日志或项目路径。
- `show` 支持 `compact`、`quota`、`projects`、`radar`，显示并切换现有窗口。
- `size 1..5` 使用现有五档字号/尺寸并持久化。
- `move X Y` 指定当前窗口左下角的屏幕逻辑点，原点是主屏左下角；坐标会限制在当前屏幕可见范围，并保存为后续 Mini 恢复位置。应读取返回的实际 `frame`，不能假定请求坐标一定被原样应用。
- `refresh` 仅表示请求刷新当前页，不表示网络同步完成；来源仍有节流间隔。随后用 `status` 检查状态。
- `hide` 隐藏窗口，应用仍在运行；用 `show` 恢复。
- 成功时 `ok: true` 且退出码为 0；错误时返回 `ok: false`、`error`，退出码为 1。未启动应用时明确报错，不自动开启常驻进程。
- CLI 调整窗口尺寸与位置时直接应用，返回实际窗口尺寸；SwiftUI 内容更新由主线程随后完成。

## 给后续 AI 的操作顺序

先 `status` 保存当前 `mode`、`visible`、`sizeLevel` 和 `frame`，再调用需要的命令并回读。检查结束后按需要还原原尺寸、页面、坐标和可见性。使用此入口操作应用，无需模拟鼠标或直接改偏好文件。它控制现有 UI 设置；修改视觉样式、布局代码仍需编辑源码并构建。

通信使用同用户 Unix socket：`~/Library/Caches/CodexPetEnergy/control/app.sock`。目录权限 0700、socket 权限 0600，连接双方检查用户 ID，请求有大小与读写等待限制。服务随应用启动和退出，不创建独立后台任务。

## 倒计时布局

通常 Mini 为 208×62 pt。有有效倒计时时为 208×84 pt：预警行保留概率及北京时间日期、时刻，单独的 22 pt 底行显示倒计时。倒计时失效后自动恢复原高度。`countdownRowVisible` 可用于查询当前状态。

重置雷达参考 Codex Resets（https://codex-resets.com/zh-CN）和 codex-reset.com（https://codex-reset.com/zh/）。一站有效就用这一站；两站有效且均为 24 小时窗口时取等权平均，`radar.averaged` 为 true，`radar.probabilitySource` 为“双源平均”。不同窗口不平均，主数字保留 Codex Resets。

`radar.codexResetsProbability` 和 `radar.codexResetProbability` 分别给出两站当前有效原值；缺失或过期为 null，不填零。两个 URL 字段保留来源归属。`radar.fresh` 仍表示 Codex Resets 状态新鲜；`radar.probabilityFresh` 表示当前选用数值有效，两者相互独立。请求失败可暂留新鲜缓存并列出错误，重试不延长来源有效期。
