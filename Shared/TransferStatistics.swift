import Foundation

struct TransferSnapshot {
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let bytesPerSecond: Double?
    let remainingSeconds: Double?
    let isOverall: Bool

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
    }

    var capacityText: String {
        let done = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        guard let totalBytes else { return "\(done) · 總大小未知" }
        return "\(done) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }

    var speedText: String {
        guard let bytesPerSecond else { return "計算中…" }
        if bytesPerSecond <= 0 { return "0 KB/s · 等待資料" }
        return ByteCountFormatter.string(fromByteCount: Int64(min(bytesPerSecond, Double(Int64.max / 2))), countStyle: .file) + "/s"
    }

    var remainingText: String {
        guard let remainingSeconds, remainingSeconds.isFinite, remainingSeconds >= 0,
              remainingSeconds < Double(Int.max / 2) else { return "估算中…" }
        let seconds = Int(ceil(remainingSeconds))
        if seconds == 0 { return "即將完成" }
        if seconds < 60 { return "約 \(seconds) 秒" }
        if seconds < 3600 { return "約 \(seconds / 60) 分 \(seconds % 60) 秒" }
        return "約 \(seconds / 3600) 小時 \((seconds % 3600) / 60) 分"
    }
}

/// A five-second window smooths network bursts. Times use monotonic system uptime.
struct TransferStatistics {
    private struct Sample {
        let time: TimeInterval
        let bytes: Int64
    }
    private var sizes: [Int64?]
    private var index = 0
    private var bytes: Int64 = 0
    private var samples: [Sample]
    private var lastDataAt: TimeInterval
    private var partStartedAt: TimeInterval

    init(expectedSizes: [Int64?], startedAt: TimeInterval) {
        sizes = expectedSizes.map { value in value.flatMap { $0 > 0 ? $0 : nil } }
        samples = [Sample(time: startedAt, bytes: 0)]
        lastDataAt = startedAt
        partStartedAt = startedAt
    }

    mutating func beginPart(_ index: Int, at time: TimeInterval) {
        precondition(sizes.indices.contains(index))
        self.index = index
        bytes = 0
        samples = [Sample(time: time, bytes: 0)]
        lastDataAt = time
        partStartedAt = time
    }

    mutating func record(bytes: Int64, expectedBytes: Int64, at time: TimeInterval) {
        guard sizes.indices.contains(index), time >= (samples.last?.time ?? time), bytes >= self.bytes else { return }
        if expectedBytes > 0 { sizes[index] = max(bytes, expectedBytes) }
        if bytes > self.bytes {
            self.bytes = bytes
            lastDataAt = time
            samples.append(Sample(time: time, bytes: bytes))
            // Retain one sample before the window boundary for a meaningful rate.
            while samples.count > 2 && samples[1].time < time - 5 { samples.removeFirst() }
        }
    }

    mutating func finishPart(bytes: Int64, at time: TimeInterval) {
        record(bytes: bytes, expectedBytes: bytes, at: time)
        if sizes.indices.contains(index) { sizes[index] = max(0, bytes) }
    }

    func snapshot(at time: TimeInterval) -> TransferSnapshot {
        let allSizesKnown = !sizes.isEmpty && sizes.allSatisfy { ($0 ?? 0) > 0 }
        let completed = sizes.prefix(index).reduce(Int64(0)) { $0 + ($1 ?? 0) }
        let total = allSizesKnown ? sizes.reduce(Int64(0)) { $0 + ($1 ?? 0) } : (sizes.indices.contains(index) ? sizes[index] : nil)
        let downloaded = allSizesKnown ? completed + bytes : bytes
        var rate: Double?
        if time - lastDataAt >= 3 {
            rate = 0
        } else if let first = samples.first, let last = samples.last,
                  last.time - first.time >= 0.25, last.bytes > first.bytes {
            rate = Double(last.bytes - first.bytes) / (last.time - first.time)
        } else if time - partStartedAt < 0.25 {
            rate = nil
        }
        let remaining: Double?
        if let total, let rate, rate > 0 {
            remaining = Double(max(0, total - downloaded)) / rate
        } else { remaining = nil }
        return TransferSnapshot(downloadedBytes: downloaded, totalBytes: total, bytesPerSecond: rate,
                                remainingSeconds: remaining, isOverall: allSizesKnown)
    }
}
