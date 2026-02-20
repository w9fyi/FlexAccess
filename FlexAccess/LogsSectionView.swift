//
//  LogsSectionView.swift
//  FlexAccess
//

import SwiftUI

struct LogsSectionView: View {
    @ObservedObject var radio: FlexRadioState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Logs")
                    .font(.title2)

                // Status summary
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status: \(radio.connectionStatus)")
                    Text("Model:  \(radio.radioModel.isEmpty ? "(unknown)" : radio.radioModel)")
                    Text("FW:     \(radio.firmwareVersion.isEmpty ? "(unknown)" : radio.firmwareVersion)")
                    Text("WAN:    \(radio.isWAN ? "Yes (SmartLink)" : "No (Local)")")
                    if let hz = radio.sliceFrequencyHz {
                        Text(String(format: "Freq:   %.6f MHz", Double(hz) / 1_000_000.0))
                    }
                    Text("Mode:   \(radio.sliceMode.label)")
                    Text("TX:     \(radio.isTX ? "TX" : "RX")")
                    Text("TX:     \(radio.lastTXFrame)")
                    Text("RX:     \(radio.lastRXFrame)")
                }
                .font(.system(.body, design: .monospaced))

                Divider()

                // Connection log
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text("Connection Log")
                            .font(.headline)
                        Button("Clear") { radio.clearConnectionLog() }
                            .disabled(radio.connectionLog.isEmpty)
                        Button("Copy") {
                            let text = radio.connectionLog.joined(separator: "\n")
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            #else
                            UIPasteboard.general.string = text
                            #endif
                        }
                        .disabled(radio.connectionLog.isEmpty)
                    }

                    if radio.connectionLog.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                    } else {
                        List(radio.connectionLog.indices, id: \.self) { i in
                            Text(radio.connectionLog[i])
                                .font(.system(.footnote, design: .monospaced))
                        }
                        .frame(minHeight: 200)
                    }
                }

                Divider()

                // Error log
                VStack(alignment: .leading, spacing: 8) {
                    Text("Errors")
                        .font(.headline)

                    if radio.errorLog.isEmpty {
                        Text("No errors")
                            .foregroundStyle(.secondary)
                    } else {
                        List(radio.errorLog.indices, id: \.self) { i in
                            Text(radio.errorLog[i])
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                        .frame(minHeight: 100)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}
