import Foundation
import Darwin

public actor TraCIConnection {
    private var fd: Int32 = -1
    private let host: String
    private let port: Int

    public init(host: String = "127.0.0.1", port: Int) {
        self.host = host
        self.port = port
    }

    public func connect(retries: Int = 50, retryDelayMS: Int = 100) async throws {
        var lastErr: Int32 = 0
        for _ in 0..<retries {
            if try connectOnce() { return }
            lastErr = errno
            try await Task.sleep(nanoseconds: UInt64(retryDelayMS) * 1_000_000)
        }
        throw TraCIError.statusError(command: 0, message: "connect failed: errno=\(lastErr) \(String(cString: strerror(lastErr)))")
    }

    private func connectOnce() throws -> Bool {
        let s = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard s >= 0 else { throw TraCIError.statusError(command: 0, message: "socket() failed") }

        var on: Int32 = 1
        _ = setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))

        var resolvedAddress = in_addr()
        let resolvedHost = host == "localhost" ? "127.0.0.1" : host
        guard inet_pton(AF_INET, resolvedHost, &resolvedAddress) == 1 else {
            Darwin.close(s)
            throw TraCIError.statusError(command: 0, message: "invalid IPv4 TraCI host: \(host)")
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr = resolvedAddress

        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 {
            Darwin.close(s)
            return false
        }
        self.fd = s
        return true
    }

    public func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    public func send(_ data: Data) throws {
        guard fd >= 0 else { throw TraCIError.notConnected }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(fd, raw.baseAddress!.advanced(by: sent), data.count - sent, 0)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw TraCIError.statusError(command: 0, message: "send: \(String(cString: strerror(errno)))")
                }
                sent += n
            }
        }
    }

    public func receiveMessage() throws -> Data {
        let header = try receiveExact(4)
        var len: UInt32 = 0
        for b in header { len = (len << 8) | UInt32(b) }
        let bodyLen = Int(len) - 4
        guard bodyLen >= 0 else { throw TraCIError.truncated(need: 4, have: 0) }
        if bodyLen == 0 { return Data() }
        return try receiveExact(bodyLen)
    }

    private func receiveExact(_ n: Int) throws -> Data {
        guard fd >= 0 else { throw TraCIError.notConnected }
        var buf = Data(count: n)
        var got = 0
        try buf.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            while got < n {
                let r = recv(fd, raw.baseAddress!.advanced(by: got), n - got, 0)
                if r == 0 { throw TraCIError.truncated(need: n, have: got) }
                if r < 0 {
                    if errno == EINTR { continue }
                    throw TraCIError.statusError(command: 0, message: "recv: \(String(cString: strerror(errno)))")
                }
                got += r
            }
        }
        return buf
    }
}
