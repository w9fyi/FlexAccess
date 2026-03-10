//
//  CWKeyerView.swift
//  FlexAccess
//
//  Keyboard CW keyer with live decoded text display.
//  VoiceOver-first: decoded text uses a live region so VO announces
//  each new character without stealing focus.
//

import SwiftUI

struct CWKeyerView: View {
    @Bindable var radio: Radio

    @State private var inputText:   String = ""
    @State private var showMacroEditor: Bool = false

    private var keyer:   CWKeyer   { radio.cwKeyer }
    private var decoder: CWDecoder { radio.cwDecoder }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                if radio.connectionStatus != .connected {
                    Text("Connect to a radio to use CW.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {

                // MARK: Keyer settings
                GroupBox("Keyer Settings") {
                    VStack(spacing: 12) {
                        LabeledSlider(label: "Speed",
                                      value: Binding(get: { Double(keyer.speed) },
                                                     set: { keyer.setSpeed(Int($0)) }),
                                      range: Double(FlexProtocol.cwSpeedRange.lowerBound)...Double(FlexProtocol.cwSpeedRange.upperBound),
                                      unit: "WPM",
                                      step: 1)

                        LabeledSlider(label: "Sidetone",
                                      value: Binding(get: { Double(keyer.sidetoneLevel) },
                                                     set: { keyer.setSidetoneLevel(Int($0)) }),
                                      range: Double(FlexProtocol.cwSidetoneRange.lowerBound)...Double(FlexProtocol.cwSidetoneRange.upperBound),
                                      unit: "%",
                                      step: 5)

                        LabeledSlider(label: "Pitch",
                                      value: Binding(get: { Double(keyer.pitch) },
                                                     set: { keyer.setPitch(Int($0)) }),
                                      range: Double(FlexProtocol.cwPitchRange.lowerBound)...Double(FlexProtocol.cwPitchRange.upperBound),
                                      unit: "Hz",
                                      step: 50)
                    }
                    .padding(4)
                }

                // MARK: Keyboard send
                GroupBox("Send") {
                    VStack(spacing: 10) {
                        TextField("Type CW text…", text: $inputText, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("CW send text")
                            .onSubmit { sendInput() }

                        HStack {
                            Button("Send") { sendInput() }
                                .buttonStyle(.borderedProminent)
                                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || keyer.isSending)
                                .keyboardShortcut(.return, modifiers: .command)
                                .accessibilityLabel("Send CW")

                            Button("Abort") { keyer.abort() }
                                .buttonStyle(.bordered)
                                .disabled(!keyer.isSending)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Abort CW transmission")

                            Spacer()

                            if keyer.isSending {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Sending…").font(.caption).foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Sending CW")
                            }
                        }
                    }
                    .padding(4)
                }

                // MARK: Macros
                GroupBox("Macros") {
                    VStack(spacing: 8) {
                        ForEach(keyer.macros.indices, id: \.self) { i in
                            HStack {
                                Button(keyer.macros[i]) {
                                    keyer.send(keyer.macros[i])
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Macro \(i + 1): \(keyer.macros[i])")
                                Spacer()
                            }
                        }
                        Button("Edit Macros…") { showMacroEditor = true }
                            .font(.caption)
                            .sheet(isPresented: $showMacroEditor) {
                                MacroEditorSheet(macros: Bindable(keyer).macros)
                            }
                    }
                    .padding(4)
                }

                // MARK: Decoded receive text
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Decoder active", isOn: Binding(
                                get: { decoder.isActive },
                                set: { $0 ? decoder.start() : decoder.stop() }
                            ))
                            Spacer()
                            Button("Clear") { decoder.clearText() }
                                .font(.caption)
                                .disabled(decoder.decodedText.isEmpty)
                        }

                        ScrollView {
                            Text(decoder.decodedText.isEmpty ? "Decoded text will appear here…" : decoder.decodedText)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(decoder.decodedText.isEmpty ? Color.secondary : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                        .frame(minHeight: 80)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        // Live region: VoiceOver announces new characters without stealing focus
                        .accessibilityLabel("Decoded CW text")
                        .accessibilityValue(decoder.decodedText.isEmpty ? "Empty" : decoder.decodedText)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    .padding(4)
                } label: {
                    Text("Decoded Receive Text")
                }
                } // end else: connected
            }
            .padding()
        }
    }

    private func sendInput() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        keyer.send(text)
        inputText = ""
    }
}

// MARK: - LabeledSlider

private struct LabeledSlider: View {
    let label: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let unit:  String
    let step:  Double

    var body: some View {
        HStack {
            Text(label)
                .frame(minWidth: 70, alignment: .leading)
                .font(.subheadline)
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue)) \(unit)")
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 60, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)")
        .accessibilityValue("\(Int(value.wrappedValue)) \(unit)")
        .accessibilityAdjustableAction { direction in
            let delta = step * (direction == .increment ? 1 : -1)
            value.wrappedValue = Swift.min(Swift.max(value.wrappedValue + delta, range.lowerBound), range.upperBound)
        }
    }
}

// MARK: - Macro editor sheet

private struct MacroEditorSheet: View {
    @Binding var macros: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(macros.indices, id: \.self) { i in
                    TextField("Macro \(i + 1)", text: $macros[i])
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Macro \(i + 1)")
                }
            }
            .navigationTitle("Edit Macros")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
