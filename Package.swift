// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mCapture",
    platforms: [.macOS(.v15)],
    targets: [
        // AppKit에 의존하지 않는 순수 로직 (모델, 좌표 계산, 렌더링)
        .target(
            name: "MCaptureCore",
            path: "Sources/MCaptureCore"
        ),
        // 메뉴바 앱 본체
        .executableTarget(
            name: "mCapture",
            dependencies: ["MCaptureCore"],
            path: "Sources/mCapture"
        ),
        .testTarget(
            name: "MCaptureCoreTests",
            dependencies: ["MCaptureCore"],
            path: "Tests/MCaptureCoreTests"
        ),
    ]
)
