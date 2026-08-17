# Testing

All tests below were executed on isolated ports (e.g. 3995–3999) so a live 3080 session is never touched.

| Case | Result |
|---|---|
| Full lifecycle: start → listener up → stop → port released | ✅ |
| Idempotent stop (run twice, exit 0) | ✅ |
| Borrow mode: foreign server not adopted, never killed | ✅ (first run caught an over-broad adoption bug, since fixed) |
| App-level end-to-end: app launch → server up → app quit → server down | ✅ (verified via debug log chain) |
| Real double-click path (`open`) + clean quit + main port untouched | ✅ |
| Stop latency: ~10s → ~1s | ✅ (fixed a fallback loop that idled for 10s after the server was gone) |
| Code signature valid / plist valid / icon correct | ✅ |

Known limitation: the literal red-button click was verified by real usage (macOS blocks UI scripting without Accessibility permission for the test runner).
