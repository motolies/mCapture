# mCapture
개인용 macOS 스크린샷 캡처·주석 앱.

## 주요 기능 (1단계 MVP + 보완 + 2단계 일상 편의 + 3단계 측정·유틸 + 4단계 파일 찾기 + 5단계 시스템 모니터)
- 멈춘 화면 위에서 영역 선택 (확대경, 크기 표시, 다중 디스플레이), Tab으로 픽셀 색 복사
- 컬러 피커: 메뉴바·⌃⇧6으로 화면에서, 에디터 I 도구로 이미지에서 픽셀 색을 HEX(클릭)·RGB(⇧클릭)로 복사
- 픽셀 자(에디터 M 도구): 커서 아래 요소 간격 자동 표시, 드래그로 두 점 거리 측정
- 파일 찾기(⌃⇧F): Everything·Cling처럼 이름으로 즉시 검색. 퍼지·한글 초성·`ext:`·`folder:`·경로·`regex:`, ↩ 열기·⌘↩ Finder·⌘C 경로 복사. 자체 인덱스 + FSEvents
- 메뉴바 잠자기 방지 토글 (`caffeinate -i`와 같음, 켜지면 아이콘이 초록색)
- 메뉴바 시스템 모니터: CPU 사용률·메모리 압력 두 줄 글자(임계값 넘으면 빨간색), 누르면 iStat식 상세(온도·기록·코어·프로세스·GPU 사용률·메모리·온도·로드 / 압력·내역·프로세스·스왑). 설정에서 표시·임계값
- 창 캡처 (커서 아래 창 강조 → 클릭, 투명 배경, 그림자 선택)
- 텍스트·QR 인식 (한국어+영어, 결과를 클립보드로)
- 캡처 후 자동 복사·저장·에디터 열기
- 에디터: 크롭(핸들로 크기 조절), 사각형·타원·선·화살표·형광펜·텍스트·카운터 주석, 픽셀화·블러 가리기, 실행 취소, 줌·이동
- ⌘V 이미지 붙여넣기, 범위를 끈 뒤 Delete로 범위 안 주석 한꺼번에 지우기
- 화면에 고정(핀, ⌘P), 툴바 손잡이로 다른 앱에 끌어놓기
- 이미지 열기(⇧⌘O, 파일 드롭, Finder에서 PNG "다음으로 열기"), 설정에서 단축키 녹화
- 실행 중에 다시 실행하면 빈 캔버스: 이미지를 끌어다 놓거나 ⌘V로 붙여넣어 바로 편집

앱 아이콘은 `swift scripts/make-icon.swift`로 다시 만들 수 있다.

## 요구 사항
| 항목 | 버전 |
|---|---|
| macOS | 15 이상 |
| Swift | 6.0 이상 (Command Line Tools로 충분, Xcode 불필요) |

## 시작하기

```bash
./scripts/create-signing-identity.sh   # 최초 1회: 서명 인증서 생성
./scripts/build-app.sh                 # build/mCapture-dev.app 생성 (개발 빌드)
open build/mCapture-dev.app
```

첫 캡처 때 화면 기록 권한을 허용한다. 기본 단축키는 영역 ⌃⇧4, 전체 화면 ⌃⇧1, 창 ⌃⇧3, 텍스트 인식 ⌃⇧5, 컬러 피커 ⌃⇧6, 파일 찾기 ⌃⇧F(개발 빌드는 ⌃⌥⇧ + 같은 키). 파일 찾기 인덱스를 처음 만들 때 데스크탑·문서·다운로드 폴더 접근을 허용한다.

### 개발 빌드와 사용 중인 앱

`build-app.sh`는 DMG로 설치해 쓰는 mCapture와 겹치지 않는 **mCapture Dev**를 만든다. 번들 ID(`com.motolies.mcapture.dev`), 설정, URL Scheme(`mcapture-dev://`), 단축키, 저장 폴더(`~/Pictures/mCapture-dev`), 프로세스 이름(`mCaptureDev`)이 모두 달라 두 앱을 함께 띄워 둘 수 있다. 개발 빌드만 끌 때는 `pkill -x mCaptureDev`를 쓴다. 화면 기록 권한은 mCapture Dev에도 한 번 따로 허용한다. 자세한 비교는 [개발 스펙의 개발 빌드 분리](claudedocs/mcapture-개발-스펙.md#개발-빌드-분리)에 있다.

## 테스트

```bash
./scripts/test.sh
```

Command Line Tools 환경에서 `swift test`를 바로 실행하면 Testing 매크로 플러그인 경로가 빠져 성공·실패가 번갈아 나온다. 스크립트가 경로를 보정한다.

## 배포

```bash
./scripts/make-dmg.sh   # build/mCapture-<버전>.dmg 생성
```

배포용 번들 ID(`com.motolies.mcapture`)로 release 빌드한 앱, Applications 바로가기, [설치 안내](docs/설치-안내.md)를 DMG 하나로 묶는다. Apple 공증 없이 배포하므로 받는 사람은 설치 안내의 첫 실행 절차를 거친다. 버전은 `Resources/Info.plist`의 `CFBundleShortVersionString`을 올려서 바꾼다.

배포를 시작한 뒤에는 서명 인증서(`mCapture`)를 바꾸지 않는다. 화면 기록 권한은 인증서 지문에 묶여 있어서, 인증서가 바뀌면 받는 사람 모두 권한을 다시 허용해야 한다. 여러 컴퓨터에서 배포할 때도 모든 컴퓨터가 같은 인증서를 써야 한다.

```bash
./scripts/export-signing-identity.swift            # 인증서 + 개인 키를 암호 건 p12로 백업 (signing/, git 제외)
./scripts/import-signing-identity.sh <백업.p12>     # 다른 컴퓨터에 복원 (같은 이름의 다른 인증서는 확인 후 교체)
```

p12 파일과 암호는 컴퓨터 밖(암호 관리자 등)에 따로 보관한다. 유효 기간·교체·문제 해결은 [서명 인증서 관리](claudedocs/서명-인증서-관리.md)에 있다.

## 문서
- [사용 설명서](claudedocs/USAGE.md) — 기능별 사용법과 단축키
- [개발 스펙](claudedocs/mcapture-개발-스펙.md)
- [서명 인증서 관리](claudedocs/서명-인증서-관리.md) — 생성·유효 기간·백업·복원·교체
