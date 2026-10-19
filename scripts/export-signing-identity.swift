#!/usr/bin/env -S swift -suppress-warnings
// mCapture 서명 인증서(개인 키 포함)를 암호를 건 .p12 파일 하나로 백업한다.
// 사용법: ./scripts/export-signing-identity.swift [출력 경로]
//   출력 경로를 생략하면 signing/mCapture-Dev-<SHA-1 앞 8자리>.p12 (signing/은 git에서 제외된다)
// 키체인이 내보내기를 허락할지 물으면 로그인 암호를 넣는다. 복원은 import-signing-identity.sh가 한다.
// security export는 키체인의 서명 정체성을 모두 내보내므로 Security 프레임워크로 하나만 골라 내보낸다.
// 시험용 MCAPTURE_KEYCHAIN에 쓰는 SecKeychainOpen이 deprecated라 첫 줄에서 컴파일 경고를 끈다.
import CryptoKit
import Foundation
import Security

let environment = ProcessInfo.processInfo.environment
let name = environment["MCAPTURE_SIGN_IDENTITY"] ?? "mCapture"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
// p12 암호는 키 유도가 약한 방식(SHA-1·3DES)이라 길이로 보완한다
let minimumPassphraseLength = 12

/// 오류를 출력하고 끝낸다
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
    exit(1)
}

/// 인증서 DER의 SHA-1 지문 (security find-identity·codesign 요구 사항과 같은 대문자 16진수)
func sha1(of certificate: SecCertificate) -> String {
    let der = SecCertificateCopyData(certificate) as Data
    return Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()
}

/// 이름이 정확히 같은 서명 정체성을 찾는다. MCAPTURE_KEYCHAIN을 주면 그 키체인에서만 찾는다 (시험용)
func findIdentities(named name: String) -> [(identity: SecIdentity, sha1: String)] {
    var query: [CFString: Any] = [
        kSecClass: kSecClassIdentity,
        kSecMatchLimit: kSecMatchLimitAll,
        kSecReturnRef: true,
    ]
    if let path = environment["MCAPTURE_KEYCHAIN"] {
        var keychain: SecKeychain?
        guard SecKeychainOpen(path, &keychain) == errSecSuccess, let keychain else {
            fail("키체인을 열 수 없습니다: \(path)")
        }
        query[kSecMatchSearchList] = [keychain]
    }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess, let items = result as? [SecIdentity] else {
        fail("키체인 조회 실패: \(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")")
    }
    var found: [(SecIdentity, String)] = []
    for identity in items {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
              SecCertificateCopySubjectSummary(certificate) as String? == name else { continue }
        found.append((identity, sha1(of: certificate)))
    }
    // 키체인 목록에 같은 항목이 겹쳐 나올 수 있어 지문으로 한 번 더 거른다
    var seen = Set<String>()
    return found.filter { seen.insert($0.1).inserted }
}

/// 터미널에서 화면에 보이지 않게 암호를 읽는다 (터미널이 없으면 표준 입력에서 읽는다)
func readPassphrase(_ prompt: String) -> String {
    guard let raw = getpass(prompt) else { fail("암호를 읽지 못했습니다.") }
    return String(cString: raw)
}

let matches = findIdentities(named: name)
guard matches.count == 1, let match = matches.first else {
    if matches.isEmpty {
        fail("'\(name)' 서명 인증서가 키체인에 없습니다.")
    }
    let list = matches.map { "   \($0.sha1)" }.joined(separator: "\n")
    fail("'\(name)' 인증서가 여러 개입니다. 하나만 남긴 뒤 다시 실행하세요.\n\(list)")
}

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("signing/\(name.replacingOccurrences(of: " ", with: "-"))-\(match.sha1.prefix(8)).p12")
if FileManager.default.fileExists(atPath: output.path) {
    fail("이미 파일이 있습니다: \(output.path)")
}

print("내보낼 인증서: \(name) (SHA-1 \(match.sha1))")
let passphrase = readPassphrase("p12 암호 (\(minimumPassphraseLength)자 이상): ")
guard passphrase.count >= minimumPassphraseLength else {
    fail("암호는 \(minimumPassphraseLength)자 이상이어야 합니다.")
}
guard readPassphrase("p12 암호 확인: ") == passphrase else { fail("두 암호가 다릅니다.") }

// 키체인이 이 프로세스에 개인 키 내보내기를 허락할지 묻는 창이 뜰 수 있다
let passphraseRef = passphrase as CFString
var parameters = SecItemImportExportKeyParameters()
parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
parameters.passphrase = Unmanaged.passUnretained(passphraseRef)
var exported: CFData?
let status = SecItemExport(match.identity, .formatPKCS12, [], &parameters, &exported)
guard status == errSecSuccess, let exported else {
    fail("내보내기 실패: \(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")")
}

// 개인 키가 든 파일이라 폴더는 700, 파일은 600으로 둔다
let directory = output.deletingLastPathComponent()
try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
guard FileManager.default.createFile(
    atPath: output.path, contents: exported as Data, attributes: [.posixPermissions: 0o600]) else {
    fail("파일을 쓰지 못했습니다: \(output.path)")
}

print("✅ \(output.path)")
print("   이 파일과 암호를 컴퓨터 밖(암호 관리자 등)에 따로 보관하세요.")
