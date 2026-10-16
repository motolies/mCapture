import AppKit

// 메뉴바 상주 앱으로 시작한다. 에디터가 열리면 Dock 아이콘이 나타난다
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
