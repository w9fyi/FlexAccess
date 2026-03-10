//
//  DiscoveredRadio.swift
//  FlexAccess
//

import Foundation

enum PacketSource: String {
    case local     = "local"
    case smartlink = "smartlink"
    case direct    = "direct"
}

struct DiscoveredRadio: Identifiable, Equatable {
    let id: String          // serial number
    var model: String
    var callsign: String
    var ip: String
    var port: Int
    var version: String
    var source: PacketSource

    // WAN / SmartLink fields
    var publicIp: String      = ""
    var publicTlsPort: Int    = 4994
    var publicUdpPort: Int    = 4993
    var wanConnected: Bool    = false

    var displayName: String {
        callsign.isEmpty ? "\(model) (\(ip))" : "\(callsign) — \(model)"
    }

    static func == (lhs: DiscoveredRadio, rhs: DiscoveredRadio) -> Bool { lhs.id == rhs.id }
}
