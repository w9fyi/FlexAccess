//
//  MorseTable.swift
//  FlexAccess
//
//  ITU Morse code table with encode/decode support.
//

import Foundation

enum MorseTable {

    // MARK: - Table (ITU-R M.1677-1)

    /// Maps Morse code sequence → character.  Public for test coverage checks.
    static let codeToChar: [String: Character] = [
        // Letters
        ".-": "A",   "-...": "B", "-.-.": "C", "-..": "D",
        ".": "E",    "..-.": "F", "--.": "G",  "....": "H",
        "..": "I",   ".---": "J", "-.-": "K",  ".-..": "L",
        "--": "M",   "-.": "N",   "---": "O",  ".--.": "P",
        "--.-": "Q", ".-.": "R",  "...": "S",  "-": "T",
        "..-": "U",  "...-": "V", ".--": "W",  "-..-": "X",
        "-.--": "Y", "--..": "Z",
        // Digits
        "-----": "0", ".----": "1", "..---": "2", "...--": "3",
        "....-": "4", ".....": "5", "-....": "6", "--...": "7",
        "---..": "8", "----.": "9",
        // Punctuation (ITU)
        ".-.-.-": ".", "--..--": ",", "..--..": "?", ".----.": "'",
        "-.-.--": "!", "-..-.": "/",  "-.--.": "(",  "-.--.-": ")",
        ".-...": "&",  "---...": ":", "-.-.-.": ";", "-...-": "=",
        ".-.-.": "+",  "-....-": "-", "..--.-": "_", ".-..-.": "\"",
        "...-..-": "$",".--.-.": "@"
    ]

    private static let charToCode: [Character: String] = {
        Dictionary(uniqueKeysWithValues: codeToChar.map { ($0.value, $0.key) })
    }()

    // MARK: - Public API

    /// Decode a Morse code sequence (e.g. ".-") to its character, or nil if unknown.
    static func decode(_ morse: String) -> Character? {
        codeToChar[morse]
    }

    /// Encode a single character to its Morse code sequence, normalising to uppercase.
    /// Returns nil for characters not in the ITU table.
    static func encode(_ char: Character) -> String? {
        let upper = Character(char.uppercased())
        return charToCode[upper]
    }

    /// Convenience overload accepting a single-character String.
    /// Normalises to uppercase. Returns nil if unknown or empty.
    static func encode(_ str: String) -> String? {
        guard let first = str.uppercased().first else { return nil }
        return charToCode[first]
    }

    /// Encode a full text string to spaced Morse code.
    /// Letters are separated by " ", words by " / ".
    /// Characters not in the table are skipped.
    static func encodeText(_ text: String) -> String {
        text.uppercased()
            .components(separatedBy: " ")
            .map { word in
                word.compactMap { encode($0) }.joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }
}
