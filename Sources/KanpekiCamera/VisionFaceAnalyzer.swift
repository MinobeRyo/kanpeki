import Vision

/// Full-image detection retains every face. Re-estimate the largest face with more input detail.
/// No previous-frame coordinates, calibration labels or reference answers enter inference.
enum VisionFaceAnalyzer {
    static func refinementRegion(_ box: CGRect) -> CGRect {
        let width = box.width * 2.5, height = box.height * 2.5
        let x = max(0, box.midX - width/2)
        let top = max(0, 1-box.midY - height/2)
        let clippedHeight = min(height, 1-top)
        return CGRect(x: x, y: 1-top-clippedHeight, width: min(width, 1-x), height: clippedHeight)
    }
    static func isSameFace(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        return !overlap.isNull && overlap.width*overlap.height > 0.5 * min(a.width*a.height,b.width*b.height)
            && abs(a.midX-b.midX) < 0.35 * max(a.width,b.width)
            && abs(a.midY-b.midY) < 0.35 * max(a.height,b.height)
    }
    static func perform(_ request: VNDetectFaceRectanglesRequest, using handler: VNImageRequestHandler) throws -> [VNFaceObservation] {
        try handler.perform([request])
        var faces = request.results ?? []
        // The full-image detector downsamples the scene. Search overlapping regions as
        // well when faces are small or multiple people are present. Keep original poses
        // for existing detections and suppress duplicate boxes across region boundaries.
        let largestArea = faces.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0
        if faces.count >= 2 || largestArea < 0.02 {
            for y in [0.0, 0.35] { for x in [0.0, 0.35] {
                let regionRequest = VNDetectFaceRectanglesRequest()
                regionRequest.revision = request.revision
                regionRequest.regionOfInterest = CGRect(x: x, y: y, width: 0.65, height: 0.65)
                if (try? handler.perform([regionRequest])) != nil {
                    for candidate in regionRequest.results ?? [] where faces.count < 50 {
                        if !faces.contains(where: { isSameFace($0.boundingBox, candidate.boundingBox) }) {
                            faces.append(candidate)
                        }
                    }
                }
            } }
        }
        guard let index = faces.indices.max(by: { faces[$0].boundingBox.width*faces[$0].boundingBox.height < faces[$1].boundingBox.width*faces[$1].boundingBox.height }) else { return faces }
        let original = faces[index]
        let detail = VNDetectFaceRectanglesRequest()
        detail.revision = request.revision
        detail.regionOfInterest = refinementRegion(original.boundingBox)
        // A failed or ambiguous refinement never replaces the original detection.
        if (try? handler.perform([detail])) != nil,
           let match = detail.results?.filter({ isSameFace(original.boundingBox, $0.boundingBox) })
            .max(by: { $0.confidence < $1.confidence }), match.yaw != nil, match.pitch != nil {
            // Equal-weight fusion reduces sensitivity to the crop's framing.
            // Keep the original detection box so refinement cannot alter face count or tracking.
            let average: (NSNumber?, NSNumber?) -> NSNumber? = { a,b in
                guard let a, let b else { return a ?? b }
                return NSNumber(value: (a.doubleValue+b.doubleValue)/2)
            }
            faces[index] = VNFaceObservation(requestRevision: request.revision, boundingBox: original.boundingBox,
                roll: original.roll, yaw: average(original.yaw,match.yaw), pitch: average(original.pitch,match.pitch))
        }
        return faces
    }
}
