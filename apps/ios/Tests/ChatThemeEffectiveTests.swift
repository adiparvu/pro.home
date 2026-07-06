import XCTest
@testable import PRVIO

// ChatTheme.effective(scope:) is the one authority for what a conversation
// shows. The regression it guards: the three background keys are ONE setting
// (the picker clears the other two with "" when one is chosen), so a
// per-field fallback to the global values would resurrect a stale global
// photo over a freshly picked preset — "the background never changes".
final class ChatThemeEffectiveTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "chat-theme-effective-tests")
        defaults.removePersistentDomain(forName: "chat-theme-effective-tests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "chat-theme-effective-tests")
        super.tearDown()
    }

    func testScopedPresetBeatsStaleGlobalPhoto() {
        defaults.set("chatbg-global.jpg", forKey: "prvio.chatBgImage")
        defaults.set("aurora", forKey: "prvio.chatBgAnim.group")
        defaults.set("", forKey: "prvio.chatBgImage.group")
        defaults.set("", forKey: "prvio.chatBgID.group")

        let theme = ChatTheme.effective(scope: "group", defaults: defaults)
        XCTAssertEqual(theme.backgroundAnimation, "aurora")
        XCTAssertNil(theme.backgroundImage, "The stale global photo must not win")
    }

    func testGlobalPresetAppliesWhenScopeUntouched() {
        defaults.set("aurora", forKey: "prvio.chatBgAnim")
        defaults.set("", forKey: "prvio.chatBgImage")

        let theme = ChatTheme.effective(scope: "group", defaults: defaults)
        XCTAssertEqual(theme.backgroundAnimation, "aurora")
    }

    func testScopeInheritsGlobalPhotoWhenNoScopedBackground() {
        defaults.set("chatbg-global.jpg", forKey: "prvio.chatBgImage")

        let theme = ChatTheme.effective(scope: "group", defaults: defaults)
        XCTAssertEqual(theme.backgroundImage, "chatbg-global.jpg")
    }

    func testScopedPhotoWinsOverScopedLeftovers() {
        defaults.set("chatbg-group.jpg", forKey: "prvio.chatBgImage.group")
        defaults.set("", forKey: "prvio.chatBgAnim.group")

        let theme = ChatTheme.effective(scope: "group", defaults: defaults)
        XCTAssertEqual(theme.backgroundImage, "chatbg-group.jpg")
        XCTAssertNil(theme.backgroundAnimation)
    }

    func testThemeAndBubbleStillFallBackPerField() {
        defaults.set("midnight", forKey: "prvio.chatTheme")
        defaults.set("#FF0000", forKey: "prvio.chatBubbleHex.group")

        let theme = ChatTheme.effective(scope: "group", defaults: defaults)
        XCTAssertEqual(theme.name, ChatTheme.theme(for: "midnight").name)
    }

    func testGlobalScopeReadsGlobalOnly() {
        defaults.set("tide", forKey: "prvio.chatBgAnim")
        defaults.set("ember", forKey: "prvio.chatBgAnim.group")

        let theme = ChatTheme.effective(scope: nil, defaults: defaults)
        XCTAssertEqual(theme.backgroundAnimation, "tide")
    }
}
