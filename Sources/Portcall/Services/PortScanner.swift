import Foundation
import Darwin

/// Enumerates listening TCP/UDP sockets directly via libproc (no subprocess).
/// Walks every PID's socket file descriptors and keeps TCP sockets in LISTEN
/// state plus bound, unconnected UDP sockets.
struct PortScanner: Sendable {
    func scan() -> [PortEntry] {
        var results: [PortEntry] = []
        for pid in Libproc.allPIDs() where pid > 0 {
            let fds = Libproc.socketFDs(of: pid)
            guard !fds.isEmpty else { continue }
            let command = Libproc.name(of: pid)
            for fd in fds {
                if let entry = entry(pid: pid, command: command, fd: fd) {
                    results.append(entry)
                }
            }
        }
        return results
    }

    private func entry(pid: pid_t, command: String, fd: Int32) -> PortEntry? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.stride)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, size) > 0 else { return nil }
        let socket = info.psi

        let proto: NetworkProtocol
        let ini: in_sockinfo
        switch Int(socket.soi_kind) {
        case SOCKINFO_TCP:
            let tcp = socket.soi_proto.pri_tcp
            guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { return nil }
            proto = .tcp
            ini = tcp.tcpsi_ini
        case SOCKINFO_IN where socket.soi_protocol == IPPROTO_UDP:
            let udp = socket.soi_proto.pri_in
            guard udp.insi_fport == 0 else { return nil } // skip connected flows
            proto = .udp
            ini = udp
        default:
            return nil
        }

        let port = Self.hostPort(ini.insi_lport)
        guard port != 0 else { return nil } // skip unbound (ephemeral) sockets
        let (family, address) = Self.localAddress(ini)
        return PortEntry(pid: pid, command: command, proto: proto,
                         family: family, address: address, port: port)
    }

    // MARK: - Byte / address decoding

    /// insi_lport carries the port in network byte order in its low 16 bits.
    static func hostPort(_ networkOrder: Int32) -> Int {
        Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: networkOrder)))
    }

    /// Decode the local address into (family, presentation string), choosing the
    /// IPv4/IPv6 union member from the socket's version flag.
    static func localAddress(_ ini: in_sockinfo) -> (family: String, address: String) {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if ini.insi_vflag & 0x1 != 0 { // INI_IPV4
            var addr = ini.insi_laddr.ina_46.i46a_addr4
            inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return ("IPv4", String(cString: buffer))
        } else {
            var addr = ini.insi_laddr.ina_6
            inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return ("IPv6", String(cString: buffer))
        }
    }
}
