import SwiftUI

// MARK: - Data types

struct StickerCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let stickers: [Sticker]
}

struct Sticker: Identifiable, Hashable {
    let id: String
    let emoji: String
    let label: String
    let categoryId: String
}

// MARK: - Catalog (baked-in, no server required)

enum StickerCatalog {
    static let categories: [StickerCategory] = [
        StickerCategory(id: "home", name: "Home Life",
                        icon: "house.fill", color: .blue, stickers: [
            Sticker(id: "home_sweet",     emoji: "🏠", label: "Home sweet home", categoryId: "home"),
            Sticker(id: "cozy_mode",      emoji: "🛋️", label: "Cozy mode",       categoryId: "home"),
            Sticker(id: "good_vibes",     emoji: "🪟", label: "Good vibes only",  categoryId: "home"),
            Sticker(id: "coffee_first",   emoji: "☕", label: "Coffee first",     categoryId: "home"),
            Sticker(id: "do_not_disturb", emoji: "😴", label: "Do not disturb",   categoryId: "home"),
            Sticker(id: "laundry_later",  emoji: "🧺", label: "Laundry… later",   categoryId: "home"),
        ]),
        StickerCategory(id: "plants", name: "Plants",
                        icon: "leaf.fill", color: Color(red: 0.2, green: 0.75, blue: 0.35), stickers: [
            Sticker(id: "lookin_good",  emoji: "🌿", label: "Lookin' good!",   categoryId: "plants"),
            Sticker(id: "thirsty",      emoji: "🪴", label: "Thirsty!",         categoryId: "plants"),
            Sticker(id: "too_cool",     emoji: "🌵", label: "Too cool to die",  categoryId: "plants"),
            Sticker(id: "little_tough", emoji: "🌱", label: "Little but tough", categoryId: "plants"),
            Sticker(id: "help_me",      emoji: "🌸", label: "Help me",          categoryId: "plants"),
            Sticker(id: "cant_touch",   emoji: "🪸", label: "Can't touch this", categoryId: "plants"),
        ]),
        StickerCategory(id: "tasks", name: "Tasks & Wins",
                        icon: "checklist", color: Color(red: 0.3, green: 0.82, blue: 0.5), stickers: [
            Sticker(id: "all_done",     emoji: "✅", label: "All done!",     categoryId: "tasks"),
            Sticker(id: "lets_do_this", emoji: "💪", label: "Let's do this!", categoryId: "tasks"),
            Sticker(id: "on_it",        emoji: "📋", label: "On it!",         categoryId: "tasks"),
            Sticker(id: "well_done",    emoji: "🏆", label: "Well done!",     categoryId: "tasks"),
            Sticker(id: "yay",          emoji: "🎉", label: "Yay!",           categoryId: "tasks"),
            Sticker(id: "goal_hit",     emoji: "🎯", label: "Goal hit!",      categoryId: "tasks"),
        ]),
        StickerCategory(id: "supplies", name: "Supplies",
                        icon: "cart.fill", color: Color(red: 0.35, green: 0.65, blue: 1.0), stickers: [
            Sticker(id: "shopping_time",   emoji: "🛒", label: "Shopping time",   categoryId: "supplies"),
            Sticker(id: "dont_run_out",    emoji: "🧻", label: "Don't run out!",   categoryId: "supplies"),
            Sticker(id: "need_more_juice", emoji: "🔋", label: "Need more juice",  categoryId: "supplies"),
            Sticker(id: "spray_and_pray",  emoji: "🧴", label: "Spray & pray",    categoryId: "supplies"),
            Sticker(id: "stock_up",        emoji: "📦", label: "Stock up",         categoryId: "supplies"),
            Sticker(id: "bright_idea",     emoji: "💡", label: "Bright idea",      categoryId: "supplies"),
        ]),
        StickerCategory(id: "maintenance", name: "Maintenance",
                        icon: "wrench.and.screwdriver.fill", color: Color(red: 0.9, green: 0.5, blue: 0.15), stickers: [
            Sticker(id: "i_fix_stuff", emoji: "🔧", label: "I fix stuff",         categoryId: "maintenance"),
            Sticker(id: "check_me",    emoji: "🔩", label: "Check me",             categoryId: "maintenance"),
            Sticker(id: "filter_time", emoji: "🌫️", label: "Filter time",          categoryId: "maintenance"),
            Sticker(id: "beep_love",   emoji: "🤖", label: "Beep if you love me",  categoryId: "maintenance"),
            Sticker(id: "uh_oh",       emoji: "😬", label: "Uh oh…",               categoryId: "maintenance"),
            Sticker(id: "all_good",    emoji: "👷", label: "All good!",             categoryId: "maintenance"),
        ]),
        StickerCategory(id: "mood", name: "Mood & Energy",
                        icon: "bolt.fill", color: Color(red: 1.0, green: 0.7, blue: 0.1), stickers: [
            Sticker(id: "hundred",   emoji: "⚡", label: "100%",      categoryId: "mood"),
            Sticker(id: "meh",       emoji: "😑", label: "Meh…",       categoryId: "mood"),
            Sticker(id: "send_help", emoji: "😩", label: "Send help",  categoryId: "mood"),
            Sticker(id: "recharge",  emoji: "🔌", label: "Recharge",   categoryId: "mood"),
        ]),
        StickerCategory(id: "extras", name: "Extras",
                        icon: "sparkles", color: Color(red: 0.6, green: 0.35, blue: 0.95), stickers: [
            Sticker(id: "new_stuff",   emoji: "🎁", label: "New stuff!",   categoryId: "extras"),
            Sticker(id: "memories",    emoji: "📷", label: "Memories",    categoryId: "extras"),
            Sticker(id: "important",   emoji: "📌", label: "Important!",   categoryId: "extras"),
            Sticker(id: "thats_prvio", emoji: "🏡", label: "That's PRVIO", categoryId: "extras"),
        ]),
    ]

    static func sticker(id: String) -> Sticker? {
        categories.flatMap(\.stickers).first { $0.id == id }
    }

    static var all: [Sticker] { categories.flatMap(\.stickers) }
}
