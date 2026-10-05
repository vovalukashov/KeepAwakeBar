import Foundation

enum OwlState: Equatable {
    case sleeping, caffeinated, wideAwake, unknown

    static func resolve(systemDisabled: Bool?, caffeinate: Bool) -> OwlState {
        if systemDisabled == true { return .wideAwake }
        if caffeinate { return .caffeinated }
        guard systemDisabled != nil else { return .unknown }
        return .sleeping
    }
    var assetName: String {
        switch self {
        case .sleeping: return "OwlSleeping"
        case .wideAwake: return "OwlWideAwake"
        case .caffeinated, .unknown: return "MenuBarIcon"
        }
    }
    var description: String {
        switch self {
        case .sleeping: return "Caffeinate и Disable Sleep выключены"
        case .caffeinated: return "Caffeinate включён"
        case .wideAwake: return "Disable Sleep включён"
        case .unknown: return "Состояние системного сна пока неизвестно"
        }
    }
}
