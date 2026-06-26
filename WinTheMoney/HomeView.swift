import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var sheet: HomeSheet?

    enum HomeSheet: Identifiable { case settings, txns, upload, accounts
        var id: Int { hashValue } }

    var body: some View {
        VStack(spacing: 22) {
            hero
            statRow

            section("This month's plan", "All →", { store.tab = .plan }) {
                if store.categories.isEmpty {
                    EmptyState(icon: "chart.pie", title: "No budget yet",
                               message: "Set up monthly categories to track your spending.",
                               actionTitle: "Add category") { store.tab = .plan }
                } else {
                    VStack(spacing: 9) {
                        ForEach(store.top3) { c in
                            Button { store.tab = .plan } label: { CategoryRow(c: c, compact: true) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            section("Accounts", "Manage →", { sheet = .accounts }) {
                if store.banks.isEmpty {
                    EmptyState(icon: "building.columns", title: "No accounts linked",
                               message: "Add an account manually, import a statement, or connect via Account Aggregator.",
                               actionTitle: "Add account") { sheet = .accounts }
                } else { accountsCarousel }
            }

            section("Recent activity", "See all →", { sheet = .txns }) {
                if store.txns.isEmpty {
                    EmptyState(icon: "list.bullet.rectangle", title: "No transactions",
                               message: "Import a bank statement (PDF) or add a transaction by hand.",
                               actionTitle: "Import statement") { sheet = .upload }
                } else { recentCard }
            }
        }
        .navigationTitle(store.userName.isEmpty ? "Good morning" : "Good morning, \(store.userName)")
        .navigationSubtitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.tab = .goals } label: {
                    Label("Lv \(store.level)", systemImage: "bolt.fill").labelStyle(.titleAndIcon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .settings } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .settings: SettingsSheet()
            case .txns: TransactionsSheet()
            case .upload: UploadSheet()
            case .accounts: AccountsView()
            }
        }
    }

    // generic titled section
    @ViewBuilder
    private func section<C: View>(_ title: String, _ action: String?, _ act: (() -> Void)?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: title, actionLabel: action, action: act)
            content()
        }
    }

    // MARK: hero
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LIQUID NET WORTH").font(.caption.weight(.semibold)).foregroundStyle(Zen.ink2)
            HStack(alignment: .center) {
                Text(INR.compact(store.liquidNetWorth)).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(Zen.ink)
                Spacer()
                Button { store.tab = .wealth } label: {
                    Sparkline(points: Array(store.nwHistory.suffix(7)), tint: Zen.accent)
                        .frame(width: 66, height: 30)
                }.buttonStyle(.plain)
            }
            .padding(.top, 2)
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                Text("\(INR.compact(store.nwChange)) this month")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Zen.greenDeep)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .glassEffect(.regular.tint(Zen.green.opacity(0.18)), in: .capsule)
            .padding(.top, 8)

            VStack(spacing: 7) {
                HStack {
                    Label("Road to \(store.targetLabel)", systemImage: "leaf").font(.caption.weight(.semibold)).foregroundStyle(Zen.ink2)
                    Spacer()
                    Text("\(store.toTargetPct)% · \(INR.compact(store.toTarget)) to go").font(.caption.weight(.bold)).foregroundStyle(Zen.ink)
                }
                ZenBar(value: Double(store.toTargetPct)/100, tint: AnyShapeStyle(Zen.calmGradient))
            }
            .padding(.top, 18)
        }
        .padding(22)
        .zenCard(tinted: Zen.accent, 30)
    }

    // MARK: stat row
    private var statRow: some View {
        HStack(spacing: 12) {
            Button { store.tab = .plan } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THIS MONTH").font(.caption2.weight(.semibold)).foregroundStyle(Zen.ink2)
                    Text(INR.compact(store.spentTotal)).font(.title2.weight(.bold)).foregroundStyle(Zen.ink)
                    Text("of \(INR.compact(store.planTotal)) planned").font(.caption2).foregroundStyle(Zen.ink3)
                    ZenBar(value: store.planTotal > 0 ? store.spentTotal/store.planTotal : 0).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).zenCard(22, interactive: true)
            }.buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("ON-PLAN STREAK").font(.caption2.weight(.semibold)).foregroundStyle(Zen.ink2)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(Zen.green)
                    Text("\(store.streakMonths)").font(.title.weight(.bold)).foregroundStyle(Zen.ink)
                    Text("months").font(.subheadline).foregroundStyle(Zen.ink3)
                }
                Text(store.streakMonths > 0 ? "Keep it calm" : "Stay on plan to build a streak").font(.caption2).foregroundStyle(Zen.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).zenCard(22)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accountsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.banks) { b in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            Text(b.logo).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(Circle().fill(Color(hex: b.colorHex)))
                            Text("••\(b.mask)").font(.caption2.weight(.semibold)).foregroundStyle(Zen.ink3)
                        }
                        Text(INR.compact(b.balance)).font(.title3.weight(.bold)).foregroundStyle(Zen.ink).padding(.top, 10)
                        Text(b.name).font(.caption2).foregroundStyle(Zen.ink3).padding(.top, 1)
                    }
                    .padding(14).frame(width: 132, alignment: .leading).zenCard(20)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var recentCard: some View {
        VStack(spacing: 0) {
            ForEach(store.recent) { t in
                HStack(spacing: 12) {
                    IconChip(symbol: t.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.merchant).font(.subheadline.weight(.semibold)).foregroundStyle(Zen.ink)
                        Text("\(t.category) · \(t.account)").font(.caption2).foregroundStyle(Zen.ink3)
                    }
                    Spacer()
                    Text((t.income ? "+" : "−") + INR.full(abs(t.amount)))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(t.income ? Zen.greenDeep : Zen.ink)
                }
                .padding(.vertical, 11)
                if t.id != store.recent.last?.id { Divider().overlay(Zen.track) }
            }
            Divider().overlay(Zen.track)
            Button { sheet = .upload } label: {
                HStack(spacing: 12) {
                    IconChip(symbol: "doc.text", tint: Zen.accentDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload a statement").font(.subheadline.weight(.semibold)).foregroundStyle(Zen.ink)
                        Text("PDF statements · auto-categorised").font(.caption2).foregroundStyle(Zen.ink2)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill").foregroundStyle(Zen.accentDeep)
                }
                .padding(.vertical, 12)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .zenCard(22)
    }
}

// MARK: - Category row (shared by Home + Plan)
struct CategoryRow: View {
    var c: BudgetCategory
    var compact = false
    var body: some View {
        HStack(spacing: 12) {
            IconChip(symbol: c.symbol, size: compact ? 34 : 40, tint: Color(hex: c.color))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(c.name).font(.subheadline.weight(compact ? .semibold : .bold)).foregroundStyle(Zen.ink)
                    Spacer()
                    HStack(spacing: 3) {
                        Text(INR.compact(c.spent)).foregroundStyle(Zen.ink2)
                        Text("/ \(INR.compact(c.plan))").foregroundStyle(Zen.ink3)
                    }.font(.caption.weight(.semibold))
                }
                ZenBar(value: c.pct, tint: AnyShapeStyle(Color(hex: c.barColorHex)))
            }
            if !compact {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(c.pct*100))%").font(.subheadline.weight(.bold)).foregroundStyle(Color(hex: c.barColorHex))
                    Text("\(INR.compact(abs(c.left))) \(c.over ? "over" : "left")").font(.caption2).foregroundStyle(Zen.ink3)
                }.frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, compact ? 13 : 14)
        .zenCard(20, interactive: true)
    }
}
