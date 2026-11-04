import Foundation
import Testing
@testable import MCaptureCore

struct NetworkTrafficTests {
    @Test func initialIdleAndElapsedTime() {
        var counter = NetworkAccumulator()
        #expect(counter.sample(["en0": NetworkBytes(received: 100, sent: 50)], time: 1) == nil)
        #expect(counter.sample(["en0": NetworkBytes(received: 3100, sent: 1550)], time: 2.5) == NetworkRate(download: 2000, upload: 1000))
        #expect(counter.sample(["en0": NetworkBytes(received: 3100, sent: 1550)], time: 3.5) == NetworkRate())
        #expect(counter.total == NetworkBytes(received: 3000, sent: 1500))
    }
    @Test func multipleInterfacesNewInterfaceAndReset() {
        var counter = NetworkAccumulator()
        _ = counter.sample(["en0": NetworkBytes(received: 100), "en1": NetworkBytes(sent: 200)], time: 0)
        let rate = counter.sample(["en0": NetworkBytes(received: 200), "en1": NetworkBytes(sent: 500), "en2": NetworkBytes(received: 999999)], time: 2)
        #expect(rate == NetworkRate(download: 50, upload: 150))
        let date = Date(timeIntervalSince1970: 1234)
        counter.resetTotals(now: date)
        #expect(counter.total == NetworkBytes()); #expect(counter.startedAt == date)
        #expect(counter.sample(["en0": NetworkBytes(received: 300), "en1": NetworkBytes(sent: 600)], time: 3) == NetworkRate(download: 100, upload: 100))
    }
    @Test func decreaseDisconnectFailureAndWake() {
        var counter = NetworkAccumulator()
        _ = counter.sample(["en0": NetworkBytes(received: 1000)], time: 0)
        #expect(counter.sample(["en0": NetworkBytes(received: 10)], time: 1) == nil)
        #expect(counter.sample(["en0": NetworkBytes(received: 20)], time: 2)?.download == 10)
        #expect(counter.sample(nil, time: 3) == nil)
        #expect(counter.sample(["en0": NetworkBytes(received: 50000)], time: 4) == nil)
        counter.resetBaseline()
        #expect(counter.sample(["en0": NetworkBytes(received: 60000)], time: 5) == nil)
        #expect(counter.sample(["en0": NetworkBytes(received: 90000)], time: 60) == nil)
        _ = counter.sample([:], time: 61)
        #expect(counter.sample([:], time: 62) == NetworkRate())
        #expect(counter.sample(["en0": NetworkBytes(received: 100000)], time: 63) == nil)
        #expect(counter.total.received == 10)
    }
    @Test func networkThresholdUnitsAndBoundaries() {
        let kb = NetworkThreshold(enabled: true, amount: 500, unit: .kilobytes)
        #expect(!kb.exceeds(nil))
        #expect(!kb.exceeds(NetworkRate(download: 499_999, upload: 499_999)))
        #expect(kb.exceeds(NetworkRate(download: 500_000)))
        #expect(kb.exceeds(NetworkRate(upload: 500_000)))
        let mb = NetworkThreshold(enabled: true, amount: 1, unit: .megabytes)
        #expect(!mb.exceeds(NetworkRate(download: 999_999)))
        #expect(mb.exceeds(NetworkRate(download: 1_000_000)))
        #expect(!NetworkThreshold(enabled: false, amount: 1, unit: .kilobytes).exceeds(NetworkRate(download: 1_000_000)))
        #expect(NetworkThreshold(enabled: true, amount: 0, unit: .kilobytes).amount == 1)
        #expect(NetworkThreshold(enabled: true, amount: 1000, unit: .megabytes).amount == 999)
    }

    @Test func unitsAndAxis() {
        #expect(NetworkFormat.menuRate(nil) == "–")
        #expect(NetworkFormat.menuRate(0) == "0KB")
        #expect(NetworkFormat.menuRate(12_300_000) == "12MB")
        #expect(NetworkFormat.menuRate(640_000) == "640KB")
        #expect(NetworkFormat.menuRate(999_499) == "999KB")
        #expect(NetworkFormat.menuRate(999_500) == "1MB")
        #expect(NetworkFormat.menuRate(999_500_000) == "1GB")
        #expect(NetworkFormat.rate(nil) == "–")
        #expect(NetworkFormat.rate(0) == "0 KB/s")
        #expect(NetworkFormat.rate(12_300_000) == "12.3 MB/s")
        #expect(NetworkFormat.rate(640_000) == "640 KB/s")
        #expect(NetworkFormat.rate(999_999) == "1.0 MB/s")
        #expect(NetworkFormat.bytes(.infinity) == "0 KB")
        #expect(NetworkFormat.axis([nil, NetworkRate()]) == 1000)
        #expect(NetworkFormat.axis([NetworkRate(download: 1234, upload: 5200)]) == 6000)
    }
    @Test func nettopParseAndGroup() {
        let batches = NettopParser.parse("""
        ,bytes_in,bytes_out,
        browser.123,1000,100,
        helper.124,50,50,
        ,bytes_in,bytes_out,
        browser.123,5000,200,
        helper.124,2050,150,
        new.125,99999,99999,
        broken,row
        """)
        #expect(batches.count == 2)
        let apps = NetworkAppRanking.rank(previous: batches[0], current: batches[1], interval: 2,
                                          paths: [123: "/A.app/Contents/MacOS/A", 124: "/A.app/Helpers/H.app/H", 125: "/new"])
        #expect(apps.count == 1)
        #expect(apps.first?.path == "/A.app")
        #expect(apps.first?.rate == NetworkRate(download: 3000, upload: 100))
    }
    @Test func pidReuseExitCountersAndEmpty() {
        let old = [NetworkProcessSample(pid: 1, name: "old", bytes: NetworkBytes(received: 100))]
        let reused = [NetworkProcessSample(pid: 1, name: "new", bytes: NetworkBytes(received: 1000))]
        #expect(NetworkAppRanking.rank(previous: old, current: reused, interval: 2, paths: [1: "/new"]).isEmpty)
        #expect(NetworkAppRanking.rank(previous: old, current: old, interval: 2, paths: [:]).isEmpty)
        #expect(NetworkAppRanking.rank(previous: old, current: [], interval: 2, paths: [:]).isEmpty)
        #expect(NettopParser.parse("access denied").isEmpty)
        #expect(NettopParser.parse(",bytes_out,bytes_in,\n\"some,app.12\",42,100,").first?.first?.bytes == NetworkBytes(received: 100, sent: 42))
    }
    @Test func pingResponses() {
        let partial = PingSummary.parse("5 packets transmitted, 3 packets received, 40.0% packet loss\nround-trip min/avg/max/stddev = 1.1/2.2/3.3/0.2 ms")
        #expect(partial?.lossPercent == 40); #expect(partial?.average == 2.2)
        #expect(PingSummary.parse("5 packets transmitted, 0 packets received, 100.0% packet loss")?.received == 0)
        #expect(PingSummary.parse("5 packets transmitted, 5 packets received\nround-trip min/avg/max/stddev = 1/2/3/1 ms")?.lossPercent == 0)
        #expect(PingSummary.parse("invalid") == nil)
    }
}
