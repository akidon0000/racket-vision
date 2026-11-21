// 球の検出の書き出し（BallFrameExport の JSON）とコートの矩形の記録から、球を 3D に置けた割合と高さを数える（調べるため）。
// BALL_JSON（球の JSON）と COURT_JSON（コートの矩形の記録）を指定したときだけ動く。
import BallTracking
import CoreGraphics
import CourtScene
import Foundation
import Testing

private struct BallPlacementProbeRow: Decodable {
    var seconds: Double
    var imageWidth: Int
    var imageHeight: Int
    var ball: [Double]?
    var radius: Double?
    var rally: Int
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["BALL_JSON"] != nil
        && ProcessInfo.processInfo.environment["COURT_JSON"] != nil))
func probesBallPlacementOnDemoVideo() throws {
    let environment = ProcessInfo.processInfo.environment
    let rows = try JSONDecoder().decode([BallPlacementProbeRow].self, from: Data(contentsOf: URL(fileURLWithPath: environment["BALL_JSON"] ?? "")))
    let courts = try JSONDecoder().decode([[Double]?].self, from: Data(contentsOf: URL(fileURLWithPath: environment["COURT_JSON"] ?? "")))
    var placement = BallPlacement()
    let error = Double(environment["BALL_ERROR"] ?? "") ?? placement.maximumError
    placement.maximumError = error
    if let weight = Double(environment["BALL_DEPTH_WEIGHT"] ?? "") {
        placement.depthWeight = weight
    }
    if let radius = Double(environment["BALL_RADIUS_M"] ?? "") {
        placement.ballRadius = radius
    }
    // BALL_JOIN=0 で、続いている飛行をまとめない。BALL_CONTINUITY と BALL_HEIGHT_WEIGHT で、まとめるときの重さを変える。
    if environment["BALL_JOIN"] == "0" {
        placement.joinsFlights = false
    }
    if let weight = Double(environment["BALL_CONTINUITY"] ?? "") {
        placement.continuityWeight = weight
    }
    if let weight = Double(environment["BALL_HEIGHT_WEIGHT"] ?? "") {
        placement.boundaryHeightWeight = weight
    }
    var total = 0
    var placed = 0
    var heights = [Double]()
    // 弾んだ位置（置いた点で、下がってきて上がり始めるところ）。コートの中（外 0.5 m まで）に落ちるのが自然。
    var bounces = [SIMD3<Double>]()
    // BALL3D_OUT を指定すると、置いた点（時刻、x、y、z、ラリー、写った位置）を JSON に書く（絵にして確かめるため）。
    var exported = [[String: Double]]()
    // ネットを越える高さ（置いた点のうち、ネット（z = 0）をまたぐ 2 点のあいだで、z = 0 での高さ）。
    var netHeights = [Double]()
    // ラリーごとに、軌跡をまとめて置く。
    let rallies = Dictionary(grouping: rows.indices.filter { rows[$0].ball != nil }, by: { rows[$0].rally })
    for indices in rallies.values {
        guard let last = indices.last, last < courts.count, let values = courts[last] else { continue }
        let corners = stride(from: 0, to: values.count, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
        let size = CGSize(width: rows[last].imageWidth, height: rows[last].imageHeight)
        guard let camera = CourtCamera(corners: corners, imageSize: size) else { continue }
        let samples = indices.map { index in
            BallSample(time: rows[index].seconds, center: CGPoint(x: rows[index].ball![0], y: rows[index].ball![1]), radius: CGFloat(rows[index].radius ?? 0), confidence: 1)
        }
        let result = placement.place(samples, camera: camera)
        let points = result.compactMap { $0 }
        for (sample, point) in zip(samples, result) {
            var row = ["t": sample.time, "rally": Double(rows[indices[0]].rally), "u": Double(sample.center.x), "v": Double(sample.center.y)]
            if let point {
                row["x"] = point.x
                row["y"] = point.y
                row["z"] = point.z
            }
            exported.append(row)
        }
        for index in points.indices.dropFirst().dropLast()
        where points[index].y < points[index - 1].y && points[index].y <= points[index + 1].y && points[index].y < 0.5 {
            bounces.append(points[index])
        }
        for (a, b) in zip(points, points.dropFirst()) where a.z * b.z < 0 {
            let t = a.z / (a.z - b.z)
            netHeights.append(a.y + (b.y - a.y) * t)
        }
        total += samples.count
        placed += result.compactMap { $0 }.count
        heights += result.compactMap { $0?.y }
    }
    heights.sort()
    func quantile(_ q: Double) -> Double { heights.isEmpty ? 0 : heights[min(heights.count - 1, Int(Double(heights.count) * q))] }
    print(String(format: "BALL3D error=%.3f placed %d / %d (%.0f%%) height p10 %.2f p50 %.2f p90 %.2f", error, placed, total,
                 Double(placed) / Double(max(1, total)) * 100, quantile(0.1), quantile(0.5), quantile(0.9)))
    netHeights.sort()
    let over = netHeights.filter { (0.86...4.0).contains($0) }.count
    print(String(format: "NET crossings %d, clear 0.86-4.0 m: %d (%.0f%%), median %.2f", netHeights.count, over,
                 Double(over) / Double(max(1, netHeights.count)) * 100, netHeights.isEmpty ? 0 : netHeights[netHeights.count / 2]))
    // ありえない場所（コートの横 2 m より外、後ろ 3 m より外、高さ 5 m より上）に置いた点の割合。
    let points = exported.compactMap { row -> SIMD3<Double>? in
        guard let x = row["x"], let y = row["y"], let z = row["z"] else { return nil }
        return SIMD3(x, y, z)
    }
    let odd = points.filter { abs($0.x) > 3.048 + 2 || abs($0.z) > 6.7056 + 3 || $0.y > 5 }.count
    print(String(format: "ODD %d / %d (%.0f%%)", odd, points.count, Double(odd) / Double(max(1, points.count)) * 100))
    let inside = bounces.filter { abs($0.x) <= 3.048 + 0.5 && abs($0.z) <= 6.7056 + 0.5 }.count
    print(String(format: "BOUNCE %d, in court (+0.5 m): %d (%.0f%%)", bounces.count, inside, Double(inside) / Double(max(1, bounces.count)) * 100))
    if let out = environment["BALL3D_OUT"] {
        try JSONSerialization.data(withJSONObject: exported).write(to: URL(fileURLWithPath: out))
    }
}
