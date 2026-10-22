import Foundation

/// 앱의 모든 진입점(메뉴·전역 단축키·URL·제스처)이 실행하는 동작. rawValue는 제스처 바인딩 저장 문자열이라 바꾸지 않는다
enum AppAction: String, CaseIterable, Identifiable {
    case captureArea
    case captureFullscreen
    case captureWindow
    case recognizeText
    case pickColor
    /// 파일 찾기 패널 열기·닫기
    case findFile
    case openImage
    case openSaveFolder
    case showSettings
    case toggleSleepPrevention
    case blankCanvas

    var id: String { rawValue }

    /// 설정·메뉴·동작 선택에 보이는 이름
    var title: String {
        switch self {
        case .captureArea: "영역 캡처"
        case .captureFullscreen: "전체 화면 캡처"
        case .captureWindow: "창 캡처"
        case .recognizeText: "텍스트 인식"
        case .pickColor: "컬러 피커"
        case .findFile: "파일 찾기"
        case .openImage: "이미지 열기"
        case .openSaveFolder: "저장 폴더 열기"
        case .showSettings: "설정 열기"
        case .toggleSleepPrevention: "잠자기 방지 켜기·끄기"
        case .blankCanvas: "빈 캔버스"
        }
    }

    /// 전역 단축키 슬롯. 단축키가 없는 동작은 nil
    var hotkeyAction: HotKeyCenter.Action? {
        HotKeyCenter.Action.allCases.first { $0.appAction == self }
    }
}
