import SwiftUI

struct IncomeView: View {
    @EnvironmentObject var store: Store
    @State private var showAddStream = false
    @State private var showEditTax = false
    @State private var editingStream: IncomeStream?

    var body: some View {
        VStack(spacing: 20) {
            taxHero

            VStack(alignment: .leading, spacing: 11) {
                SectionHeader(title: "Income streams", actionLabel: "Add") { showAddStream = true }
                if store.incomeStreams.isEmpty {
                    EmptyState(icon: "indianrupeesign.circle", title: "No income added",
                               message: "Add your salary, consulting, or other income to compute presumptive tax.",
                               actionTitle: "Add income") { showAddStream = true }
                } else {
                    VStack(spacing: 9) {
                        ForEach(store.incomeStreams) { s in
                            Button { editingStream = s } label: { streamRow(s) }.buttonStyle(.plain)
                            .contextMenu {
                                Button { editingStream = s } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { store.remove(stream: s) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }

            if store.grossIncome > 0 {
                VStack(alignment: .leading, spacing: 11) {
                    SectionHeader(title: "Taxable income — 44ADA")
                    breakdownCard
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                SectionHeader(title: "Advance tax schedule")
                if store.taxTotal <= 0 {
                    EmptyState(icon: "doc.text", title: "No tax set",
                               message: "Enter your estimated annual tax and what you've paid so far.",
                               actionTitle: "Set tax") { showEditTax = true }
                } else {
                    scheduleCard
                }
            }
        }
        .navigationTitle("Income & Tax")
        .navigationSubtitle("\(store.financialYearLabel) · new regime")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showEditTax = true } label: { Image(systemName: "slider.horizontal.3") } } }
        .task { await store.refreshFX() }
        .sheet(isPresented: $showAddStream) { AddIncomeStreamSheet() }
        .sheet(isPresented: $showEditTax) { EditTaxSheet() }
        .sheet(item: $editingStream) { AddIncomeStreamSheet(editing: $0) }
    }

    private func streamRow(_ s: IncomeStream) -> some View {
        HStack(spacing: 12) {
            IconChip(symbol: s.symbol, size: 40, tint: Zen.greenDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.subheadline.weight(.bold)).foregroundStyle(Zen.ink)
                Text(subtitle(s)).font(.caption2).foregroundStyle(Zen.ink3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(INR.compact(store.inrAnnual(s))).font(.subheadline.weight(.bold)).foregroundStyle(Zen.ink)
                if s.currency != "INR" { Text("@ ₹\(String(format: "%.1f", store.fxRate(s.currency)))").font(.caption2).foregroundStyle(Zen.ink3) }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 14).zenCard(20)
    }

    private func subtitle(_ s: IncomeStream) -> String {
        var parts: [String] = ["\(Currencies.symbol(s.currency))\(Int(s.perPeriodAmount))/\(s.periodLabel)"]
        if let acc = store.bankName(s.accountId) { parts.append(acc) }
        if let d = s.creditDay { parts.append("day \(d)") }
        return parts.joined(separator: " · ")
    }

    private var taxHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOTAL TAX PAYABLE").font(.caption.weight(.semibold)).foregroundStyle(Zen.ink2)
            Text(INR.compact(store.taxTotal)).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(Zen.ink)
            Text("incl. cess · 44ADA presumptive").font(.caption2).foregroundStyle(Zen.ink3).padding(.top, 2)
            HStack(spacing: 10) {
                miniStat("Advance paid", INR.compact(store.taxPaid), Zen.greenDeep, Zen.green)
                miniStat("Pending", INR.compact(store.taxPending), Zen.ink2, Zen.caution)
            }.padding(.top, 16)
            ZenBar(value: store.taxTotal > 0 ? Double(store.taxPaidPct)/100 : 0, tint: AnyShapeStyle(Zen.green)).padding(.top, 14)
            HStack {
                Text("\(store.taxPaidPct)% paid").font(.caption2).foregroundStyle(Zen.ink3)
                Spacer()
                Text("ITR due \(store.filingDue)").font(.caption2).foregroundStyle(Zen.ink3)
            }.padding(.top, 7)
        }
        .padding(22).zenCard(30)
    }

    private func miniStat(_ t: String, _ v: String, _ c: Color, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption2.weight(.semibold)).foregroundStyle(Zen.ink2)
            Text(v).font(.title3.weight(.bold)).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassEffect(.regular.tint(tint.opacity(0.16)), in: .rect(cornerRadius: 16))
    }

    private var breakdownCard: some View {
        VStack(spacing: 12) {
            row("Gross professional receipts", store.grossIncome, Zen.ink)
            row("Presumptive income (50%)", store.presumptiveIncome, Zen.ink)
            row("Less: 80C / 80D deductions", -store.deductions, Zen.greenDeep)
            Divider().overlay(Zen.track)
            row("Net taxable income", store.taxableIncome, Zen.ink, bold: true)
        }
        .padding(18).zenCard(26)
    }

    private func row(_ t: String, _ v: Double, _ c: Color, bold: Bool = false) -> some View {
        HStack {
            Text(t).font(.subheadline.weight(bold ? .bold : .medium)).foregroundStyle(bold ? Zen.ink : Zen.ink2)
            Spacer()
            Text((v < 0 ? "− " : "") + INR.compact(abs(v))).font(.subheadline.weight(bold ? .bold : .semibold)).foregroundStyle(c)
        }
    }

    // Advance-tax instalments — tap to mark each one paid.
    private var scheduleCard: some View {
        let labels = ["15 Jun", "15 Sep", "15 Dec", "15 Mar"]
        return VStack(spacing: 0) {
            ForEach(Array(Store.advancePcts.enumerated()), id: \.offset) { i, pct in
                let cumulative = store.taxTotal * pct
                let paid = store.advanceTaxPaidStages.contains(i)
                Button { store.toggleAdvanceStage(i) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: paid ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(paid ? Zen.green : Zen.ink3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(labels[i]).font(.subheadline.weight(.bold)).foregroundStyle(Zen.ink)
                            Text("\(Int(pct*100))% · \(INR.compact(cumulative))").font(.caption2).foregroundStyle(Zen.ink3)
                        }
                        Spacer()
                        Text(paid ? "Paid" : "Mark paid").font(.caption.weight(.bold)).foregroundStyle(paid ? Zen.greenDeep : Zen.accentDeep)
                    }
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                if i < Store.advancePcts.count - 1 { Divider().overlay(Zen.track).padding(.leading, 36) }
            }
        }
        .padding(.horizontal, 16).zenCard(26)
    }
}
