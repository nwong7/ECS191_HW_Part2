import Foundation

/// The example notes from the project brief (Recipes, Birthdays, Word List).
/// Used to seed the app on first launch, in SwiftUI previews and in tests.
public enum SampleNotes {
    public static func all(now: Date = Date()) -> [Note] {
        [wordList(now: now), birthdays(now: now), recipes(now: now)]
    }

    public static func recipes(now: Date = Date()) -> Note {
        Note(title: "Recipes", blocks: [
            Block(text: "Apple pie: recipe"),
            Block(text: "Butterscotch pie: recipe"),
            Block(text: "Snail pie: recipe"),
        ], createdAt: now, appearance: NoteAppearance(icon: "🍳", color: .orange))
    }

    public static func birthdays(now: Date = Date()) -> Note {
        Note(title: "Birthdays", blocks: [
            Block(style: .heading, text: "Family"),
            Block(text: "Dad [1/1/1111]"),
            Block(text: "Mom [1/1/1111]"),
            Block(text: ""),
            Block(style: .heading, text: "Friends"),
            Block(text: "Lucas H - 1/1/1111"),
            Block(text: "Emma S - 1/1/1111"),
            Block(text: ""),
            Block(style: .heading, text: "School"),
            Block(text: "Froilan F - 1/1/1111 "),
            Block(text: ""),
            Block(style: .heading, text: "Work"),
            Block(text: "Gregory R - 1/1/1111"),
        ], createdAt: now, appearance: NoteAppearance(icon: "🎂", color: .pink))
    }

    public static func wordList(now: Date = Date()) -> Note {
        Note(title: "Word List", blocks: [
            Block(text: "exuviae - sloughed off natural animal coverings"),
            Block(text: "kludge -  a makeshift, clumsy, or inelegant solution"),
        ], createdAt: now, appearance: NoteAppearance(icon: "📚", color: .blue))
    }
}
