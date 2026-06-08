import SwiftUI

// MARK: - Group label (uppercase micro-label header)

struct GroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(VaniToken.text3)
            .padding(.horizontal, 4)
    }
}

// MARK: - Glass card (rows on a frosted surface, hairline dividers)

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(VaniToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: VaniRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaniRadius.card, style: .continuous)
                    .strokeBorder(VaniToken.border, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: VaniRadius.card, style: .continuous)
                    .strokeBorder(VaniToken.glassEdge, lineWidth: 1)
                    .blendMode(.plusLighter).opacity(0.5)
            }
    }
}

/// One row: title (+ optional subtitle) on the left, a trailing control.
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5)).foregroundStyle(VaniToken.text)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11.5)).foregroundStyle(VaniToken.text2)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if showDivider {
                Rectangle().fill(VaniToken.hairline).frame(height: 1).padding(.leading, 14)
            }
        }
    }
}

// MARK: - Accent swatches

struct AccentSwatches: View {
    @Binding var selected: UInt32
    let options: [UInt32] = [0x6F6BE0, 0x2E9E6B, 0x2E6FD8, 0xD9534F, 0xC7892B, 0x222530]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.self) { hex in
                Circle()
                    .fill(Color(nsColor: NSColor(hex: hex)))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white, lineWidth: selected == hex ? 2 : 0))
                    .overlay(Circle().strokeBorder(VaniToken.border, lineWidth: 1))
                    .onTapGesture { selected = hex }
            }
        }
    }
}

// MARK: - Chip field (tokens with × + add)

struct ChipField: View {
    @Binding var items: [String]
    var placeholder: String = "Add term…"
    @State private var draft = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item).font(.system(size: 12))
                    Button { items.removeAll { $0 == item } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }.buttonStyle(.plain).foregroundStyle(VaniToken.accentText)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(VaniToken.accentSoft, in: Capsule())
                .foregroundStyle(VaniToken.accentText)
            }
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .frame(minWidth: 90)
                .onSubmit { commit() }
        }
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !items.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { draft = ""; return }
        items.append(t); draft = ""
    }
}

/// Simple flow layout that wraps chips to new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: - Icon-pill tab bar (Raycast-style)

struct VaniTabBar<Tab: Hashable>: View {
    let tabs: [(tab: Tab, label: String, icon: String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.tab) { item in
                Button { selection = item.tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 15))
                        Text(item.label).font(.system(size: 10.5, weight: .medium))
                    }
                    .frame(width: 64, height: 44)
                    .foregroundStyle(selection == item.tab ? VaniToken.accentText : VaniToken.text2)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selection == item.tab ? VaniToken.accentSoft : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
    }
}
