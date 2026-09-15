import Vision

/// Camera capture and public-video benchmarking share the exact angle/box convention.
enum VisionFaceAdapter {
    static func normalized(_ face: VNFaceObservation) -> [String: Any] {
        let b = face.boundingBox
        return ["bbox": ["x": b.minX, "y": 1 - b.maxY, "width": b.width, "height": b.height],
                "yaw": face.yaw.map { -$0.doubleValue * 180 / .pi } as Any? ?? NSNull(),
                "pitch": face.pitch.map { -$0.doubleValue * 180 / .pi } as Any? ?? NSNull()]
    }
}
