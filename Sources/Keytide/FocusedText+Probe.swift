import ApplicationServices
import Carbon

// The clipboard probe sends Shift+Left, Command+C and Right without seeing the text, so it goes only to a focus that
// shows an empty text caret (AXSelectedTextRange). A focus that is not known to be text (a game, a canvas, an AX
// error or timeout) never gets those keys; the caret is also how the probe checks where it left it.
extension FocusedText {
    enum ProbeCaret: Equatable { case at(Int), refused(String) }

    func probeCaret(pid: pid_t) -> ProbeCaret {
        guard !IsSecureEventInputEnabled() else { return .refused("secure input") }
        guard let element = focused() else { return .refused("focus unreadable") }
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return .refused("focus in another process") }
        AXUIElementSetMessagingTimeout(element, 0.05)
        switch inspect(element) {
        case .unknown(let range?): return range.length == 0 ? .at(range.location) : .refused("selection")
        // A text field whose text read failed refuses the correction itself (its tail cannot be checked).
        case .text, .loose: return .refused("text field")
        case .secure: return .refused("secure field")
        case .unknown(nil), .silent: return .refused("no caret")
        }
    }
}
