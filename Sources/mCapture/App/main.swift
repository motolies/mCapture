import AppKit

#if SEARCH_BENCHMARK_APP
// Isolated release validation: no AppDelegate, indexing, settings writes or saved snapshots.
Task { @MainActor in
    await FindFileController.runSearchBenchmark()
    NSApplication.shared.terminate(nil)
}
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
#else
// 메뉴바 상주 앱으로 시작한다. 에디터가 열리면 Dock 아이콘이 나타난다
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

#endif
