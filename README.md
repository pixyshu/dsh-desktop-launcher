# DSH Desktop Launcher

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）变成**单窗口原生 macOS 应用**：双击打开，服务自动启动、窗口直接可用；点红点关窗，服务自动停止。全程无终端、无 Chrome。

> 社区项目，非 DeepSeek 官方产品。核心功能已验证（见文末测试矩阵）。

## 效果

```
双击 DSH.app
 ├─ 检查 3080 端口 → 未运行则后台启动 dsh web（日志 ~/.dsh/web-app-3080.log）
 ├─ 等待服务就绪（最多 60 秒）
 ├─ 原生窗口（WKWebView）加载 http://127.0.0.1:3080
 └─ 点红点关窗 → 应用退出 → 优雅停止服务（只停自己启动的，绝不误杀其他来源的服务）
```

- **只停自己启动的**：如果服务是终端/ChatGPT 等外部启动的，应用会"借用"它；关窗不会误杀（归属标记机制）
- **会话不丢**：服务停启后，会话从磁盘恢复，续聊无缝
- **幂等安全**：重复点击、重复关窗都无害

## 环境依赖

| 依赖 | 要求 | 说明 |
|---|---|---|
| macOS | ≥ 13.0（arm64 与 x86_64 均可） | 仅支持 macOS（Swift + AppKit + WKWebView） |
| Node.js | ≥ 22.19 | **唯一需要手动安装的依赖**（dsh 运行时必需） |
| dsh CLI | 自动处理 | `install.sh` 检测到缺失时自动 `npm i -g @deepseek-ai/dsh`；运行时还有 `DSH_BIN` → PATH → `npx -y @deepseek-ai/dsh` 三级兜底 |
| 构建工具 | Xcode 命令行工具（swiftc） | **仅构建时需要**：`xcode-select --install`；运行不需要 |
| 其他 | 无 | 运行时只使用 macOS 自带的 bash / lsof / curl / nohup，无任何第三方 npm 依赖 |

> 一句话：**只需先装好 Node.js**，其余 `bash install.sh` 全部自动处理。
> 若 Node 不在常见路径（如用 `n` 版本管理器安装），可用环境变量 `DSH_NODE=/path/to/node`、`DSH_BIN=/path/to/dsh` 指定。

## 安装

```bash
git clone https://github.com/pixyshu/dsh-desktop-launcher
cd dsh-desktop-launcher
bash install.sh        # 构建 dist/DSH.app → 装脚本到 ~/.dsh → 复制应用到 ~/Applications
```

然后把 `~/Applications/DSH.app` 拖到程序坞，日常点击即可。

**图标**：仓库不含 DeepSeek 品牌图标。把自己的图标放成 `assets/AppIcon.icns`（1024×1024 的 icns 文件）再构建即可；不提供时自动生成纯色占位图标。

## 工作原理与文件结构

```
DSH.app（Swift 原生应用，无 @main 魔法、显式委托启动）
  │  启动时：DispatchQueue 后台执行 ~/.dsh/start-dsh.sh
  │  窗口关闭：applicationShouldTerminateAfterLastWindowClosed → true
  │  退出时：applicationWillTerminate → ~/.dsh/stop-dsh.sh（同步等待优雅停止）
  ▼
scripts/start-dsh.sh   端口未占用才启动；归属标记 .web-app.<port>.flag；
                       默认端口上自动接管旧版启动器遗留的服务
scripts/stop-dsh.sh    有归属标记才停；按"当前监听进程"停止（不依赖记录 PID）；
                       幂等；处理"关窗时服务还在启动中"的竞态
src/main.swift         单窗口 WKWebView 应用；服务未就绪自动重试加载
```

关键设计取舍：

- **归属标记 > 记录 PID**：进程 PID 会错位（nohup/子进程包装），按端口上的实际监听进程停止最可靠
- **接管只在 3080**：避免隔离端口测试/其他端口上的外部服务被误接管（此 bug 曾被测试抓出并修复）
- **停止脚本幂等 + 竞态兜底**：连点、快速关窗都不会留下孤儿进程

## 配置（环境变量）

| 变量 | 默认 | 用途 |
|---|---|---|
| `DSH_PORT` | 3080 | 服务端口（应用与脚本均支持，主要用于测试隔离） |
| `DSH_BIN` | 自动解析 | dsh 命令路径（`dsh` → PATH → `npx -y @deepseek-ai/dsh`） |
| `DSH_NODE` | 自动解析 | Node 路径（变量 → `n` 版本管理器 → Homebrew/usr-local → PATH） |

## 测试矩阵（隔离端口实测）

| 用例 | 结果 |
|---|---|
| 完整生命周期：启动 → 监听 → 停止 → 端口释放 | ✅ |
| 停止幂等（连续两次 stop 退出 0） | ✅ |
| 借用模式：外部服务不被误接管、不被误杀 | ✅（首测抓出接管越权 bug 并修复） |
| 应用级端到端：应用开 → 服务起 → 应用退 → 服务停 | ✅（调试日志全链路验证） |
| 真实双击路径（open 启动）+ 退出干净 + 主端口零影响 | ✅ |
| 签名有效 / plist 合法 / 图标正确 | ✅ |

## FAQ

- **还需要先装 dsh 吗？** 不需要手动装。唯一需要装的是 Node.js；`install.sh` 会自动全局安装 dsh，运行时还有 npx 兜底（首次启动会下载，较慢，建议装好后先手动开一次）。
- **关窗后服务没停？** 只停"自己启动的"。若服务是外部来源，属预期行为；想在 3080 上接管旧服务，删除 `~/.dsh/.web-app.pid` 残留并重启应用即可。
- **窗口空白/服务起不来？** 看 `~/.dsh/web-app-3080.log` 与 `~/.dsh/dsh-app-debug.log`；多半是 Node/dsh 未找到，用 `DSH_NODE`/`DSH_BIN` 指定。
- **想改窗口大小/标题？** 改 `src/main.swift` 后重新 `bash build.sh`。
- **多开/连点？** macOS 单实例机制自动聚焦已有窗口；停止操作幂等，安全。

## License

[MIT](LICENSE)。DSH 本体为 DeepSeek 的 MIT 项目；本项目不包含其品牌图标。
