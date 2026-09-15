import CoreImage
import Vision

/// Vertical facial-landmark measurements for nod analysis.
/// All values are pixels in the image frame with y increasing downward.
/// Only scalar geometry leaves this function; no face image or identity feature is produced.
enum FaceLandmarkFeatures {
    static func extract(_ face: VNFaceObservation, imageWidth: Double, imageHeight: Double) -> [String: Any]? {
        guard let landmarks = face.landmarks else { return nil }
        let box = face.boundingBox
        func toPixels(_ p: CGPoint) -> (x: Double, y: Double) {
            (Double(box.minX + p.x * box.width) * imageWidth,
             (1 - Double(box.minY + p.y * box.height)) * imageHeight)
        }
        func points(_ region: VNFaceLandmarkRegion2D?) -> [(x: Double, y: Double)] {
            guard let region, region.pointCount > 0 else { return [] }
            return region.normalizedPoints.map(toPixels)
        }
        func mean(_ pts: [(x: Double, y: Double)]) -> (x: Double, y: Double)? {
            guard !pts.isEmpty else { return nil }
            return (pts.map(\.x).reduce(0, +) / Double(pts.count), pts.map(\.y).reduce(0, +) / Double(pts.count))
        }
        guard let left = mean(points(landmarks.leftEye)), let right = mean(points(landmarks.rightEye)),
              let noseTip = points(landmarks.noseCrest).max(by: { $0.y < $1.y }),
              let chin = points(landmarks.medianLine).max(by: { $0.y < $1.y }) else { return nil }
        let interocular = hypot(right.x - left.x, right.y - left.y)
        guard interocular > 4 else { return nil }
        let eyeMid = (x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        var output: [String: Any] = [
            "eyeY": eyeMid.y, "eyeX": eyeMid.x, "noseY": noseTip.y, "noseX": noseTip.x, "chinY": chin.y,
            "interocular": interocular,
            "eyeNose": noseTip.y - eyeMid.y, "eyeChin": chin.y - eyeMid.y,
            "boxTopY": (1 - Double(box.maxY)) * imageHeight, "boxHeight": Double(box.height) * imageHeight]
        if let noseBase = mean(points(landmarks.nose)) { output["noseBaseY"] = noseBase.y }
        if let roll = face.roll { output["roll"] = roll.doubleValue * 180 / .pi }
        return output
    }

    /// Minimum face height (pixels) below which the landmark detector runs on an upscaled crop.
    static var upscaleBelowHeight = 0.0
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Runs the landmark detector on already detected faces and attaches the geometry to each
    /// normalized face dictionary. Faces without a matching landmark result are left unchanged.
    /// Small faces are optionally re-detected on an upscaled crop so landmark quantisation shrinks.
    static func attach(to faces: inout [[String: Any]], observations: [VNFaceObservation],
                       handler: VNImageRequestHandler, imageWidth: Double, imageHeight: Double,
                       pixelBuffer: CVPixelBuffer? = nil) throws {
        guard !observations.isEmpty else { return }
        if upscaleBelowHeight > 0, let pixelBuffer {
            try attachUpscaled(to: &faces, observations: observations, pixelBuffer: pixelBuffer, imageWidth: imageWidth, imageHeight: imageHeight)
            return
        }
        let request = VNDetectFaceLandmarksRequest()
        request.inputFaceObservations = observations
        try handler.perform([request])
        for result in request.results ?? [] {
            guard let index = observations.firstIndex(where: { VisionFaceAnalyzer.isSameFace($0.boundingBox, result.boundingBox) }),
                  index < faces.count, faces[index]["landmarks"] == nil,
                  let features = extract(result, imageWidth: imageWidth, imageHeight: imageHeight) else { continue }
            faces[index]["landmarks"] = features
        }
    }

    /// Landmarks from a 2–4× upscaled crop around each face; output geometry is mapped back to frame pixels.
    private static func attachUpscaled(to faces: inout [[String: Any]], observations: [VNFaceObservation],
                                       pixelBuffer: CVPixelBuffer, imageWidth: Double, imageHeight: Double) throws {
        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        for (index, face) in observations.enumerated() where index < faces.count {
            let b = face.boundingBox
            let heightPx = b.height * imageHeight
            let scale = heightPx >= upscaleBelowHeight ? 1.0 : min(4.0, max(2.0, (upscaleBelowHeight / heightPx).rounded(.up)))
            // Crop with a margin (bottom-left origin like Vision), upscale, and run landmarks on the crop.
            let crop = CGRect(x: max(0, (b.minX - b.width * 0.3) * imageWidth), y: max(0, (b.minY - b.height * 0.3) * imageHeight),
                              width: min(imageWidth, b.width * 1.6 * imageWidth), height: min(imageHeight, b.height * 1.6 * imageHeight)).integral
            guard crop.width >= 8, crop.height >= 8 else { continue }
            let image = frame.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: crop.width * scale, height: crop.height * scale)) else { continue }
            // The face box inside the crop, normalized to the crop.
            let inner = CGRect(x: (b.minX * imageWidth - crop.minX) / crop.width, y: (b.minY * imageHeight - crop.minY) / crop.height,
                               width: b.width * imageWidth / crop.width, height: b.height * imageHeight / crop.height)
            let request = VNDetectFaceLandmarksRequest()
            request.inputFaceObservations = [VNFaceObservation(boundingBox: inner)]
            try VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:]).perform([request])
            guard let result = request.results?.first, let l = result.landmarks else { continue }
            // Map normalized crop coordinates to frame pixels (y down).
            let rb = result.boundingBox
            func toPixels(_ p: CGPoint) -> (x: Double, y: Double) {
                let cx = (rb.minX + p.x * rb.width) * crop.width + crop.minX
                let cy = (rb.minY + p.y * rb.height) * crop.height + crop.minY
                return (Double(cx), imageHeight - Double(cy))
            }
            func points(_ region: VNFaceLandmarkRegion2D?) -> [(x: Double, y: Double)] {
                guard let region, region.pointCount > 0 else { return [] }
                return region.normalizedPoints.map(toPixels)
            }
            func mean(_ pts: [(x: Double, y: Double)]) -> (x: Double, y: Double)? {
                guard !pts.isEmpty else { return nil }
                return (pts.map(\.x).reduce(0, +) / Double(pts.count), pts.map(\.y).reduce(0, +) / Double(pts.count))
            }
            guard let left = mean(points(l.leftEye)), let right = mean(points(l.rightEye)),
                  let noseTip = points(l.noseCrest).max(by: { $0.y < $1.y }),
                  let chin = points(l.medianLine).max(by: { $0.y < $1.y }) else { continue }
            let interocular = hypot(right.x - left.x, right.y - left.y)
            guard interocular > 2 else { continue }
            let eyeMid = (x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
            var output: [String: Any] = [
                "eyeY": eyeMid.y, "eyeX": eyeMid.x, "noseY": noseTip.y, "noseX": noseTip.x, "chinY": chin.y,
                "interocular": interocular, "eyeNose": noseTip.y - eyeMid.y, "eyeChin": chin.y - eyeMid.y,
                "boxTopY": (1 - Double(b.maxY)) * imageHeight, "boxHeight": Double(b.height) * imageHeight, "upscale": scale]
            if let noseBase = mean(points(l.nose)) { output["noseBaseY"] = noseBase.y }
            if let roll = result.roll { output["roll"] = roll.doubleValue * 180 / .pi }
            faces[index]["landmarks"] = output
        }
    }
}
