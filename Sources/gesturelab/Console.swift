import Foundation

/// 줄 단위 출력. stdout·stderr 전역 변수는 Swift 6 엄격 동시성에서 쓸 수 없어 fflush(nil)과 FileHandle로 대신한다
enum Console {
    static func line(_ text: String) {
        print(text)
        fflush(nil)
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
