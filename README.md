# Codex 算力条

在 Mac 桌面随时查看 Codex 账户剩余额度、今日项目 Token 和额度重置预测。

[下载 v1.3.4（Apple Silicon）](https://github.com/yidiandianzheng/codex-energy-bar/releases/download/v1.3.4/CodexEnergyBar-v1.3.4-macOS-arm64.zip) · [使用说明](docs/使用说明.md) · [反馈问题](https://github.com/yidiandianzheng/codex-energy-bar/issues)

![Codex 算力条紧凑界面，演示数据](docs/images/demo-mini.png)

*截图使用演示数据。*

## 功能

- **账户额度**：读取本机 Codex 返回的真实剩余额度、各窗口重置时间，以及接口提供的重置券信息。
- **今日算力**：按项目统计本机当天 Token，查看输入、输出及缓存、推理子项。
- **重置雷达**：参考两个免费公开来源，自动回退或取双源平均，保留来源和更新时间。
- **桌面浮窗**：拖动定位，点击展开详情，五档尺寸，跟随系统深浅外观；菜单栏图标可显示或隐藏。

## 下载与安装

适用于 **macOS 13 及以上的 Apple Silicon Mac**。Intel 兼容性尚未验证。查看账户额度前，请先在本机 Codex 登录；支持的 Codex 安装位置见[使用说明](docs/使用说明.md#额度读取失败)。

1. 下载上方 ZIP，双击解压。
2. 在 Finder 按 **Shift + Command + G**，输入 `~/Applications` 进入用户“应用程序”文件夹；若不存在，先在个人文件夹中新建 `Applications`。
3. 将 `Codex算力条.app` 拖入该文件夹，双击打开。
4. 若 macOS 因未公证阻止打开，先尝试启动一次，再到“系统设置 → 隐私与安全性”对该应用选择“仍要打开”。

应用也可从系统 `/Applications` 目录运行；仓库中的安装与 CLI 脚本默认使用 `~/Applications/Codex算力条.app`。

下载包使用**本地签名，未经过 Apple 公证**。应用没有 Dock 图标；打开后查看桌面浮窗或菜单栏图标。默认不开机自启，不安装额外后台服务。

## 基本操作

- 点击浮窗的额度、Token 或雷达区域，进入对应页面；按 **Esc** 收起。
- 拖动浮窗移动位置；“更多”中可调整尺寸、恢复默认位置、隐藏或退出。
- 点击菜单栏算力图标显示或隐藏浮窗；刷新按钮只刷新当前页面。

更多操作、异常排查及倒计时规则见[使用说明](docs/使用说明.md)。本地自动化命令见 [CLI 文档](docs/CLI.md)。

## 数据来源与计算

账户额度来自本机 Codex 的 `account/rateLimits/read`。项目 Token 来自 `~/.codex/sessions` 和 `~/.codex/archived_sessions`，按上海时区自然日统计。总量为**输入 + 输出**，缓存输入和推理输出已包含在各自主项中，不重复相加。账户额度百分比与本地 Token 不能直接换算；统计不包含其他电脑的日志。

重置雷达参考 [Codex Resets](https://codex-resets.com/zh-CN) 与 [codex-reset.com](https://codex-reset.com/zh/)，无需会员或 API Key：

- 只有一站数据有效时使用该站；两站数据有效且均为未来 24 小时窗口时，各占 50% 取算术平均。
- 不同预测窗口分别展示，不跨窗口平均；缺失、无效或过期数据不当作 0%。两站数据都要求在 30 分钟内更新。
- 详情保留各站原值、时间和链接。双源平均是本应用计算的参考值，未经概率校准，预测和倒计时均不保证实际重置。

## 隐私

会话日志与项目统计在本机读取和计算，本应用不上传会话内容、项目路径或 Token 统计，也不修改 Codex 会话日志。账户登录与账户请求由本机 Codex 处理。

雷达会请求上述公开网站，向站点发送 IP 地址、应用请求标识等常规网络信息。点击来源链接会在浏览器打开网页。浮窗位置和尺寸保存在本机；所有刷新随应用退出而停止。

## 从源码构建

需要 Git、Swift 6 工具链和 macOS SDK（可通过 Xcode 或 Command Line Tools 提供）。

```bash
git clone https://github.com/yidiandianzheng/codex-energy-bar.git
cd codex-energy-bar
./scripts/build-app.sh
```

脚本输出生成的 `.app` 路径。可用 `CODEX_PET_ENERGY_SDK` 指定 SDK，`CODEX_PET_ENERGY_BUILD_DIR` 指定应用输出目录。内部可执行文件名仍为 `CodexPetEnergy`。

[贡献指南](CONTRIBUTING.md) · [安全问题](SECURITY.md) · [MIT 许可](LICENSE)
