import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The AI built into the device (FS-08.07 §2): Apple Intelligence where the
/// device supports it and it is on.
enum OnDeviceAI {
    enum IntelligenceStatus: Equatable, Sendable {
        case ready
        case notEnabled
        case downloading
        /// The device or OS cannot run it: not listed.
        case unsupported
    }

    static var intelligence: IntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
            case .unavailable(.modelNotReady): return .downloading
            case .unavailable: return .unsupported
            }
        }
        #endif
        return .unsupported
    }

    static var choices: AIChoice.OnDevice {
        AIChoice.OnDevice(appleIntelligence: intelligence == .ready)
    }
}
