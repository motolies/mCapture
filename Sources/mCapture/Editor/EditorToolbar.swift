import MCaptureCore
import SwiftUI

/// 에디터 상단 툴바
struct EditorToolbar: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(EditorState.Tool.allCases) { tool in
                    IconButton(symbol: tool.symbol, help: "\(tool.title) (\(tool.shortcut))", selected: state.tool == tool) {
                        state.canvas?.selectTool(tool)
                    }
                }
            }

            Divider().frame(height: 18)

            // 창이 좁으면 팔레트를 현재 색 버튼 하나로 접고, 누르면 같은 팔레트를 팝오버로 보인다
            ViewThatFits(in: .horizontal) {
                palette
                compactPalette
            }

            Divider().frame(height: 18)

            sizeSlider

            // 툴바 최소 폭이 창 최소 폭이 되므로, 옵션은 같은 폭의 칸에 겹쳐 두고 숨기지 않고 비활성화한다
            ZStack {
                textOptions
                    .disabled(state.toolOptions != .text)
                    .opacity(state.toolOptions == .redact ? 0 : 1)
                redactOptions
                    .disabled(state.toolOptions != .redact)
                    .opacity(state.toolOptions == .redact ? 1 : 0)
            }

            Spacer(minLength: 8)

            // 라벨은 줄어들지 않게 고정해 팔레트가 먼저 접히게 한다
            Text(state.sizeText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            Button(state.zoomText) { state.canvas?.zoomToFit(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
                .help("화면에 맞춤 (⌘1)")

            Divider().frame(height: 18)

            IconButton(symbol: "arrow.uturn.backward", help: "실행 취소 (⌘Z)") { state.canvas?.undo(nil) }
                .disabled(!state.canUndo)
            IconButton(symbol: "arrow.uturn.forward", help: "다시 실행 (⇧⌘Z)") { state.canvas?.redo(nil) }
                .disabled(!state.canRedo)
            IconButton(symbol: "doc.on.doc", help: "복사 (⌘C)") { state.canvas?.copy(nil) }
            IconButton(symbol: "square.and.arrow.down", help: "저장 (⌘S)") { state.canvas?.saveDocument(nil) }
            IconButton(symbol: "pin", help: "화면에 고정 (⌘P)") { state.canvas?.pinToScreen(nil) }
            DragOutButton(prepare: { state.canvas?.prepareDragPayload() }, payload: { state.canvas?.dragPayload() })
                .frame(width: 28, height: 24)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(.bar)
    }

    // 기본 8색 팔레트
    private var palette: some View {
        HStack(spacing: 7) {
            ForEach(RGBAColor.palette, id: \.self) { color in
                ColorSwatch(color: color, selected: state.color == color) {
                    state.canvas?.applyColor(color)
                    state.showsColorPopover = false
                }
            }
        }
    }

    // 접힌 팔레트: 현재 색 버튼
    private var compactPalette: some View {
        ColorSwatch(color: state.color, selected: false) {
            state.showsColorPopover.toggle()
        }
        .popover(isPresented: $state.showsColorPopover, arrowEdge: .bottom) {
            palette.padding(10)
        }
    }

    // 크기 슬라이더와 값. 눈금이 그려지지 않게 step 없이 두고 정수로 반올림한다
    // 끄는 동안의 변경은 실행 취소 한 단계로 묶는다
    private var sizeSlider: some View {
        HStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { Double(state.size.value) },
                    set: { state.canvas?.applySize(AnnotationSize(Int($0.rounded()))) }
                ),
                in: Double(AnnotationSize.range.lowerBound)...Double(AnnotationSize.range.upperBound),
                onEditingChanged: { editing in
                    if editing {
                        state.canvas?.beginSizeEditing()
                    } else {
                        state.canvas?.endSizeEditing()
                    }
                }
            )
            .controlSize(.small)
            .focusable(false)
            .frame(width: 72)
            Text("\(state.size.value)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
        }
        .help("크기 \(state.size.value) — 선 두께·글자·카운터·가리기 강도")
    }

    // 가리기 방식: 픽셀화·블러
    private var redactOptions: some View {
        HStack(spacing: 2) {
            ForEach(RedactMode.allCases, id: \.self) { mode in
                IconButton(symbol: mode.symbol, help: mode.title, selected: state.redactMode == mode) {
                    state.canvas?.applyRedactMode(mode)
                }
            }
        }
    }

    // 텍스트 글꼴 메뉴와 배경 상자 켜기·끄기
    private var textOptions: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(TextFont.allCases, id: \.self) { font in
                    Button {
                        state.canvas?.applyTextFont(font)
                    } label: {
                        if state.textFont == font {
                            Label(font.title, systemImage: "checkmark")
                        } else {
                            Text(font.title)
                        }
                    }
                }
            } label: {
                Text("Aa").font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 24)
            .help("글꼴: \(state.textFont.title)")

            IconButton(symbol: "character.textbox", help: "텍스트 배경", selected: state.textBackground) {
                state.canvas?.applyTextBackground(!state.textBackground)
            }
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ColorSwatch: View {
    let color: RGBAColor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .padding(2)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(color.hex)
    }
}
