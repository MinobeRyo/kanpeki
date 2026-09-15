import Foundation
import whisper

final class AudioCancellation {
    private let lock = NSLock()
    private var stopped = false
    private let deadline = Date().addingTimeInterval(600)
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped || Date() >= deadline }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

struct WhisperEngine {
    func transcribe(_ samples: [Float], model: URL, cancellation: AudioCancellation) throws -> [AudioSegment] {
        guard !cancellation.isCancelled else { throw CancellationError() }
        let parameters = whisper_context_default_params()
        guard let context = model.path.withCString({ whisper_init_from_file_with_params($0, parameters) }) else {
            throw AudioHostError.invalid("分析モデルを読み込めません。モデルを準備し直してください。")
        }
        defer { whisper_free(context) }
        var options = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        options.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))
        options.translate = false
        options.no_context = true
        options.print_progress = false
        options.print_realtime = false
        options.print_timestamps = false
        options.print_special = false
        options.max_len = 40
        options.abort_callback = { pointer in
            guard let pointer else { return true }
            return Unmanaged<AudioCancellation>.fromOpaque(pointer).takeUnretainedValue().isCancelled
        }
        options.abort_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()
        let result = "ja".withCString { language in
            options.language = language
            return samples.withUnsafeBufferPointer { whisper_full(context, options, $0.baseAddress, Int32($0.count)) }
        }
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard result == 0 else { throw AudioHostError.invalid("文字起こしに失敗しました。音声を確認して再度試してください。") }
        let duration = Double(samples.count)/16000
        return (0..<whisper_full_n_segments(context)).compactMap { i in
            let start = max(0, Double(whisper_full_get_segment_t0(context,i))/100)
            let end = min(duration, Double(whisper_full_get_segment_t1(context,i))/100)
            guard end > start, let textPointer = whisper_full_get_segment_text(context,i) else { return nil }
            let text = String(cString: textPointer).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : AudioSegment(start: start, end: end, text: text)
        }
    }
}
