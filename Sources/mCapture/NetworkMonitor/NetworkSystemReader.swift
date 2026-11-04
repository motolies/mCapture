import Foundation
import SystemConfiguration
import CoreWLAN
import Darwin
import MCaptureCore

struct NetworkConnection: Sendable, Equatable, Identifiable {
    let id: String
    let kind: String
    let addresses: [String]
    let isDefault: Bool
    let wifi: WiFiDetails?
}
struct WiFiDetails: Sendable, Equatable {
    let ssid: String?
    let rssi: Int
    let transmitRate: Double
    let channel: Int
    let band: String
}
struct NetworkConnections: Sendable, Equatable {
    var connections: [NetworkConnection] = []
    var gateway4: String?
    var gateway6: String?
    var primary4: String?
    var primary6: String?
    var dns: [String] = []
    var signature: String {
        connections.map { "\($0.id):\($0.addresses.joined(separator: ",")):\($0.wifi?.ssid ?? "")" }.joined(separator: "|")
        + "\(gateway4 ?? "")|\(gateway6 ?? "")|\(primary4 ?? "")|\(primary6 ?? "")|\(dns)"
    }
    var ipv6Only: Bool { primary4 == nil && primary6 != nil }
    var gateway: String? {
        guard ipv6Only else { return gateway4 }
        guard let gateway6 else { return nil }
        return gateway6.hasPrefix("fe80:" ) && !gateway6.contains("%") ? gateway6 + "%" + (primary6 ?? "") : gateway6
    }
}

enum NetworkSystemReader {
    static func physicalInterfaces() -> [String: String] {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        var result: [String: String] = [:]
        for interface in interfaces {
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else { continue }
            // Virtual Ethernet interfaces have no hardware address. Bridges/AWDL are never traffic sources.
            guard !["awdl", "llw", "bridge", "utun", "lo", "vmenet", "tap", "gif", "stf"].contains(where: name.hasPrefix),
                  SCNetworkInterfaceGetHardwareAddressString(interface) != nil else { continue }
            if type == kSCNetworkInterfaceTypeIEEE80211 as String { result[name] = "Wi-Fi" }
            else if type == kSCNetworkInterfaceTypeEthernet as String { result[name] = "Ethernet" }
            else if type == kSCNetworkInterfaceTypeWWAN as String { result[name] = "WWAN" }
        }
        return result
    }

    static func counters() -> [String: NetworkBytes]? {
        let physical = physicalInterfaces()
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { bytes in
            var offset = 0
            var result: [String: NetworkBytes] = [:]
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length > 0, offset + length <= size else { return nil }
                if Int32(header.ifm_type) == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                    let info = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        if physical[name] != nil, info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_RUNNING != 0 {
                            result[name] = NetworkBytes(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += length
            }
            return result
        }
    }

    static func connections() -> NetworkConnections {
        guard let store = SCDynamicStoreCreate(nil, "mCapture NET" as CFString, nil, nil) else { return NetworkConnections() }
        func value(_ key: String) -> [String: Any] { SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] ?? [:] }
        let ipv4 = value("State:/Network/Global/IPv4"), ipv6 = value("State:/Network/Global/IPv6")
        var result = NetworkConnections()
        result.primary4 = ipv4["PrimaryInterface"] as? String; result.primary6 = ipv6["PrimaryInterface"] as? String
        result.gateway4 = ipv4["Router"] as? String; result.gateway6 = ipv6["Router"] as? String
        result.dns = value("State:/Network/Global/DNS")["ServerAddresses"] as? [String] ?? []
        let physical = physicalInterfaces()
        let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Interface/.*/IPv[46]" as CFString) as? [String] ?? []
        var addresses: [String: [String]] = [:]
        for key in keys {
            let components = key.split(separator: "/")
            guard components.count >= 5 else { continue }
            let name = String(components[3])
            addresses[name, default: []] += value(key)["Addresses"] as? [String] ?? []
        }
        for name in addresses.keys.sorted() {
            guard let ips = addresses[name], !ips.isEmpty else { continue }
            let tunnel = name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")
            guard physical[name] != nil || tunnel else { continue }
            var wifi: WiFiDetails?
            if physical[name] == "Wi-Fi", let interface = CWWiFiClient.shared().interface(withName: name) {
                let channel = interface.wlanChannel()
                let band: String = switch channel?.channelBand {
                case .band2GHz: "2.4 GHz"
                case .band5GHz: "5 GHz"
                case .band6GHz: "6 GHz"
                default: "–"
                }
                wifi = WiFiDetails(ssid: interface.ssid(), rssi: interface.rssiValue(), transmitRate: interface.transmitRate(), channel: channel?.channelNumber ?? 0, band: band)
            }
            result.connections.append(NetworkConnection(id: name, kind: tunnel ? "VPN 터널" : physical[name] ?? name,
                                                        addresses: ips, isDefault: name == result.primary4 || name == result.primary6, wifi: wifi))
        }
        return result
    }

    struct ProcessIdentity: Sendable, Equatable { let path: String; let started: UInt64 }
    static func processIdentities() -> [Int32: ProcessIdentity] {
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [:] }
        var pids = [Int32](repeating: 0, count: Int(size) / 4 + 256)
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * 4))
        guard count > 0 else { return [:] }
        var result: [Int32: ProcessIdentity] = [:]
        for pid in pids.prefix(Int(count) / 4) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            result[pid] = ProcessIdentity(path: String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self),
                                          started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
        }
        return result
    }
}
