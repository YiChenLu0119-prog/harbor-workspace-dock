import Foundation
import HarborCore

enum LocalizedNotice {
    case text(HarborText)
    case failure(String, Error)

    func rendered(in language: HarborLanguage) -> String {
        switch self {
        case .text(let text): return text.rendered(in: language)
        case .failure(let template, let error):
            return HarborLocalization.text(template, language: language, arguments: [HarborLocalization.errorDescription(error, language: language)])
        }
    }
}
