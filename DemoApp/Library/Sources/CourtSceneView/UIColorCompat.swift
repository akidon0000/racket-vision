#if canImport(UIKit)
import UIKit

/// RealityKit の色（iOS は UIColor、macOS は NSColor）を、同じ書き方で作る。
enum UIColorCompat {
    static func white(_ white: Double, alpha: Double = 1) -> UIColor {
        UIColor(white: white, alpha: alpha)
    }

    static func rgb(_ rgb: SIMD3<Double>, alpha: Double) -> UIColor {
        UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: alpha)
    }
}
#else
import AppKit

/// RealityKit の色（iOS は UIColor、macOS は NSColor）を、同じ書き方で作る。
enum UIColorCompat {
    static func white(_ white: Double, alpha: Double = 1) -> NSColor {
        NSColor(white: white, alpha: alpha)
    }

    static func rgb(_ rgb: SIMD3<Double>, alpha: Double) -> NSColor {
        NSColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: alpha)
    }
}
#endif
