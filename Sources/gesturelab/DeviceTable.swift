import Foundation
import MCaptureCore

/// 장치 표 출력·선택 (열거는 코어의 MultitouchDeviceEnumerator가 한다)
enum DeviceTable {
    /// 표로 출력한다
    static func show(_ devices: [MultitouchDevice]) {
        Console.line("멀티터치 장치 \(devices.count)개")
        Console.line("번호  Family  종류              내장    DeviceID            표면(mm)      열기")
        for (index, d) in devices.enumerated() {
            let family = String(d.familyID).padding(toLength: 6, withPad: " ", startingAt: 0)
            let name = familyName(d.familyID).padding(toLength: 17, withPad: " ", startingAt: 0)
            let builtIn = (d.builtIn ? "예" : "아니오").padding(toLength: 6, withPad: " ", startingAt: 0)
            let id = String(format: "0x%016llx", d.descriptor.id)
            let size = String(format: "%.1f x %.1f", d.descriptor.surface.widthMM, d.descriptor.surface.heightMM).padding(toLength: 13, withPad: " ", startingAt: 0)
            Console.line("\(index)     \(family)  \(name) \(builtIn)  \(id)  \(size) \(d.origin)")
        }
    }

    /// 옵션에 따라 시작할 장치를 고른다. 기본은 매직마우스만
    static func select(_ devices: [MultitouchDevice], options: Options) -> [MultitouchDevice] {
        if options.all { return devices }
        if let index = options.device { return devices.indices.contains(index) ? [devices[index]] : [] }
        return devices.filter { $0.descriptor.kind == .magicMouse }
    }

    /// 표에 적을 장치 종류 이름. "Magic Mouse"는 재생이 표면 크기를 읽는 열쇠이므로 바꾸지 않는다
    static func familyName(_ id: Int32) -> String {
        switch DeviceFamily.kind(forFamilyID: id) {
        case .magicMouse: "Magic Mouse"
        case .magicTrackpad: "Magic Trackpad"
        case .builtInTrackpad: "내장 트랙패드"
        case .unknown: "알 수 없음"
        }
    }
}
