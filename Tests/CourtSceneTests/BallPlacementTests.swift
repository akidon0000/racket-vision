import BallTracking
import CoreGraphics
import CourtScene
import simd
import Testing

struct BallPlacementTests {
    private let truth = TestCamera(position: SIMD3(0.5, 5, 10.7), target: SIMD3(0, 0, 0), focalLength: 1500)

    /// 手前から奥へ打った球（30 コマ/秒、0.8 秒）。高さは重力の放物線。
    private func shot() -> [(time: Double, point: SIMD3<Double>)] {
        (0..<24).map { index in
            let time = Double(index) / 30
            let point = SIMD3(-1 + 0.5 * time, 1.0 + 4 * time - 9.81 / 2 * time * time, 5 - 12 * time)
            return (time, point)
        }
    }

    @Test func recoversHeightOfParabolicShot() throws {
        let camera = try #require(CourtCamera(corners: truth.corners, imageSize: truth.imageSize))
        let path = shot()
        let samples = path.map { BallSample(time: $0.time, center: truth.project($0.point), radius: 0.004, confidence: 0.9) }
        let placed = BallPlacement().place(samples, camera: camera)
        #expect(placed.count == samples.count)
        let found = zip(placed, path).compactMap { estimate, actual in estimate.map { ($0, actual.point) } }
        // 端の点は前後がそろわないので出さないことがあるが、真ん中の点は出す。
        #expect(found.count >= 14)
        for (estimate, actual) in found {
            #expect(simd_distance(estimate, actual) < 0.05)
        }
    }

    /// 投げ上げた球の位置（時刻 0 に `start`、速さ `velocity`）。
    private func flight(_ start: SIMD3<Double>, _ velocity: SIMD3<Double>, _ time: Double) -> SIMD3<Double> {
        start + velocity * time + SIMD3(0, -9.81 / 2 * time * time, 0)
    }

    private func samples(_ points: [(Double, SIMD3<Double>)]) -> [BallSample] {
        points.map { BallSample(time: $0.0, center: truth.project($0.1), radius: 0.004, confidence: 0.9) }
    }

    @Test func splitsAtHitAndPlacesBothFlights() throws {
        let camera = try #require(CourtCamera(corners: truth.corners, imageSize: truth.imageSize))
        // 奥へ打った球が、0.4 秒で打ち返され、手前へ戻る。
        let out = SIMD3(-1.0, 1.0, 5.0)
        let hitPoint = flight(out, SIMD3(0.5, 3, -12), 0.4)
        var points = (0...12).map { index -> (Double, SIMD3<Double>) in
            let time = Double(index) / 30
            return (time, flight(out, SIMD3(0.5, 3, -12), time))
        }
        points += (1...12).map { index in
            let time = Double(index) / 30
            return (0.4 + time, flight(hitPoint, SIMD3(1, 2.5, 10), time))
        }
        let placed = BallPlacement().place(samples(points), camera: camera)
        for (estimate, actual) in zip(placed, points) {
            let point = try #require(estimate)
            #expect(simd_distance(point, actual.1) < 0.1)
        }
    }

    @Test func joinedFlightsMeetAtTheHit() throws {
        let camera = try #require(CourtCamera(corners: truth.corners, imageSize: truth.imageSize))
        let out = SIMD3(-1.0, 1.0, 5.0)
        let hitPoint = flight(out, SIMD3(0.5, 3, -12), 0.4)
        var points = (0...12).map { index -> (Double, SIMD3<Double>) in
            (Double(index) / 30, flight(out, SIMD3(0.5, 3, -12), Double(index) / 30))
        }
        points += (1...12).map { index in (0.4 + Double(index) / 30, flight(hitPoint, SIMD3(1, 2.5, 10), Double(index) / 30)) }
        let flights = BallPlacement().flights(samples(points), camera: camera)
        try #require(flights.count == 2)
        // 打った点は、前の飛行の終わりと、次の飛行の始まりで、同じ位置になる。
        let end = flights[0].1.position(at: flights[0].1.endTime)
        let start = flights[1].1.position(at: flights[1].1.startTime)
        #expect(simd_distance(end, start) < 0.02)
        #expect(simd_distance(start, hitPoint) < 0.1)
    }

    @Test func splitsAtBounce() throws {
        let camera = try #require(CourtCamera(corners: truth.corners, imageSize: truth.imageSize))
        // 高さ 1.2 m から落ちて、0.5 秒あたりで弾む（縦の速さが反対になり、少し弱まる）。
        let start = SIMD3(0.5, 1.2, -1.0)
        let velocity = SIMD3(0.2, 0.5, 6.0)
        // 地面に着く時刻: 1.2 + 0.5t - 4.905t² = 0。
        let landing = (0.5 + (0.25 + 4 * 4.905 * 1.2).squareRoot()) / (2 * 4.905)
        let landingPoint = flight(start, velocity, landing)
        let bounceVelocity = SIMD3(0.2, -(0.5 - 9.81 * landing) * 0.7, 5.0)
        var points = stride(from: 0.0, to: landing, by: 1.0 / 30).map { ($0, flight(start, velocity, $0)) }
        points += (1...12).map { index in
            let time = Double(index) / 30
            return (landing + time, flight(landingPoint, bounceVelocity, time))
        }
        let placed = BallPlacement().place(samples(points), camera: camera)
        let found = zip(placed, points).compactMap { estimate, actual in estimate.map { ($0, actual.1) } }
        #expect(found.count >= points.count - 2)
        for (estimate, actual) in found {
            #expect(simd_distance(estimate, actual) < 0.1)
        }
    }

    @Test func ignoresSingleWrongDetection() throws {
        let camera = try #require(CourtCamera(corners: truth.corners, imageSize: truth.imageSize))
        let path = shot()
        var observed = samples(path.map { ($0.time, $0.point) })
        // 10 番目だけ、選手の靴を拾った（映像の幅の 5% ずれた）。
        observed[10].center.x += 0.05
        let placed = BallPlacement().place(observed, camera: camera)
        for (index, estimate) in placed.enumerated() where index != 10 {
            let point = try #require(estimate)
            #expect(simd_distance(point, path[index].point) < 0.05)
        }
    }

    @Test func returnsNothingForTooFewSamples() throws {
        let camera = try #require(CourtCamera(corners: truth.corners, imageSize: truth.imageSize))
        let samples = shot().prefix(3).map { BallSample(time: $0.time, center: truth.project($0.point), radius: 0.004, confidence: 0.9) }
        #expect(BallPlacement().place(Array(samples), camera: camera).allSatisfy { $0 == nil })
    }
}
