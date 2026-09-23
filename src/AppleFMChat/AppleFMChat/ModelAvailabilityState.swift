// モデルの利用可否。フレームワークの型を View・ViewModel に見せないためのアプリ側の型
enum ModelAvailabilityState: Equatable {
    enum UnavailableReason: Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case other
    }

    case available
    case unavailable(UnavailableReason)
}
