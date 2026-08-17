// DSH.app — DeepSeek Harness 单窗口原生应用（通用发行版）
// 生命周期：启动 → 后台执行 start-dsh.sh → 窗口内加载 http://127.0.0.1:3080
//          最后一个窗口关闭 → 应用退出 → 执行 stop-dsh.sh → 服务停止
// 服务归属判断完全由 ~/.dsh/start-dsh.sh 与 stop-dsh.sh 负责（复用已运行服务、不误杀外部服务）。
// 环境变量：DSH_PORT 覆盖默认端口（调试用）；DSH_HOME 覆盖脚本目录（默认 ~/.dsh）。
import Cocoa
import WebKit

func dshLog(_ s: String) {
    let path = NSHomeDirectory() + "/.dsh/dsh-app-debug.log"
    let line = "[\(Date())] \(s)\n"
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var stopRan = false
    private var readinessAttempts = 0
    private let port = ProcessInfo.processInfo.environment["DSH_PORT"] ?? "3080"
    private let scriptsDir = ProcessInfo.processInfo.environment["DSH_HOME"] ?? (NSHomeDirectory() + "/.dsh")
    private lazy var targetURL = URL(string: "http://127.0.0.1:\(port)/")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        dshLog("applicationDidFinishLaunching (port=\(port))")
        buildMenu()
        buildWindow()
        startServerThenLoad()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 菜单栏（macOS 快捷键依赖菜单项的 keyEquivalent）

    private func buildMenu() {
        let mainMenu = NSMenu()

        // 应用菜单：⌘Q 退出 / ⌘H 隐藏
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 DSH", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 DSH", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 DSH", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 编辑菜单：⌘C/⌘V/⌘X/⌘A/⌘Z 走响应链 → WKWebView 文本编辑
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")

        // 视图菜单：⌘R 刷新
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "刷新", action: #selector(reloadPage), keyEquivalent: "r")

        // 窗口菜单：⌘W 关窗（关窗=退出=停服务）/ ⌘M 最小化
        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "窗口")
        winItem.submenu = winMenu
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = mainMenu
        dshLog("menu built")
    }

    @objc private func reloadPage() {
        webView?.reload()
    }

    // 最后一个窗口关闭 → 应用退出 → applicationWillTerminate → 停止服务
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        dshLog("last window closed → terminate")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        dshLog("applicationWillTerminate → runStopScript")
        runStopScript()
    }

    // MARK: - UI

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        webView = wv

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "DeepSeek Harness"
        win.contentView = wv
        win.minSize = NSSize(width: 800, height: 600)
        win.center()
        win.setFrameAutosaveName("DSHMainWindow")
        win.isReleasedWhenClosed = false
        window = win
        win.makeKeyAndOrderFront(nil)
        dshLog("window created")
    }

    // MARK: - 服务生命周期

    private func startServerThenLoad() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            dshLog("start-dsh.sh launching")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["\(self?.scriptsDir ?? NSHomeDirectory() + "/.dsh")/start-dsh.sh"]
            do {
                try p.run()
            } catch {
                dshLog("Process.run FAILED: \(error)")
            }
            p.waitUntilExit()
            dshLog("start-dsh.sh exited: \(p.terminationStatus)")
            DispatchQueue.main.async { self?.loadWhenReady() }
        }
    }

    private func loadWhenReady() {
        readinessAttempts += 1
        var req = URLRequest(url: targetURL)
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            let ok = (resp as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false
            DispatchQueue.main.async {
                guard let self, let wv = self.webView else { return }
                if ok {
                    wv.load(URLRequest(url: self.targetURL))
                } else if self.readinessAttempts < 60 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.loadWhenReady() }
                } else {
                    wv.loadHTMLString(
                        "<h2>DSH 服务启动失败</h2><p>请查看日志：~/.dsh/web-app-\(self.port).log</p>",
                        baseURL: nil
                    )
                }
            }
        }.resume()
    }

    private func runStopScript() {
        guard !stopRan else { return }
        stopRan = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptsDir + "/stop-dsh.sh"]
        do {
            try p.run()
        } catch {
            dshLog("stop Process.run FAILED: \(error)")
        }
        p.waitUntilExit()  // 等优雅停止完成（最多约 15 秒）再退出进程
        dshLog("stop-dsh.sh exited: \(p.terminationStatus)")
    }
}

// MARK: - 导航失败重试（服务重启窗口期）

extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard readinessAttempts < 120 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.loadWhenReady()
        }
    }
}

// 显式启动结构：不依赖 @main 的委托实例化魔法
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
