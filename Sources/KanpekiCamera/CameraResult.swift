import Foundation

/// A device-local camera session, not the presentation's timer or an audio score.
public struct CameraResult: Equatable {
    public enum Status: Equatable {
        case off, preparing, collecting, finalizing, completed, permissionDenied, inputInterrupted, cancelled, failed(String)

        public var message: String {
            switch self {
            case .off: return "分析OFF · カメラ結果はありません"
            case .preparing: return "カメラを準備中 · まだ計測していません"
            case .collecting: return "カメラ分析中"
            case .finalizing: return "結果を準備中 · 待たずに準備へ戻れます"
            case .completed: return "カメラ分析を終了しました"
            case .permissionDenied: return "権限不足 · カメラの使用が許可されていません"
            case .inputInterrupted: return "入力断・中断 · 停止までに取得できた結果です"
            case .cancelled: return "開始前にキャンセル · 未計測です"
            case .failed(let message): return "解析失敗 · \(message)"
            }
        }
    }

    public private(set) var id: UUID?
    public private(set) var subject: CameraSubject = .audience
    public private(set) var status: Status = .off
    public private(set) var summary = CameraSummary()
    public init() {}

    mutating func begin(id: UUID, subject: CameraSubject) {
        self = CameraResult()
        self.id = id
        self.subject = subject
        status = .preparing
    }

    /// Late capture callbacks cannot attach a previous session to a new result.
    mutating func update(id: UUID, status: Status, summary: CameraSummary? = nil) {
        guard self.id == id else { return }
        self.status = status
        if let summary { self.summary = summary }
    }

    @discardableResult
    mutating func delete(id: UUID) -> Bool {
        guard self.id == id else { return false }
        switch status {
        case .preparing, .collecting, .finalizing: return false
        default: self = CameraResult(); return true
        }
    }
}
