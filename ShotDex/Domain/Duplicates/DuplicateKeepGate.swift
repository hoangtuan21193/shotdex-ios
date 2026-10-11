/// "Keep at least one photo in this group." (FS-06.06 §1, FS-01.08c §7) —
/// the one rule the Duplicates grid and a Compare opened from it share. A
/// group is never marked whole: the last photo in it that is not marked
/// cannot be marked. Pure; each caller says what "marked" means to it.
enum DuplicateKeepGate {
    /// Whether `id` may be marked. Unmarking is always allowed.
    static func canMark(_ id: String, in group: [String], isMarked: (String) -> Bool) -> Bool {
        guard group.contains(id), !isMarked(id) else { return true }
        return group.contains { $0 != id && !isMarked($0) }
    }
}
