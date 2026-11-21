/// 画像の一部（窓）の中で、球の色の画素を、種からつながる限りたどって塊にする。
///
/// 動いた画素は球の縁だけになりやすいので、動いた画素を種にして、色でつながる球の全体を取る。
/// 縦か横が `limit` を超える塊（黄色い服など）は、球ではないので捨てる。
struct BallColorFill {
    private let image: FrameImage
    private let color: BallColor
    private let originX: Int
    private let originY: Int
    private let width: Int
    private let height: Int
    private let limit: Int
    /// 窓の画素ごとの状態。0: まだ見ていない、1: 塊に入れた、2: 大きすぎる塊の一部、3: 球の色でない。
    private var state: [UInt8]
    private var stack = [Int]()
    private var members = [Int]()

    /// `x`・`y`・`width`・`height` は、たどる窓（画像の画素）。画像からはみ出す分は切る。
    init(image: FrameImage, color: BallColor, x: Int, y: Int, width: Int, height: Int, limit: Int) {
        self.image = image
        self.color = color
        originX = max(0, x)
        originY = max(0, y)
        self.width = max(0, min(image.width, x + width) - originX)
        self.height = max(0, min(image.height, y + height) - originY)
        self.limit = limit
        state = [UInt8](repeating: 0, count: self.width * self.height)
    }

    /// 画像の画素 (x, y) から、色の合う画素をたどる。塊にならないとき（窓の外、色が合わない、もう見た、大きすぎる）は nil。
    mutating func blob(atX x: Int, y: Int) -> BallBlob? {
        guard x >= originX, x < originX + width, y >= originY, y < originY + height else { return nil }
        let start = (y - originY) * width + (x - originX)
        guard state[start] == 0 else { return nil }
        guard matches(start) else {
            state[start] = 3
            return nil
        }
        state[start] = 1
        stack.removeAll(keepingCapacity: true)
        members.removeAll(keepingCapacity: true)
        stack.append(start)
        var blob = BallBlob(x: x, y: y)
        var isTooLarge = false
        while let index = stack.popLast() {
            members.append(index)
            blob.add(x: index % width + originX, y: index / width + originY)
            if blob.maxX - blob.minX >= limit || blob.maxY - blob.minY >= limit {
                isTooLarge = true
            }
            // 大きすぎると分かったら、それ以上は広げない。
            if !isTooLarge, pushNeighbors(of: index) {
                isTooLarge = true
            }
        }
        guard !isTooLarge else {
            for member in members {
                state[member] = 2
            }
            return nil
        }
        return blob
    }

    /// まわりの 8 画素のうち、色が合って、まだ見ていない画素を積む。大きすぎる塊の広げ残しにつながっていたら true。
    private mutating func pushNeighbors(of index: Int) -> Bool {
        let localX = index % width
        let localY = index / width
        var touchesTooLarge = false
        for neighborY in max(0, localY - 1)...min(height - 1, localY + 1) {
            for neighborX in max(0, localX - 1)...min(width - 1, localX + 1) {
                let neighbor = neighborY * width + neighborX
                if state[neighbor] == 2 {
                    touchesTooLarge = true
                }
                guard state[neighbor] == 0 else { continue }
                if matches(neighbor) {
                    state[neighbor] = 1
                    stack.append(neighbor)
                } else {
                    state[neighbor] = 3
                }
            }
        }
        return touchesTooLarge
    }

    private func matches(_ local: Int) -> Bool {
        let offset = ((local / width + originY) * image.width + local % width + originX) * 4
        return color.matches(red: image.bytes[offset + 2], green: image.bytes[offset + 1], blue: image.bytes[offset])
    }
}
