import SwiftUI
import Charts

struct PlanView: View {
    @EnvironmentObject var store: Store
    @State private var showAddCategory = false
    @State private var editingCategory: BudgetCategory?

    var body: some View {
        VStack(spacing: 20) {
            hero
            if store.txns.contains(where: { !$0.income }) {
                VStack(alignment: .leading, spacing: 11) {
                    SectionHeader(title: "Plan vs actual")
                    barChart
                }
            }
            VStack(alignment: .leading, spacing: 11) {
                SectionHeader(title: "Categories")
                if store.categories.isEmpty {
                    EmptyState(icon: "chart.pie", title: "No budget categories",
                               message: "Add categories to plan your monthly spend.",
                               actionTitle: "Add category") { showAddCategory = true }
                } else {
                    VStack(spacing: 9) {
                        ForEach(store.categories) { c in
                            Button { editingCategory = c } label: { CategoryRow(c: c) }.buttonStyle(.plain)
                                .contextMenu {
                                    Button { editingCategory = c } label: { Label("Edit", systemImage: "pencil") }
                                    Button(role: .destructive) { store.remove(category: c) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Monthly plan")
        .navigationSubtitle("\(store.currentMonthName) \(Date().formatted(.dateTime.year()))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAddCategory = true } label: { Label("Add category", systemImage: "plus") }
                    Button {
                        if BudgetLiveActivity.isRunning { BudgetLiveActivity.stop() }
                        else { BudgetLiveActivity.start(month: store.currentMonthName, spent: store.spentTotal, plan: store.planTotal, daysLeft: store.daysLeftInMonth) }
                    } label: {
                        Label(BudgetLiveActivity.isRunning ? "Stop Live Activity" : "Track live", systemImage: BudgetLiveActivity.isRunning ? "stop.circle" : "bolt.badge.clock")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showAddCategory) { AddCategorySheet() }
        .sheet(item: $editingCategory) { AddCategorySheet(editing: $0) }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SPENT SO FAR").font(.caption.weight(.semibold)).foregroundStyle(Zen.ink2)
                    Text(INR.compact(store.spentTotal)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Zen.ink)
                    Text("of \(INR.compact(store.planTotal)) planned").font(.caption).foregroundStyle(Zen.ink3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(INR.compact(store.planLeft)).font(.subheadline.weight(.bold)).foregroundStyle(Zen.greenDeep)
                    Text("left to spend").font(.caption2).foregroundStyle(Zen.ink3)
                }
            }
            ZenBar(value: store.planTotal > 0 ? store.spentTotal/store.planTotal : 0, tint: AnyShapeStyle(Zen.calmGradient)).padding(.top, 14)
            Text("\(store.planPct)% of budget used · \(store.daysLeftInMonth) days left in \(store.currentMonthName)")
                .font(.caption2).foregroundStyle(Zen.ink3).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
        }
        .padding(20).zenCard(28)
    }

    private var barChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(store.planMonths) { m in
                BarMark(x: .value("Month", m.month),
                        y: .value("Used", m.pct),
                        width: .fixed(22))
                    .foregroundStyle(m.over ? Zen.caution : Zen.accent)
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text("\(m.pct)%").font(.caption2.weight(.semibold)).foregroundStyle(Zen.ink3)
                    }
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
            .frame(height: 130)

            HStack(spacing: 16) {
                legend(Zen.accent, "On plan")
                legend(Zen.caution, "Over budget")
            }
        }
        .padding(18).zenCard(26)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10)
            Text(t).font(.caption.weight(.semibold)).foregroundStyle(Zen.ink2)
        }
    }
}
