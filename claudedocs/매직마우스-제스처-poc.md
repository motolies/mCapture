# 매직마우스 2·3·4 손가락 제스처 PoC 결과

BTT처럼 매직마우스 제스처를 동작에 매핑하려면 손가락 수가 필요하고, 그 유일한 출처는 비공개 `MultitouchSupport.framework`의 접촉 프레임이다. 이 문서는 `poc/magic-mouse-gestures` 브랜치의 `Sources/mtpoc` 실행 타깃으로 **현재 Mac에서 그 프레임이 들어오고 2·3·4 손가락 탭·스와이프가 구분되는지** 실측한 기록이다. 앱에는 넣지 않았다.

| 환경 | 값 |
|---|---|
| macOS | 27.0.1 (26A434), Apple Silicon, Swift 6.4 |
| 매직마우스 | Magic Mouse 2 (ProductID 0x0269), Family ID 112, Bluetooth, 표면 51.5 × 90.6 mm |
| 비교용 | 내장 트랙패드 Family 111, 156 × 96 mm |
| 함께 실행 중 | BetterTouchTool, Karabiner-Elements |

## 실행

```bash
cd /Users/nwkim/git/cap/.claude/worktrees/mt-poc
swift run mtpoc              # 매직마우스만, 제스처 이벤트 출력
swift run mtpoc --raw        # 프레임마다 접촉 좌표·state (걸러진 접촉은 x)
swift run mtpoc --all --pointer   # 모든 장치 + 포인터 이동 기록 (사용자 활동 확인용)
swift run mtpoc --help       # 임계값 플래그
```

이 Mac에는 `timeout`이 없어 정해진 시간만 돌리려면 perl alarm 래퍼를 쓴다 (메모리 `macos-no-timeout-command`).

## 확인된 사실 (2026-10-22)

| 항목 | 결과 | 근거 |
|---|---|---|
| 프레임워크·심볼 | `dlopen` 성공, 필요한 MT 심볼 13개 모두 존재 | `dyld_info -exports`, 실행 로그 |
| 96바이트 접촉 레이아웃 | 이 OS에서도 일치 | 트랙패드 raw에서 앞 두 접촉의 `timestamp − frameTimestamp` = 0.000 (1227프레임 전부) |
| state 값 | 0–7 매핑이 문헌과 동일 | StartInRange → MakeTouch → Touching → BreakTouch → LingerInRange → OutOfRange 순서 관찰 |
| 권한 | 접촉 프레임 수신에 별도 프롬프트 없음. 다만 이 터미널(Warp)은 입력 모니터링이 **이미 허용**돼 있어 "권한 없이도 되는지"는 미확정 | `IOHIDCheckAccess(ListenEvent)` = 허용됨 |
| 트랙패드 인식 | 2손가락 탭(120ms), 2·4손가락 스와이프 4방향, 느린 2손가락 스크롤은 "이동(미분류)"로 분리 | 40초·20분 세션 |
| 매직마우스 열기 | 연결 즉시 `MTDeviceCreateList`에 Family 112로 등장. IORegistry → `MTDeviceCreateFromService` 우회는 필요 없었음 | 실행 로그 |
| 매직마우스 커널 연결 | 마우스 멀티터치 노드에 WindowServer·BetterTouchTool과 나란히 mtpoc의 `AppleMultitouchDeviceUserClient` 생성 | `ioreg -rc AppleMultitouchDevice -l` |
| BTT 공존 | 트랙패드에서는 BTT와 동시에 프레임 수신 | 같은 노드에 두 user client |
| `MTDeviceIsAlive` | 트랙패드·마우스 모두 false → 판단 근거로 쓸 수 없음 | 실행 로그 |
| **매직마우스 프레임** | **미확정.** 기록 창(3분 + 40초 + 20분) 동안 사용자가 마우스를 만지지 않음 | 포인터 이동 168회가 모두 트랙패드 프레임 직후에 발생 |

## 남은 시험 (사용자가 마우스를 쓸 때)

1. `swift run mtpoc --raw`를 띄우고 매직마우스에 손가락 하나를 올린다. 프레임이 흐르면 비공개 API가 매직마우스에서도 살아 있다는 뜻.
2. 2·3·4 손가락 탭, 좌·우·앞·뒤 스와이프를 각각 3회. 이벤트 줄과 mm 값을 보고 `Thresholds`(탭 ≤3mm·≤300ms, 스와이프 ≥8mm, 묶음 150ms)를 조정한다.
3. 평소처럼 쥐고 1손가락 스크롤·클릭·손가락 얹어 두기를 해서 2손가락 이벤트가 새지 않는지 본다.
4. 프레임이 전혀 안 오면 순서대로: BetterTouchTool을 잠시 종료하고 재시도(마우스 쪽만 독점하는지) → `--request-access` → `MTDeviceStart` runMode 변경.

## 설계 메모

- **제스처 = 거의 동시에 닿은 손가락 묶음.** 접촉 수로 세면 얹어 둔 손가락 때문에 창이 닫히지 않는다. 첫 손가락 뒤 150ms 안에 닿은 손가락만 묶고, 1.5초 넘게 눌린 묶음은 쉬는 손가락으로 버린다.
- **분류는 mm 단위.** 정규화 좌표는 가로:세로가 1:1.76이라 우세 축 판정이 가로로 치우친다.
- 쉬는 손가락 필터는 Jitouch 기준(접촉 2개 이상일 때 y<0.3 버림, 가장자리 작은 접촉 버림, size>5.5면 프레임 무시).
- 접촉 메모리는 콜백 동안만 유효해 `loadUnaligned`로 즉시 복사한다. Swift struct로 선언하지 않는다.
- 콜백 → 값 복사 → 직렬 큐 구조는 `FileEventWatcher.swift`와 같다. Swift 6 엄격 모드를 수정 없이 통과했다.
- `stdout`·`stderr` 전역은 Swift 6에서 못 쓰므로 `fflush(nil)`·`FileHandle`로 대신한다.

## 앱에 넣을 때 필요한 것 (PoC 범위 밖)

- 블루투스 재연결·잠자기 복귀 시 장치 재생성 (Jitouch #40: IOService 알림 → `CreateList` 재호출, 1초 간격 3회 재시도)
- 다중 로그인 세션에서 프레임이 끊기는 문제 (MiddleClick 보고, 세션 비활성 시 중지)
- 1손가락 스크롤·OS 2손가락 스와이프와의 공존, 제스처 억제는 불가(관찰만 가능)
- 손쉬운 사용 권한은 동작 쪽(다른 앱에 키 보내기)에서만 필요
