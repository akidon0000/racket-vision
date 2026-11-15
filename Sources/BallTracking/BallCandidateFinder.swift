import simd

/// 球の候補（画素の座標、左上が原点）。
struct BallCandidate: Equatable {
    var center: SIMD2<Double>
    var radius: Double
    /// 塊が、囲む四角形をどれだけ埋めているか（0〜1）。円は約 0.79。
    var score: Double
}

/// 動いていて、球の色をしていて、球の大きさの塊を探す。
struct BallCandidateFinder {
    struct Result {
        var candidates: [BallCandidate]
        /// 1 つ前のフレームから動いた画素の割合（0〜1。8 画素おきに数える）。
        var movingRatio: Double
    }

    var color = BallColor.yellowGreen
    /// 球の直径の範囲（映像の幅に対する割合）。
    var diameterRange: ClosedRange<Double> = 0.002...0.02
    /// 動いた画素の割合がこれを超えたら、場面の切り替わりとみなして候補を出さない。
    var sceneChangeRatio = 0.2
    /// 「動いた」とみなす、青・緑・赤の差の合計。
    var differenceThreshold = 45
    /// 塊の長い辺が、短い辺の何倍まで許すか（ぶれて伸びた球を通す）。
    var maximumElongation = 3.0
    /// 塊が、囲む四角形を埋める割合の下限。
    var minimumFill = 0.3

    /// 3 枚は同じ大きさであること。
    func find(current: FrameImage, previous: FrameImage, beforePrevious: FrameImage) -> Result {
        let ratio = movingRatio(current: current, previous: previous)
        guard ratio <= sceneChangeRatio else { return Result(candidates: [], movingRatio: ratio) }
        var mask = [Bool](repeating: false, count: current.width * current.height)
        let seeds = fillMask(&mask, current: current, previous: previous, beforePrevious: beforePrevious)
        let blobs = BallBlob.collect(from: &mask, seeds: seeds, width: current.width, height: current.height)
        return Result(candidates: blobs.compactMap { candidate(from: $0, imageWidth: current.width) }, movingRatio: ratio)
    }

    private func movingRatio(current: FrameImage, previous: FrameImage) -> Double {
        var sampled = 0
        var moved = 0
        current.bytes.withUnsafeBufferPointer { now in
            previous.bytes.withUnsafeBufferPointer { before in
                for y in stride(from: 0, to: current.height, by: 8) {
                    for x in stride(from: 0, to: current.width, by: 8) {
                        sampled += 1
                        if difference(now, before, at: (y * current.width + x) * 4) > differenceThreshold {
                            moved += 1
                        }
                    }
                }
            }
        }
        return sampled == 0 ? 0 : Double(moved) / Double(sampled)
    }

    /// 1 つ前とも 2 つ前とも違い、球の色をしている画素を立てる。立てた画素の番号を返す。
    private func fillMask(_ mask: inout [Bool], current: FrameImage, previous: FrameImage, beforePrevious: FrameImage) -> [Int] {
        var seeds = [Int]()
        current.bytes.withUnsafeBufferPointer { now in
            previous.bytes.withUnsafeBufferPointer { before in
                beforePrevious.bytes.withUnsafeBufferPointer { older in
                    for index in 0..<(current.width * current.height) {
                        let offset = index * 4
                        // 大半の画素は止まっているので、軽い「動き」を先に見る。
                        guard difference(now, before, at: offset) > differenceThreshold,
                              color.matches(red: now[offset + 2], green: now[offset + 1], blue: now[offset]),
                              difference(now, older, at: offset) > differenceThreshold else { continue }
                        mask[index] = true
                        seeds.append(index)
                    }
                }
            }
        }
        return seeds
    }

    private func difference(_ first: UnsafeBufferPointer<UInt8>, _ second: UnsafeBufferPointer<UInt8>, at offset: Int) -> Int {
        abs(Int(first[offset]) - Int(second[offset]))
            + abs(Int(first[offset + 1]) - Int(second[offset + 1]))
            + abs(Int(first[offset + 2]) - Int(second[offset + 2]))
    }

    /// 塊が球の大きさと形なら、候補にする。直径は、ぶれで伸びない短い辺で見る。
    private func candidate(from blob: BallBlob, imageWidth: Int) -> BallCandidate? {
        let width = Double(blob.maxX - blob.minX + 1)
        let height = Double(blob.maxY - blob.minY + 1)
        let short = min(width, height)
        let minimum = max(2, diameterRange.lowerBound * Double(imageWidth))
        let maximum = diameterRange.upperBound * Double(imageWidth)
        let fill = Double(blob.count) / (width * height)
        guard short >= minimum, short <= maximum, max(width, height) <= short * maximumElongation, fill >= minimumFill else {
            return nil
        }
        // 画素の中心は、番号に 0.5 を足した位置。
        let center = SIMD2(Double(blob.sumX) / Double(blob.count) + 0.5, Double(blob.sumY) / Double(blob.count) + 0.5)
        return BallCandidate(center: center, radius: short / 2, score: min(1, fill))
    }
}
