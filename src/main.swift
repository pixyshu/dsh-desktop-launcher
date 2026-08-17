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

    // Last window closed → quit → applicationWillTerminate → stop the server
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        dshLog("last window closed → terminate")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        dshLog("applicationWillTerminate → runStopScript")
        runStopScript()
    }

    // MARK: - Menu bar (macOS keyboard shortcuts are driven by menu key equivalents)

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu: ⌘Q quit / ⌘H hide
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About DSH", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide DSH", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit DSH", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu: ⌘C/⌘V/⌘X/⌘A/⌘Z through the responder chain → WKWebView text editing
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")

        // View menu: ⌘R reload
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadPage), keyEquivalent: "r")

        // Window menu: ⌘W close (close = quit = stop server) / ⌘M minimize
        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winItem.submenu = winMenu
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = mainMenu
        dshLog("menu built")
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
                        "<h2>DSH server failed to start</h2><p>See ~/.dsh/web-app-\(self.port).log</p>",
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
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
