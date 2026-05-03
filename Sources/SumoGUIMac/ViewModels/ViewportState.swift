import Foundation
import SumoKit

@MainActor
final class ViewportState: ObservableObject {
    private(set) var center = SIMD2<Float>(0, 0)
    private(set) var pointsPerWorldUnit: Float = 1
    private(set) var rotationRadians: Float = 0
    private(set) var isConfigured = false
    private var pinchLastMagnification: CGFloat = 1

    var onChange: (() -> Void)?

    func configureToFit(netBounds: SIMD4<Float>, viewSize: CGSize, inset: Float) {
        let width = max(netBounds.z - netBounds.x, 1)
        let height = max(netBounds.w - netBounds.y, 1)
        let availableWidth = max(Float(viewSize.width) - inset * 2, 1)
        let availableHeight = max(Float(viewSize.height) - inset * 2, 1)

        center = SIMD2((netBounds.x + netBounds.z) * 0.5, (netBounds.y + netBounds.w) * 0.5)
        pointsPerWorldUnit = min(availableWidth / width, availableHeight / height)
        rotationRadians = 0
        isConfigured = true
        onChange?()
    }

    func requestFit() {
        isConfigured = false
        rotationRadians = 0
        onChange?()
    }

    func pan(worldDelta: SIMD2<Float>) {
        guard isConfigured else { return }
        center += worldDelta
        onChange?()
    }

    func center(on point: SIMD2<Float>) {
        guard isConfigured else { return }
        center = point
        onChange?()
    }

    func setRotationDegrees(_ degrees: Float) {
        guard degrees.isFinite else { return }
        rotationRadians = degrees * .pi / 180
        onChange?()
    }

    func resetRotation() {
        guard rotationRadians != 0 else { return }
        rotationRadians = 0
        onChange?()
    }

    func zoom(by factor: Float, anchorWorld: SIMD2<Float>) {
        guard isConfigured else { return }
        let clampedFactor = max(0.25, min(factor, 4))
        let newScale = max(0.05, min(pointsPerWorldUnit * clampedFactor, 2_500))
        let anchorOffset = anchorWorld - center
        center = anchorWorld - anchorOffset * (pointsPerWorldUnit / newScale)
        pointsPerWorldUnit = newScale
        onChange?()
    }

    func updatePinch(magnification: CGFloat) {
        guard isConfigured else { return }
        let safePrevious = pinchLastMagnification == 0 ? 1 : pinchLastMagnification
        let safeCurrent = magnification == 0 ? safePrevious : magnification
        let factor = Float(safeCurrent / safePrevious)
        pinchLastMagnification = safeCurrent
        zoom(by: factor, anchorWorld: center)
    }

    func endPinch() {
        pinchLastMagnification = 1
    }

    func zoomIn() {
        guard isConfigured else { return }
        zoom(by: 1.25, anchorWorld: center)
    }

    func zoomOut() {
        guard isConfigured else { return }
        zoom(by: 0.8, anchorWorld: center)
    }
}
