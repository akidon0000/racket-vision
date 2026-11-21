import BallTracking
import CourtScene
import Foundation

/// 球の軌跡を、3D に置いた 2 通りの形にする。
///
/// - 計算後（`settled`）: 飛び終わった打球（次の打球が始まったか、最後の点から `settleSeconds` たった打球）を、
///   その打球の全部の点で当てはめた放物線の上に、細かく並べた点。描くのは少し遅れるが、形は変わらない。
/// - リアルタイム（`live`）: 飛んでいる途中の打球を、今ある点だけで当てはめた位置。点が増えるたびに動く。
struct BallTrajectory {
    /// 打球が飛び終わったとみなす、最後の点からの時間（秒）。
    static let settleSeconds = 0.25
    /// 計算後の軌跡に並べる点の間隔（秒）。
    static let step = 1.0 / 60

    var settled: [SIMD3<Double>] = []
    var live: [SIMD3<Double>] = []

    init(samples: [BallSample], camera: CourtCamera, placement: BallPlacement = BallPlacement()) {
        guard let lastTime = samples.last?.time else { return }
        let flights = placement.flights(samples, camera: camera)
        for (index, (range, flight)) in flights.enumerated() {
            let isLast = index == flights.count - 1
            if !isLast || lastTime - flight.endTime >= Self.settleSeconds {
                var time = flight.startTime
                while time <= flight.endTime {
                    settled.append(flight.position(at: time))
                    time += Self.step
                }
            } else {
                live = range.map { flight.position(at: samples[$0].time) }
            }
        }
    }
}
