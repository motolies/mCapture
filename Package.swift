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
        // 멀티터치 제스처 진단 도구. 터미널에서 `swift run gesturelab`로만 쓰고 앱 번들에는 들어가지 않는다
        .executableTarget(
            name: "gesturelab",
            path: "Sources/gesturelab"
        ),
        .testTarget(
            name: "MCaptureCoreTests",
            dependencies: ["MCaptureCore"],
            path: "Tests/MCaptureCoreTests"
        ),
    ]
)
