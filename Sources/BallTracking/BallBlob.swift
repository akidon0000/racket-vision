/// つながった画素の塊（8 方向でつながるものを 1 つにする）。
struct BallBlob {
    var minX: Int
    var maxX: Int
    var minY: Int
    var maxY: Int
    var count = 0
    var sumX = 0
    var sumY = 0

    private init(x: Int, y: Int) {
        minX = x
        maxX = x
        minY = y
        maxY = y
    }

    private mutating func add(x: Int, y: Int) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
        count += 1
        sumX += x
        sumY += y
    }

    /// `mask` の立っている画素を、塊にまとめる。`seeds` は、立っている画素の番号。`mask` は使い終わると全部倒れる。
    static func collect(from mask: inout [Bool], seeds: [Int], width: Int, height: Int) -> [BallBlob] {
        var blobs = [BallBlob]()
        var stack = [Int]()
        for seed in seeds where mask[seed] {
            mask[seed] = false
            stack.append(seed)
            var blob = BallBlob(x: seed % width, y: seed / width)
            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                blob.add(x: x, y: y)
                for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
                    for neighborX in max(0, x - 1)...min(width - 1, x + 1) where mask[neighborY * width + neighborX] {
                        mask[neighborY * width + neighborX] = false
                        stack.append(neighborY * width + neighborX)
                    }
                }
            }
            blobs.append(blob)
        }
        return blobs
    }
}
