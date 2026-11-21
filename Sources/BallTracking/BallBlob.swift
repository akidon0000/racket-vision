/// つながった画素の塊（8 方向でつながるものを 1 つにする）。座標は画像の画素（左上が原点）。
struct BallBlob {
    var minX: Int
    var maxX: Int
    var minY: Int
    var maxY: Int
    var count = 0
    var sumX = 0
    var sumY = 0

    init(x: Int, y: Int) {
        minX = x
        maxX = x
        minY = y
        maxY = y
    }

    mutating func add(x: Int, y: Int) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
        count += 1
        sumX += x
        sumY += y
    }
}
