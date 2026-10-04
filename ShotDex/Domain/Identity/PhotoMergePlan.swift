import Foundation

/// A value the user set and when — the unit of "latest change wins".
struct Stamped<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let at: Int
}

/// Everything the user typed about one photo, as the merge sees it.
struct PhotoUserData: Equatable, Sendable {
    var rating: Stamped<Int>?
    var isFavorite: Stamped<Bool>?
    var title: Stamped<String>?
    var caption: Stamped<String>?
    var flag: Stamped<String>?
    var recipe: Stamped<Data>?
    var keywords: Set<String> = []
    var albumIds: Set<String> = []
}

/// How two photos found to be one picture become one (FS-19.05 §4): the
/// older id survives; each single value keeps whichever side changed it
/// last; keywords and albums are joined, so no tag is lost.
enum PhotoMergePlan {
    struct Side: Sendable {
        let id: String
        let createdAt: Int
        let data: PhotoUserData
    }

    struct Result: Equatable, Sendable {
        let winnerId: String
        let loserId: String
        let data: PhotoUserData
    }

    static func merge(_ a: Side, _ b: Side) -> Result {
        let (winner, loser) = (a.createdAt, a.id) <= (b.createdAt, b.id) ? (a, b) : (b, a)
        var data = PhotoUserData()
        data.rating = latest(winner.data.rating, loser.data.rating)
        data.isFavorite = latest(winner.data.isFavorite, loser.data.isFavorite)
        data.title = latest(winner.data.title, loser.data.title)
        data.caption = latest(winner.data.caption, loser.data.caption)
        data.flag = latest(winner.data.flag, loser.data.flag)
        data.recipe = latest(winner.data.recipe, loser.data.recipe)
        data.keywords = winner.data.keywords.union(loser.data.keywords)
        data.albumIds = winner.data.albumIds.union(loser.data.albumIds)
        return Result(winnerId: winner.id, loserId: loser.id, data: data)
    }

    /// The later of two stamped values; on a tie the surviving photo's.
    static func latest<Value>(_ winner: Stamped<Value>?, _ loser: Stamped<Value>?) -> Stamped<Value>? {
        guard let loser else { return winner }
        guard let winner else { return loser }
        return loser.at > winner.at ? loser : winner
    }
}
