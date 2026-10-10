import MomentumCore
import SwiftUI

/// Every achievement, earned ones shining and the rest showing how close they are. A medal
/// morphs open into its details.
struct AwardsView: View {
    @Environment(GoalStore.self) private var store
    @Namespace private var hero
    @State private var opened: String?

    var body: some View {
        let progress = store.engine.achievements(now: store.now)
        let earned = progress.filter(\.isEarned)
        let recent = earned.sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }.prefix(6)
        let closest = progress.filter { !$0.isEarned && $0.fraction > 0 }.sorted { $0.fraction > $1.fraction }.prefix(3)
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header(progress)
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle("Recently earned", systemImage: "sparkles")
                            ScrollView(.horizontal) {
                                HStack(spacing: 22) {
                                    ForEach(Array(recent)) { item in
                                        medalButton(item, place: "recent", size: 92)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                            }
                            .scrollIndicators(.never)
                        }
                    }
                    if !closest.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Almost there", systemImage: "chart.line.uptrend.xyaxis")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                                ForEach(Array(closest)) { item in AwardRow(item: item) { open(item, from: "closest") } }
                            }
                        }
                    }
                    ForEach(Achievement.Family.allCases, id: \.self) { family in
                        let items = progress.filter { $0.achievement.family == family }
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label(family.title, systemImage: family.symbolName)
                                    .font(.headline)
                                Text("\(items.filter(\.isEarned).count)/\(items.count)")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 170), spacing: 18)], alignment: .leading, spacing: 22) {
                                ForEach(items) { item in
                                    medalButton(item, place: "grid", size: 70)
                                }
                            }
                        }
                        .glassCard(cornerRadius: 24, padding: 20)
                    }
                }
                .padding(Metrics.screenPadding)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(opened != nil)

            if let key = opened, let item = progress.first(where: { key.hasSuffix("|\($0.id)") }) {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                AwardDetail(item: item, heroID: "medal-\(key)", hero: hero, onClose: close)
                    .zIndex(1)
            }
        }
        .background(Aurora())
        .navigationTitle("Awards")
        .onEscape { close() }
    }

    private func header(_ progress: [AchievementProgress]) -> some View {
        let earned = progress.filter(\.isEarned).count
        let total = progress.count
        let summary = VStack(alignment: .leading, spacing: 8) {
            if Metrics.showsInlineTitles {
                Text("Awards")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }
            Text("\(earned) of \(total) earned. Each one marks something you kept showing up for.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressBar(progress: total > 0 ? Double(earned) / Double(total) : 0, color: .yellow)
                .frame(maxWidth: 360)
        }
        let tiers = HStack(spacing: 4) {
            ForEach(Achievement.Tier.allCases, id: \.self) { tier in
                TierCount(tier: tier, count: progress.filter { $0.isEarned && $0.achievement.tier == tier }.count)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 22) {
                summary.frame(minWidth: 320, alignment: .leading)
                Spacer()
                tiers
            }
            VStack(alignment: .leading, spacing: 16) {
                summary
                tiers
            }
        }
    }

    /// A medal with its title. `place` tells apart the same medal shown in two sections, so each
    /// morphs from where it was clicked.
    private func medalButton(_ item: AchievementProgress, place: String, size: CGFloat) -> some View {
        let key = "\(place)|\(item.id)"
        return Button {
            open(item, from: place)
        } label: {
            VStack(spacing: 8) {
                MedalView(achievement: item.achievement, fraction: item.fraction, isEarned: item.isEarned, size: size)
                    .heroMatch("medal-\(key)", in: opened == key ? nil : hero)
                    .opacity(opened == key ? 0 : 1)
                Text(item.achievement.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(item.isEarned ? .primary : .secondary)
                    .lineLimit(1)
                Text(item.isEarned ? (item.earnedAt?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "") : AwardFormat.progress(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .frame(width: max(size + 30, 132))
            .contentShape(Rectangle())
        }
        .buttonStyle(MedalButtonStyle())
        .help(item.achievement.detail)
    }

    private func open(_ item: AchievementProgress, from place: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { opened = "\(place)|\(item.id)" }
    }

    private func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { opened = nil }
    }
}

private struct MedalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct TierCount: View {
    let tier: Achievement.Tier
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: tier.ringColors + [tier.ringColors[0]], center: .center))
                    .frame(width: 44, height: 44)
                    .shadow(color: tier.ringColors[0].opacity(0.4), radius: 5, y: 2)
                // Every metal is light: black reads on all of them, white on none.
                Text("\(count)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.black.opacity(0.82))
            }
            Text(tier.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 60)
    }
}

