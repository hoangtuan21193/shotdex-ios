import AppKit
import SwiftUI

/// Move / Delete from a place that is not one source — All Photos, an album
/// — when a photo has more than one copy (board `MAC_DeleteCopies`,
/// FS-19.04 §1): every copy with a checkbox, only the one the photo opens
/// from checked; the photo stays in ShotDex with the copies left. One photo
/// lists each copy; several list one row per source with how many.
struct MacDeleteCopiesSheet: View {
    /// Every copy of each selected photo, the opening copy first.
    let copies: [[DeletionTarget]]
    /// Photos selected — more than `copies` when some have no copy row yet.
    let photoCount: Int
    let fileName: String?
    let cancel: () -> Void
    /// The copies picked, per photo (a photo with none picked is left out).
    let confirm: ([[DeletionTarget]]) -> Void

    /// Seeded once the sheet is up (not on every render of the window behind
    /// it): the copy each photo opens from; the rest stay unticked.
    @State private var chosen: Set<String> = []
    @State private var rows: [Row] = []
    @State private var isReady = false

    var body: some View {
        // Worked out once a render: a select-all is many copies.
        let picked = self.picked
        let plan = Self.plan(picked)
        let leaving = copies.filter { $0.allSatisfy { chosen.contains($0.copyId) } }.count
        return VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(title(plan, leaving: leaving))
                .font(.system(size: 13, weight: .bold))
            Text(lead)
                .font(.system(size: 11))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    rowView(row)
                }
            }
            .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MacTheme.separator))
            Text(summary(plan, leaving: leaving))
                .font(.system(size: 11))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
            Text(MixedDeletionPlan.footnote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(String(localized: "Cancel", comment: "Mac delete copies: dismiss"), action: cancel)
                    .buttonStyle(MacSheetButtonStyle(isDestructive: false))
                    .keyboardShortcut(.cancelAction)
                // Destructive, so never the prominent button and never on Return.
                Button(plan.count > 0 ? plan.confirmTitle : String(localized: "Remove", comment: "Mac delete copies: the button with nothing ticked")) {
                    confirm(picked)
                }
                .buttonStyle(MacSheetButtonStyle(isDestructive: true))
                .disabled(plan.count == 0 || !isReady)
                .help(plan.count == 0 ? String(localized: "Tick at least one copy", comment: "Mac delete copies: why the button is off") : "")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .padding(.top, 4)
        .frame(width: 400)
        .presentationBackground(MacTheme.sheet)
        .task {
            let copies = self.copies
            let built = await Task.detached(priority: .userInitiated) {
                (Self.rows(for: copies), Set(copies.compactMap(\.first?.copyId)))
            }.value
            rows = built.0
            chosen = built.1
            isReady = true
        }
    }

    // MARK: Rows

    /// One copy (one photo), or one source holding copies of several photos.
    private struct Row: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let copyIds: [String]
    }

    private static func rows(for copies: [[DeletionTarget]]) -> [Row] {
        if copies.count == 1, let only = copies.first {
            return only.enumerated().map { index, copy in
                Row(id: copy.copyId, title: place(copy), detail: detail(copy, isOpening: index == 0),
                    symbol: symbol(copy.kind), copyIds: [copy.copyId])
            }
        }
        // Several photos: a row per source, in the order sources first appear.
        var order: [String] = []
        var bySource: [String: [DeletionTarget]] = [:]
        for copy in copies.joined() {
            if bySource[copy.sourceId] == nil { order.append(copy.sourceId) }
            bySource[copy.sourceId, default: []].append(copy)
        }
        let opening = Set(copies.compactMap(\.first?.copyId))
        return order.compactMap { sourceId in
            guard let group = bySource[sourceId], let first = group.first else { return nil }
            let opens = group.filter { opening.contains($0.copyId) }.count
            let photos = String(AttributedString(localized: "^[\(group.count) photo](inflect: true)",
                                                 comment: "Mac delete copies: how many photos have a copy in this source").characters)
            let role = opens == group.count
                ? String(localized: "the copies shown in ShotDex", comment: "Mac delete copies: every copy in this source is the one ShotDex shows")
                : opens == 0 ? String(localized: "other copies", comment: "Mac delete copies: no copy in this source is the one ShotDex shows")
                : String(localized: "\(opens) shown from here", comment: "Mac delete copies: some photos are shown from this source")
            return Row(id: sourceId, title: first.kind == "server" ? hideName(first.sourceName) : first.sourceName,
                       detail: [photos, role, destinationWords(first.destination, conditional: opens == 0)].joined(separator: " · "),
                       symbol: symbol(first.kind), copyIds: group.map(\.copyId))
        }
    }

    private func rowView(_ row: Row) -> some View {
        let picked = row.copyIds.filter(chosen.contains).count
        return HStack(alignment: .top, spacing: 8) {
            MacMixedCheckbox(title: "", count: picked, total: row.copyIds.count) { isOn in
                if isOn { chosen.formUnion(row.copyIds) } else { chosen.subtract(row.copyIds) }
            }
            Image(systemName: row.symbol)
                .font(.system(size: 14))
                .foregroundStyle(MacTheme.accent)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(row.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { toggle(row, picked: picked) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([picked == row.copyIds.count ? String(localized: "on", comment: "Mac delete copies: VoiceOver, row ticked")
                             : picked == 0 ? String(localized: "off", comment: "Mac delete copies: VoiceOver, row not ticked")
                             : String(localized: "mixed", comment: "Mac delete copies: VoiceOver, some of the row's copies ticked"),
                             row.detail].joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle(row, picked: picked) }
    }

    private func toggle(_ row: Row, picked: Int) {
        if picked == row.copyIds.count { chosen.subtract(row.copyIds) } else { chosen.formUnion(row.copyIds) }
    }

    // MARK: Words

    private var picked: [[DeletionTarget]] {
        copies.map { $0.filter { chosen.contains($0.copyId) } }.filter { !$0.isEmpty }
    }

    private static func plan(_ picked: [[DeletionTarget]]) -> MixedDeletionPlan {
        var plan = MixedDeletionPlan(photos: picked.map { $0.map(\.destination) }, selection: .photos)
        plan.trashName = MixedDeletionPlan.macTrashName
        return plan
    }

    /// "DSC04512.ARW has 3 copies. Choose the ones to remove; …"
    private var lead: String {
        let keep = String(localized: "Choose the ones to remove; the photo stays in ShotDex with the copies you keep.",
                          comment: "Mac delete copies: how the checklist works, one photo")
        if photoCount == 1, copies.count == 1, let total = copies.first?.count {
            let name = fileName ?? String(localized: "This photo", comment: "Mac delete copies: a photo with no file name")
            return String(localized: "\(name) has \(total) copies.", comment: "Mac delete copies: how many copies one photo has (plural)") + " " + keep
        }
        return String(localized: "Some of these \(photoCount) photos have copies in more than one place. Choose where to remove them; a photo stays in ShotDex while it has a copy left.",
                      comment: "Mac delete copies: how the checklist works, several photos")
    }

    /// "Remove 1 copy?" while every photo keeps a copy; the plan's own title
    /// ("Move 1 photo?") once a photo leaves ShotDex with none.
    private func title(_ plan: MixedDeletionPlan, leaving: Int) -> String {
        guard plan.count > 0 else {
            return String(localized: "Choose Copies to Remove", comment: "Mac delete copies: title with nothing checked")
        }
        guard leaving == 0 else { return plan.title }
        return String(AttributedString(localized: "Remove ^[\(chosen.count) copy](inflect: true)?",
                                       comment: "Mac delete copies: title when every photo keeps a copy").characters)
    }

    /// "1 goes to the Trash. … 2 copies stay." plus what to expect next.
    private func summary(_ plan: MixedDeletionPlan, leaving: Int) -> String {
        let total = copies.reduce(0) { $0 + $1.count }, removed = chosen.count
        let stay = total - removed
        var parts: [String] = []
        if plan.count > 0 {
            parts.append(plan.message)
            if plan.count(.trash) > 0 {
                parts.append(String(localized: "Files go with their paired JPEG and .xmp sidecar.",
                                    comment: "Mac delete copies: what goes to the Trash with a file"))
            }
        }
        if stay > 0 {
            parts.append(stay == 1 ? String(localized: "1 copy stays.", comment: "Mac delete copies: copies left")
                                   : String(localized: "\(stay) copies stay.", comment: "Mac delete copies: copies left (plural)"))
        }
        if leaving > 0 {
            parts.append(photoCount == 1
                ? String(localized: "No copy left: the photo leaves ShotDex.", comment: "Mac delete copies: every copy of the photo ticked")
                : String(localized: "\(leaving) photos have no copy left and leave ShotDex.", comment: "Mac delete copies: photos with every copy ticked (plural)"))
        }
        if plan.count(.recentlyDeleted) > 0 {
            parts.append(String(localized: "Photos asks to confirm its part.", comment: "Mac delete copies: the system dialog follows for Photos copies"))
        }
        if plan.needsPermanentConfirmation {
            parts.append(String(localized: "You'll be asked once more for files that can't be recovered.",
                                comment: "Mac delete copies: a no-Trash dialog follows"))
        }
        return parts.joined(separator: " ")
    }

    /// "T7 RAW Archive › RAW/2026-09-27", "Photos Library", "NAS Home (hide)".
    private static func place(_ copy: DeletionTarget) -> String {
        if copy.kind == "server" { return hideName(copy.sourceName) }
        guard let path = copy.relativePath else { return copy.sourceName }
        let folder = (path as NSString).deletingLastPathComponent
        return folder.isEmpty ? copy.sourceName : "\(copy.sourceName) › \(folder)"
    }

    private static func hideName(_ name: String) -> String {
        String(localized: "\(name) (hide)", comment: "Mac delete copies: a server source, whose copies are only hidden")
    }

    private static func detail(_ copy: DeletionTarget, isOpening: Bool) -> String {
        let role = isOpening ? String(localized: "Shown in ShotDex", comment: "Mac delete copies: the copy ShotDex shows and opens")
                             : String(localized: "Also stored here", comment: "Mac delete copies: another copy of the same photo")
        return role + " · " + destinationWords(copy.destination, conditional: !isOpening)
    }

    /// Where a copy goes; "would go" for one left unchecked by default.
    private static func destinationWords(_ destination: DeletionDestination, conditional: Bool) -> String {
        switch destination {
        case .trash:
            conditional ? String(localized: "would go to the Trash", comment: "Mac delete copies: a backup on a volume with a Trash")
                        : String(localized: "goes to the Trash", comment: "Mac delete copies: the opening copy on a volume with a Trash")
        case .recentlyDeleted:
            conditional ? String(localized: "would go to Recently Deleted", comment: "Mac delete copies: a backup in Photos")
                        : String(localized: "goes to Recently Deleted", comment: "Mac delete copies: the opening copy in Photos")
        case .permanent:
            conditional ? String(localized: "would be deleted permanently (no Trash)", comment: "Mac delete copies: a backup on a volume with no Trash")
                        : String(localized: "is deleted permanently (no Trash)", comment: "Mac delete copies: the opening copy on a volume with no Trash")
        case .hide:
            String(localized: "can only be hidden in ShotDex", comment: "Mac delete copies: a copy on a server")
        }
    }

    private static func symbol(_ kind: String) -> String {
        switch kind {
        case "photos": "photo.stack"
        case "server": "server.rack"
        case "drive": "externaldrive"
        default: "folder"
        }
    }
}

/// The checklist's two buttons (board `MAC_DeleteCopies`): side by side,
/// equal, `fill`; the destructive one red text, never the default.
private struct MacSheetButtonStyle: ButtonStyle {
    let isDestructive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isDestructive ? MacTheme.redText : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.pressed))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// A Move / Delete that waits on which copies go (`MacDeleteCopiesSheet`).
struct MacDeleteCopiesRequest: Identifiable {
    let id = UUID()
    let photoIds: [String]
    let copies: [[DeletionTarget]]
    /// Selected photos with no copy row yet: they go with the Photos part.
    let photosOnly: [String]
    let fileName: String?
}
