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
        buildWindow()
        startServerThenLoad()
        NSApp.activate(ignoringOtherApps: true)
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