/// A locked achievement with its progress, for "Almost there".
private struct AwardRow: View {
    let item: AchievementProgress
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                MedalView(achievement: item.achievement, fraction: item.fraction, isEarned: false, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.achievement.title)
                        .font(.headline)
                    Text(item.achievement.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    ProgressBar(progress: item.fraction, color: item.achievement.family.goalColor)
                    Text(AwardFormat.progress(item))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: item.achievement.family.tint, cornerRadius: 20, padding: 14)
        }
        .buttonStyle(MedalButtonStyle())
    }
}

/// An opened achievement: its medal, large, with what it takes and when it was earned.
private struct AwardDetail: View {
    let item: AchievementProgress
    let heroID: String
    let hero: Namespace.ID
    var onClose: () -> Void
    @State private var spin = false

    var body: some View {
        VStack(spacing: 18) {
            MedalView(achievement: item.achievement, fraction: item.fraction, isEarned: item.isEarned, size: 170)
                .heroMatch(heroID, in: hero)
                .rotation3DEffect(.degrees(spin ? 360 : 0), axis: (x: 0, y: 1, z: 0))
                .onTapGesture {
                    guard item.isEarned else { return }
                    withAnimation(.spring(response: 1.1, dampingFraction: 0.7)) { spin.toggle() }
                }
            VStack(spacing: 6) {
                Text(item.achievement.tier.title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(item.achievement.tier.labelColor)
                Text(item.achievement.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(item.achievement.detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let date = item.earnedAt {
                Label("Earned \(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.success)
            } else {
                VStack(spacing: 8) {
                    ProgressBar(progress: item.fraction, color: item.achievement.family.goalColor)
                        .frame(width: 260)
                    Text(AwardFormat.progress(item))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Button("Close", action: onClose)
                .secondaryActionStyle(.secondary, compact: true)
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
        }
        .padding(34)
        .frame(width: 420)
        .glassCard(tint: item.achievement.family.tint, cornerRadius: 30, padding: 0, highlighted: item.isEarned)
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Medal

/// A medal: a ring in the tier's metal around a glossy disc in the family's colors. Locked
/// medals are muted, with their progress drawn around the ring.
struct MedalView: View {
    let achievement: Achievement
    var fraction: Double = 1
    var isEarned = true
    var size: CGFloat = 64
    @Environment(\.palette) private var palette

    var body: some View {
        let tier = achievement.tier
        // A deep shade of the family's color, so the white symbol reads on it in dark mode too.
        let tint = palette.colors.deep(achievement.family.goalColor)
        let ring = size * 0.09
        ZStack {
            if isEarned {
                Circle()
                    .fill(AngularGradient(colors: tier.ringColors + [tier.ringColors[0]], center: .center, angle: .degrees(-60)))
                    .shadow(color: tier.ringColors[0].opacity(0.45), radius: size * 0.1, y: size * 0.04)
                Circle()
                    .fill(LinearGradient(colors: [tint.blended(with: .white, by: 0.25), tint, tint.blended(with: .black, by: 0.25)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(ring)
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: max(1, size * 0.015))
                    .padding(ring)
                Image(systemName: achievement.symbol)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: size * 0.02, y: size * 0.015)
                // A gloss across the top, as on a glazed badge.
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .padding(ring)
                    .mask(Ellipse().frame(width: size * 0.82, height: size * 0.5).offset(y: -size * 0.2))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            } else {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: ring)
                    .padding(ring / 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(LinearGradient(colors: tier.ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: ring, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(ring / 2)
                Circle()
                    .fill(.primary.opacity(0.06))
                    .padding(ring * 1.4)
                Image(systemName: achievement.symbol)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(achievement.title), \(isEarned ? "earned" : "\(Int(fraction * 100)) percent")")
    }
}

extension Achievement.Tier {
    /// The tier's metal, muted to sit with the calm palettes: copper, silver, soft gold and an
    /// icy platinum, each still plain to tell from the others.
    var ringColors: [Color] {
        let metal: [OKLCH] = switch self {
        case .bronze: [OKLCH(0.66, 0.085, 55), OKLCH(0.8, 0.065, 65), OKLCH(0.52, 0.075, 50)]
        case .silver: [OKLCH(0.78, 0.008, 250), OKLCH(0.95, 0.004, 250), OKLCH(0.62, 0.01, 250)]
        case .gold: [OKLCH(0.8, 0.105, 85), OKLCH(0.92, 0.075, 95), OKLCH(0.66, 0.1, 75)]
        case .platinum: [OKLCH(0.84, 0.03, 225), OKLCH(0.93, 0.015, 250), OKLCH(0.97, 0.006, 240), OKLCH(0.76, 0.03, 245)]
        }
        return metal.map { Color($0) }
    }

    /// The tier's name as text: a deep shade of its metal in light mode and a light one in dark,
    /// each 4.5:1 or better on glass, where the metal itself is too pale to read.
    var labelColor: Color {
        let (light, dark): (OKLCH, OKLCH) = switch self {
        case .bronze: (OKLCH(0.48, 0.08, 50), OKLCH(0.8, 0.065, 60))
        case .silver: (OKLCH(0.48, 0.01, 250), OKLCH(0.85, 0.006, 250))
        case .gold: (OKLCH(0.47, 0.085, 80), OKLCH(0.85, 0.09, 90))
        case .platinum: (OKLCH(0.48, 0.035, 240), OKLCH(0.88, 0.02, 235))
        }
        return .dynamic(named: "momentum.tier.\(self)", light: light.inSRGB, dark: dark.inSRGB)
    }
}

extension Achievement.Family {
    var tint: Color { goalColor.color }

    var goalColor: GoalColor {
        switch self {
        case .consistency: .green
        case .streaks: .orange
        case .focus: .indigo
        case .reading: .brown
        case .milestones: .pink
        case .journal: .teal
        case .craft: .purple
        }
    }
}

enum AwardFormat {
    /// "4 of 7 days", "12.5 of 100 hours".
    static func progress(_ item: AchievementProgress) -> String {
        let achievement = item.achievement
        let unit: String = switch achievement.metric {
        case .activeDays, .perfectDays, .perfectRun, .dailyStreak: "days"
        case .weeklyStreak: "weeks"
        case .focusHours, .bestWeekFocusHours: "hours"
        case .longestSessionMinutes: "minutes"
        case .booksFinished: "books"
        case .pagesRead: "pages"
        case .milestonesCompleted: "milestones"
        case .journalReflections, .journalPlans: "days"
        case .activeGoals: "goals"
        case .anyProgress, .comeback, .earlyBird, .nightOwl, .goalsFinished, .habitStack, .challengeWon, .event: ""
        }
        if unit.isEmpty { return item.isEarned ? "Earned" : "Not yet" }
        let value = min(item.value, achievement.target)
        let shown = value < 10 && value != value.rounded() ? String(format: "%.1f", value) : Formatting.number(value.rounded(.down))
        return "\(shown) of \(Formatting.number(achievement.target)) \(unit)"
    }
}
