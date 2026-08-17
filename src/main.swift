// DSH.app — DeepSeek Harness as a native single-window macOS app.
// Lifecycle: on launch, run start-dsh.sh in the background and load http://127.0.0.1:3080;
//            when the last window closes, the app quits and runs stop-dsh.sh.
// Server ownership is handled entirely by ~/.dsh/start-dsh.sh and stop-dsh.sh
// (running servers are reused; foreign servers are never killed).
// Environment: DSH_PORT overrides the port (debugging); DSH_HOME overrides the scripts dir (default ~/.dsh).
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

/// Reads locale.preference from ~/.dsh/settings.yaml ("en", "zh", or nil when unset).
func storedLocalePreference() -> String? {
    let path = NSHomeDirectory() + "/.dsh/settings.yaml"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    var inLocale = false
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("locale:") { inLocale = true; continue }
        if inLocale {
            if !line.hasPrefix(" ") && !line.isEmpty { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("preference:") {
                let value = trimmed.dropFirst("preference:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
    }
    return nil
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
        // Hidden snapshot hook (used to generate the README screenshot):
        // DSH_SNAPSHOT=/path.png renders the web view to a PNG and quits.
        if let snapPath = ProcessInfo.processInfo.environment["DSH_SNAPSHOT"] {
            scheduleSnapshot(to: snapPath)
        }
        // Hidden test hook: DSH_SET_LOCALE=en|zh|system writes the locale preference at launch.
        if let loc = ProcessInfo.processInfo.environment["DSH_SET_LOCALE"] {
            writeLocalePreference(loc == "system" ? nil : loc)
        }
        // Hidden test hook: DSH_DUMP_MENU=1 logs every visible menu title built (verifies localization).
        if ProcessInfo.processInfo.environment["DSH_DUMP_MENU"] != nil {
            dumpMenu()
        }
        // Hidden test hook: DSH_TEST_CLOSE_WINDOW=1 performs a real window close after 10s
        // (verifies the app and server keep running after the red button).
        if ProcessInfo.processInfo.environment["DSH_TEST_CLOSE_WINDOW"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.window?.performClose(nil)
                dshLog("test: performClose triggered")
            }
        }
    }

    private func dumpMenu() {
        guard let main = NSApp.mainMenu else { dshLog("dumpMenu: no main menu"); return }
        for (i, top) in main.items.enumerated() {
            var line = "menu[\(i)] top=\(top.title)"
            if let sub = top.submenu {
                let titles = sub.items.map { $0.isSeparatorItem ? "—" : $0.title }
                line += " → " + titles.joined(separator: " | ")
            }
            dshLog(line)
        }
    }

    // MARK: - Language switching (writes locale.preference in ~/.dsh/settings.yaml;
    // the host watches that file and the web UI re-renders via the locale/change event)

    private func currentLocalePreference() -> String? {
        storedLocalePreference()
    }

    private func writeLocalePreference(_ pref: String?) {
        let path = NSHomeDirectory() + "/.dsh/settings.yaml"
        let fm = FileManager.default
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        // Drop any existing top-level `locale:` block (everything else is preserved verbatim)
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("locale:") {
                i += 1
                while i < lines.count && (lines[i].hasPrefix(" ") || lines[i].isEmpty) { i += 1 }
                continue
            }
            out.append(line)
            i += 1
        }
        var result = out.joined(separator: "\n")
        while result.hasSuffix("\n") { result.removeLast() }

        if let pref = pref, !pref.isEmpty {
            result += (result.isEmpty ? "" : "\n") + "locale:\n  preference: \(pref)\n"
        }

        // Atomic replace — the host watches this file and reloads on change
        let tmp = path + ".dsh-tmp"
        try? result.write(toFile: tmp, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp)
        try? fm.removeItem(atPath: path)
        try? fm.moveItem(atPath: tmp, toPath: path)
        dshLog("locale preference → \(pref ?? "system default")")
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1: writeLocalePreference("zh")
        case 2: writeLocalePreference(nil)
        default: writeLocalePreference("en")
        }
        buildMenu()  // rebuild so checkmarks reflect the new selection
    }

    private func scheduleSnapshot(to path: String) {
        dshLog("snapshot mode → \(path)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, let wv = self.webView else { exit(1) }
            let config = WKSnapshotConfiguration()
            config.rect = wv.bounds
            wv.takeSnapshot(with: config) { image, error in
                if let image = image,
                   let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                    dshLog("snapshot written")
                } else {
                    dshLog("snapshot failed: \(String(describing: error))")
                }
                NSApp.terminate(nil)
            }
        }
    }

    // Red close button (or ⌘W) only closes the window; the app and the server
    // keep running. Quit via ⌘Q / Dock → Quit stops the server (applicationWillTerminate).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        dshLog("window closed — app stays running")
        return false
    }

    // Clicking the Dock icon reopens the window (same web view state).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let win = window {
                win.makeKeyAndOrderFront(nil)
                dshLog("reopened window from Dock")
            } else {
                buildWindow()
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        dshLog("applicationWillTerminate → runStopScript")
        runStopScript()
    }

    // MARK: - Menu bar (macOS keyboard shortcuts are driven by menu key equivalents)
    // All visible strings follow the current locale preference (zh/en), like the web UI.

    private func uiLang() -> String {
        if let p = currentLocalePreference() { return p }
        let langs = UserDefaults.standard.object(forKey: "AppleLanguages") as? [String] ?? []
        return (langs.first ?? "en").lowercased().hasPrefix("zh") ? "zh" : "en"
    }

    private func tr(_ s: String) -> String {
        guard uiLang() == "zh" else { return s }
        let zh: [String: String] = [
            "About DSH": "关于 DSH",
            "Hide DSH": "隐藏 DSH",
            "Quit DSH": "退出 DSH",
            "Edit": "编辑",
            "Undo": "撤销",
            "Redo": "重做",
            "Cut": "剪切",
            "Copy": "拷贝",
            "Paste": "粘贴",
            "Select All": "全选",
            "View": "视图",
            "Reload": "刷新",
            "Window": "窗口",
            "Minimize": "最小化",
            "Close Window": "关闭窗口",
            "Language": "语言",
            "System Default": "跟随系统",
            "DSH server failed to start": "DSH 服务启动失败",
            "See the log": "请查看日志",
        ]
        return zh[s] ?? s
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu: ⌘Q quit / ⌘H hide
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: tr("About DSH"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: tr("Hide DSH"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: tr("Quit DSH"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu: ⌘C/⌘V/⌘X/⌘A/⌘Z through the responder chain → WKWebView text editing
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: tr("Edit"))
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: tr("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: tr("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: tr("Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: tr("Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: tr("Select All"), action: Selector(("selectAll:")), keyEquivalent: "a")

        // View menu: ⌘R reload
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: tr("View"))
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: tr("Reload"), action: #selector(reloadPage), keyEquivalent: "r")

        // Window menu: ⌘W close (close = quit = stop server) / ⌘M minimize
        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: tr("Window"))
        winItem.submenu = winMenu
        winMenu.addItem(withTitle: tr("Minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: tr("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = winMenu

        // Language menu: English / 中文 / System default (applies live via the host settings watcher)
        let langItem = NSMenuItem()
        mainMenu.addItem(langItem)
        let langMenu = NSMenu(title: tr("Language"))
        langItem.submenu = langMenu
        let current = currentLocalePreference()
        let enItem = NSMenuItem(title: "English", action: #selector(setLanguage(_:)), keyEquivalent: "")
        enItem.tag = 0
        enItem.state = current == "en" ? .on : .off
        let zhItem = NSMenuItem(title: "中文", action: #selector(setLanguage(_:)), keyEquivalent: "")
        zhItem.tag = 1
        zhItem.state = current == "zh" ? .on : .off
        let sysItem = NSMenuItem(title: tr("System Default"), action: #selector(setLanguage(_:)), keyEquivalent: "")
        sysItem.tag = 2
        sysItem.state = current == nil ? .on : .off
        langMenu.addItem(enItem)
        langMenu.addItem(zhItem)
        langMenu.addItem(NSMenuItem.separator())
        langMenu.addItem(sysItem)

        NSApp.mainMenu = mainMenu
        dshLog("menu built (lang=\(uiLang()))")
    }

    @objc private func reloadPage() {
        webView?.reload()
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

    // MARK: - Server lifecycle

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
                        "<h2>\(self.tr("DSH server failed to start"))</h2><p>\(self.tr("See the log")): ~/.dsh/web-app-\(self.port).log</p>",
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
        p.waitUntilExit()  // wait for graceful stop (up to ~5s) before exiting
        dshLog("stop-dsh.sh exited: \(p.terminationStatus)")
    }
}

// MARK: - Retry on navigation failure (server restart window)

extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard readinessAttempts < 120 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.loadWhenReady()
        }
    }
}

// Explicit startup: no @main delegate-instantiation magic
// Apply the persisted locale before AppKit boots so system-injected menu items
// (Emoji & Symbols, Close All, …) follow the chosen language too.
if let pref = storedLocalePreference() {
    UserDefaults.standard.set([pref == "zh" ? "zh-Hans" : "en"], forKey: "AppleLanguages")
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
