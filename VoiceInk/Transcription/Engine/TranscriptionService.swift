import Foundation

/// A protocol defining the interface for a transcription service.
/// This allows the engine to dispatch across the retained local transcription backends.
protocol TranscriptionService {
    /// Transcribes the audio from a given file URL.
    ///
    /// - Parameters:
    ///   - audioURL: The URL of the audio file to transcribe.
    ///   - model: The `TranscriptionModel` to use for transcription.
    /// - Returns: The transcribed text as a `String`.
    /// - Throws: An error if the transcription fails.
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String
} 
