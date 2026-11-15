@testable import CourtFit
import CoreGraphics
import Testing

@Test func fillsViewWhenAspectMatches() {
    let mapping = AspectMapping(imageSize: CGSize(width: 100, height: 200), viewSize: CGSize(width: 200, height: 400))

    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 400))
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 1, y: 1)) == CGPoint(x: 200, y: 0))
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 100, y: 200))
}

@Test func fillCropsWidthWhenViewIsWiderThanImage() {
    // 映像は縦長（100x200）、画面は横長（400x200）。横いっぱいに拡大し、上下が切れる。
    let mapping = AspectMapping(imageSize: CGSize(width: 100, height: 200), viewSize: CGSize(width: 400, height: 200), fit: .fill)

    // 拡大率は 4。映像の高さは 800 点になり、上下に 300 点ずつはみ出す。
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 0, y: 1)) == CGPoint(x: 0, y: -300))
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 1, y: 0)) == CGPoint(x: 400, y: 500))
}

@Test func fillCropsHeightWhenViewIsTallerThanImage() {
    // 映像は横長（200x100）、画面は縦長（200x400）。縦いっぱいに拡大し、左右が切れる。
    let mapping = AspectMapping(imageSize: CGSize(width: 200, height: 100), viewSize: CGSize(width: 200, height: 400), fit: .fill)

    // 拡大率は 4。映像の幅は 800 点になり、左右に 300 点ずつはみ出す。
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 0, y: 0)) == CGPoint(x: -300, y: 400))
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 1, y: 1)) == CGPoint(x: 500, y: 0))
}

@Test func fitShowsWholeImageWithLetterbox() {
    // 映像は横長（200x100）、画面は縦長（200x400）。幅に合わせて縮め、上下に余白ができる。
    let mapping = AspectMapping(imageSize: CGSize(width: 200, height: 100), viewSize: CGSize(width: 200, height: 400), fit: .fit)

    // 拡大率は 1。映像の高さは 100 点で、上下に 150 点ずつ余白が入る。
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 250))
    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 1, y: 1)) == CGPoint(x: 200, y: 150))
}

@Test func mapsWholeQuad() {
    let mapping = AspectMapping(imageSize: CGSize(width: 100, height: 100), viewSize: CGSize(width: 100, height: 100))
    let quad = DetectedQuad(
        topLeft: CGPoint(x: 0.1, y: 0.9),
        topRight: CGPoint(x: 0.9, y: 0.9),
        bottomRight: CGPoint(x: 0.9, y: 0.1),
        bottomLeft: CGPoint(x: 0.1, y: 0.1)
    )

    let points = mapping.viewQuad(for: quad)

    #expect(points.count == 4)
    #expect(abs(points[0].x - 10) < 0.0001)
    #expect(abs(points[0].y - 10) < 0.0001)
    #expect(abs(points[2].x - 90) < 0.0001)
    #expect(abs(points[2].y - 90) < 0.0001)
}

@Test func emptyImageMapsToZero() {
    let mapping = AspectMapping(imageSize: .zero, viewSize: CGSize(width: 100, height: 100))

    #expect(mapping.viewPoint(forNormalized: CGPoint(x: 0.5, y: 0.5)) == .zero)
}
