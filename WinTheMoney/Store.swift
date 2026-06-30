import SwiftUI
import Combine
import WidgetKit

/// Single source of truth. No mock data: the app starts empty and is populated from
/// manual entry, PDF statement imports, or a connected Account Aggregator. Derived
/// stats (level, streak, milestones, badges, plan history) are computed from real data.
final class Store: ObservableObject {
    @Published var tab: Tab = .home

    @Published var categories: [BudgetCategory] = []
    @Published var txns: [Txn] = []
    @Published var banks: [BankAccount] = []
    @Published var cards: [CreditCard] = []
    @Published var deposits: [Deposit] = []
    @Published var goals: [Goal] = []
    @Published var milestones: [Milestone] = []
    @Published var badges: [Badge] = []
    @Published var investments: [Investment] = []

    // income & tax
    @Published var incomeStreams: [IncomeStream] = []
    @Published var taxProfile = TaxProfile()              // inputs for the slab-based estimate
    @Published var payslips: [Payslip] = []               // imported/entered salary slips
    @Published var advanceTaxPaidStages: Set<Int> = []   // which of the 4 instalments are marked paid

    /// Learned merchant/counterparty → category name (auto-applied on import).
    @Published var merchantRules: [String: String] = [:]

    // live FX rates (currency → INR), persisted & refreshed
    @Published var fxRates: [String: Double] = ["INR": 1]

    // net worth history (one point per day, built from real balances)
    @Published var nwHistory: [Double] = []

    @Published var userName: String = UserDefaults.standard.string(forKey: "wtm_user_name") ?? "" {
        didSet { UserDefaults.standard.set(userName, forKey: "wtm_user_name") }
    }
    @Published var netWorthTarget: Double = (UserDefaults.standard.object(forKey: "wtm_nw_target") as? Double) ?? 5_000_000 {
        didSet { UserDefaults.standard.set(netWorthTarget, forKey: "wtm_nw_target") }
    }
    /// When true, all Account Aggregator UI is hidden — statement upload + manual only.
    @Published var preferStatementImport: Bool = UserDefaults.standard.bool(forKey: "wtm_prefer_statement") {
        didSet { UserDefaults.standard.set(preferStatementImport, forKey: "wtm_prefer_statement") }
    }
    /// Account Aggregator (Setu) is OFF unless the user explicitly opts in. No sync ever runs otherwise.
    @Published var accountAggregatorEnabled: Bool = UserDefaults.standard.bool(forKey: "wtm_aa_enabled") {
        didSet { UserDefaults.standard.set(accountAggregatorEnabled, forKey: "wtm_aa_enabled") }
    }
    @Published var notificationsEnabled: Bool = UserDefaults.standard.bool(forKey: "wtm_notifs") {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "wtm_notifs") }
    }
    @Published var autoBackupEnabled: Bool = (UserDefaults.standard.object(forKey: "wtm_autobackup") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoBackupEnabled, forKey: "wtm_autobackup") }
    }

    /// Write a backup now (Files + iCloud Drive when available). Returns where it landed.
    @discardableResult
    func backupNow() -> String { BackupManager.write(exportBundle()) }
    /// Called when the app backgrounds.
    func autoBackupIfEnabled() { if autoBackupEnabled, hasData { _ = backupNow() } }
    /// Restore the most recent auto-backup; returns success.
    @discardableResult
    func restoreLatestBackup() -> Bool {
        guard let data = BackupManager.latestData() else { return false }
        return importBundle(data, replace: true)
    }

    var targetLabel: String { INR.compact(netWorthTarget) }

    private let key = "win_the_money_v1"
    private let nwDayKey = "wtm_nw_day"

    init() {
        load()
        if let t = ProcessInfo.processInfo.environment["WTM_TAB"], let forced = Tab(rawValue: t) { tab = forced }
        // One-time retroactive re-categorisation when the brand library version bumps.
        let catLibVersion = 2
        if UserDefaults.standard.integer(forKey: "wtm_cat_lib_v") < catLibVersion, !txns.isEmpty {
            recategorizeAll()
        }
        UserDefaults.standard.set(catLibVersion, forKey: "wtm_cat_lib_v")
        publishSnapshot()
        Task { await refreshFX() }
    }

    // MARK: derived totals
    var investmentsTotal: Double { investments.map(\.currentValue).reduce(0,+) }
    var liquidNetWorth: Double { banks.map(\.balance).reduce(0,+) + deposits.map(\.current).reduce(0,+) + investmentsTotal }
    var totalTracked: Double { liquidNetWorth - cards.map(\.outstanding).reduce(0,+) }
    var nwChange: Double { nwHistory.count >= 2 ? nwHistory.last! - nwHistory[nwHistory.count-2] : 0 }
    var nwChangePct: Double {
        guard nwHistory.count >= 2, nwHistory[nwHistory.count-2] != 0 else { return 0 }
        return nwChange / nwHistory[nwHistory.count-2] * 100
    }
    var toTarget: Double { max(0, netWorthTarget - liquidNetWorth) }
    var toTargetPct: Int { netWorthTarget > 0 ? Int(min(100, liquidNetWorth / netWorthTarget * 100)) : 0 }

    var spentTotal: Double { monthSpend(monthsAgo: 0) }
    /// Sum of caps normalised to per-month, so quarterly/annual caps fold into the monthly overview.
    var planTotal: Double { categories.map(\.monthlyPlan).reduce(0,+) }
    var planLeft: Double { planTotal - spentTotal }
    var planPct: Int { planTotal > 0 ? Int((spentTotal/planTotal*100).rounded()) : 0 }
    var top3: [BudgetCategory] { Array(categories.sorted { $0.spent > $1.spent }.prefix(3)) }
    var recent: [Txn] { Array(txns.sorted { $0.date > $1.date }.prefix(5)) }

    var banksTotal: Double { banks.map(\.balance).reduce(0,+) }
    var cardsTotal: Double { cards.map(\.outstanding).reduce(0,+) }
    var depositsTotal: Double { deposits.map(\.current).reduce(0,+) }

    var hasData: Bool { !banks.isEmpty || !txns.isEmpty || !deposits.isEmpty || !cards.isEmpty }

    var segments: [Segment] {
        [ Segment(label: "Bank balances", value: banksTotal, colorHex: "6E9BD8"),
          Segment(label: "Investments", value: investmentsTotal, colorHex: "5BA585"),
          Segment(label: "FD & RD", value: depositsTotal, colorHex: "7FC4A3"),
          Segment(label: "Credit owed", value: -cardsTotal, colorHex: "9AA7BE") ]
            .filter { $0.value != 0 }
    }

    // MARK: income & tax (multi-currency; converted to INR via live FX)
    func fxRate(_ currency: String) -> Double {
        currency == "INR" ? 1 : (fxRates[currency] ?? Currencies.fallbackINR[currency] ?? 1)
    }
    func inrAnnual(_ s: IncomeStream) -> Double { s.annual * fxRate(s.currency) }
    func bankName(_ id: UUID?) -> String? { id.flatMap { i in banks.first { $0.id == i }?.name } }
    var grossIncome: Double { incomeStreams.map { inrAnnual($0) }.reduce(0,+) }

    /// The slab-based tax estimate for the current profile (both regimes + recommendation).
    var tax: TaxComputation { TaxEngine.compute(taxProfile, fyStreamsSalary: grossIncome) }
    var taxTotal: Double { tax.totalTax }

    func updateTaxProfile(_ p: TaxProfile) { taxProfile = p; save() }
    func addPayslip(_ s: Payslip) { payslips.insert(s, at: 0); applyPayslipsToProfile(); save() }
    func remove(payslip: Payslip) { payslips.removeAll { $0.id == payslip.id }; applyPayslipsToProfile(); save() }

    /// Roll up imported payslips into the salary track: project annual gross from the slips' average
    /// and sum their TDS. Only fills figures the user hasn't manually overridden to non-zero values.
    func applyPayslipsToProfile() {
        guard !payslips.isEmpty else { return }
        let months = Double(payslips.count)
        let avgGross = payslips.map(\.grossEarnings).reduce(0,+) / max(1, months)
        var p = taxProfile
        if p.track == .selfEmployed || p.track == .business { p.track = .mixed }   // they have salary now
        else if p.track == .salaried || p.grossSalary == 0 { /* salaried stays */ }
        p.grossSalary = max(p.grossSalary, (avgGross * 12).rounded())   // projected annual
        p.tdsPaid = payslips.map(\.tds).reduce(0,+)                     // YTD TDS from slips
        let pf = payslips.map(\.pf).reduce(0,+)
        if p.ded80C < pf { p.ded80C = min(150_000, pf * (12 / max(1, months))) }   // PF is 80C-eligible (projected)
        p.seeded = true
        taxProfile = p
    }
    /// Advance-tax instalment cumulative percentages (15/45/75/100).
    static let advancePcts: [Double] = [0.15, 0.45, 0.75, 1.0]
    /// Derived from which instalments are marked paid.
    var taxPaid: Double {
        advanceTaxPaidStages.reduce(0.0) { acc, i in
            guard i >= 0, i < Self.advancePcts.count else { return acc }
            let prev = i == 0 ? 0 : Self.advancePcts[i - 1]
            return acc + (Self.advancePcts[i] - prev) * taxTotal
        }
    }
    var taxPending: Double { max(0, taxTotal - taxPaid) }
    var taxPaidPct: Int { taxTotal > 0 ? Int((taxPaid/taxTotal*100).rounded()) : 0 }
    func toggleAdvanceStage(_ i: Int) {
        if advanceTaxPaidStages.contains(i) { advanceTaxPaidStages.remove(i) } else { advanceTaxPaidStages.insert(i) }
        save()
    }
    /// ITR due = 31 Jul of the assessment year (year after the current FY's March end).
    var filingDue: String {
        let cal = Calendar.current, now = Date()
        let y = cal.component(.year, from: now)
        let fyEndYear = cal.component(.month, from: now) >= 4 ? y + 1 : y   // FY Apr–Mar
        return "31 Jul \(fyEndYear)"
    }
    var financialYearLabel: String {
        let cal = Calendar.current, now = Date()
        let y = cal.component(.year, from: now) % 100
        let start = cal.component(.month, from: now) >= 4 ? y : y - 1
        return "FY \(start)–\(start + 1)"
    }

    // MARK: gamification — all derived from real data
    var xp: Int {
        goals.filter { $0.status == .achieved }.count * 300
        + milestones.filter(\.reached).count * 250
        + min(txns.count, 300) * 5
    }
    var level: Int { max(1, xp / 1000 + 1) }
    var nextLevelXP: Int { level * 1000 }
    var levelName: String {
        ["Saver", "Saver", "Builder", "Investor", "Strategist", "Master"][min(level, 5)]
    }
    /// Consecutive most-recent months that stayed within plan.
    var streakMonths: Int {
        var s = 0
        for m in planMonths.reversed() { if m.pct > 0 && m.pct <= 100 { s += 1 } else { break } }
        return s
    }

    // MARK: plan history — computed from real transactions
    private func monthSpend(monthsAgo i: Int) -> Double {
        let cal = Calendar.current
        guard let d = cal.date(byAdding: .month, value: -i, to: Date()) else { return 0 }
        return max(0, txns.filter { cal.isDate($0.date, equalTo: d, toGranularity: .month) }
            .map(spendContribution).reduce(0, +))
    }

    /// Net spend a transaction contributes: debits add, refunds subtract, transfers/income ignored.
    func spendContribution(_ t: Txn) -> Double {
        if t.transfer { return 0 }
        if t.amount < 0 { return abs(t.amount) }
        if t.isRefund { return -abs(t.amount) }   // refund credit nets against spend
        return 0
    }
    // MARK: insights aggregations (exclude transfers; debit-only grouping)
    private func txnsInLast(months: Int) -> [Txn] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        guard let from = cal.date(byAdding: .month, value: -(max(1, months) - 1), to: start) else { return txns }
        return txns.filter { $0.date >= from }
    }
    /// Net spend grouped by tag (a txn counts toward each of its tags). Sorted desc.
    func spendByTag(months: Int) -> [(tag: String, amount: Double)] {
        var m: [String: Double] = [:]
        for t in txnsInLast(months: months) {
            let c = spendContribution(t); guard c > 0 else { continue }
            if t.tags.isEmpty { m["Untagged", default: 0] += c }
            else { for tag in t.tags { m[tag, default: 0] += c } }
        }
        return m.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
    /// Net spend grouped by canonical brand (BrandCatalog, fallback merchant). Sorted desc.
    func spendByBrand(months: Int) -> [(brand: String, amount: Double)] {
        var m: [String: Double] = [:]
        for t in txnsInLast(months: months) {
            let c = spendContribution(t); guard c > 0 else { continue }
            let brand = BrandCatalog.classify([t.merchant, t.counterparty ?? ""].joined(separator: " ")).brand ?? t.merchant
            m[brand, default: 0] += c
        }
        return m.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
    func monthlyTagSpend(_ tag: String, months: Int) -> [Double] {
        let cal = Calendar.current
        return (0..<max(1, months)).reversed().map { i in
            guard let d = cal.date(byAdding: .month, value: -i, to: Date()) else { return 0 }
            return txns.filter { $0.tags.contains(tag) && cal.isDate($0.date, equalTo: d, toGranularity: .month) }
                .map(spendContribution).reduce(0, +)
        }
    }

    /// Single source of truth for category spend, applying transfer/refund rules. Each category's
    /// `spent` is the net spend within *its own* current cap cycle (monthly by default, but a
    /// quarterly/annual/custom cap counts spend over that whole window — e.g. a yearly insurance cap).
    func recomputeSpent() {
        for i in categories.indices {
            let (start, end) = cycleWindow(for: categories[i])
            let name = categories[i].name
            let total = txns.filter { $0.category == name && $0.date >= start && $0.date < end }
                .map(spendContribution).reduce(0, +)
            categories[i].spent = max(0, total)
        }
    }

    /// First day of the financial year (Apr–Mar, India) containing `d`. Default cap-cycle anchor.
    static func financialYearStart(_ d: Date = Date()) -> Date {
        let cal = Calendar.current
        let y = cal.component(.year, from: d)
        let startYear = cal.component(.month, from: d) >= 4 ? y : y - 1
        return cal.date(from: DateComponents(year: startYear, month: 4, day: 1)) ?? d
    }

    /// The [start, end) of the cap cycle that currently contains today, for category `c`. Monthly and
    /// quarterly align to the calendar; annual/custom step from the category anchor (else the FY start).
    func cycleWindow(for c: BudgetCategory) -> (Date, Date) {
        let cal = Calendar.current, now = Date()
        switch c.period {
        case .monthly:
            let start = cal.dateInterval(of: .month, for: now)?.start ?? now
            return (start, cal.date(byAdding: .month, value: 1, to: start) ?? now)
        case .quarterly:
            let m = cal.component(.month, from: now)
            let qStartMonth = ((m - 1) / 3) * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: qStartMonth, day: 1)) ?? now
            return (start, cal.date(byAdding: .month, value: 3, to: start) ?? now)
        case .annual, .custom:
            let len = c.periodMonths
            let anchor = c.anchor ?? Self.financialYearStart(now)
            let monthsSince = cal.dateComponents([.month], from: anchor, to: now).month ?? 0
            let k = max(0, monthsSince / len)
            let start = cal.date(byAdding: .month, value: k * len, to: anchor) ?? anchor
            return (start, cal.date(byAdding: .month, value: len, to: start) ?? now)
        }
    }
    var planMonths: [PlanMonth] {
        let cal = Calendar.current
        return (0...5).reversed().compactMap { i -> PlanMonth? in
            guard let d = cal.date(byAdding: .month, value: -i, to: Date()) else { return nil }
            let spend = monthSpend(monthsAgo: i)
            let pct = planTotal > 0 ? Int((spend/planTotal*100).rounded()) : 0
            return PlanMonth(month: d.formatted(.dateTime.month(.abbreviated)), pct: pct, over: pct > 100)
        }
    }
    var currentMonthName: String { Date().formatted(.dateTime.month(.wide)) }
    var daysLeftInMonth: Int {
        let cal = Calendar.current, now = Date()
        let total = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        return max(0, total - cal.component(.day, from: now))
    }

    // MARK: goal actions
    func cycleGoalStatus(_ goal: Goal) {
        guard let i = goals.firstIndex(of: goal), goals[i].status != .achieved else { return }
        goals[i].status = goals[i].status.next; save()
    }
    func setGoalStatus(_ goal: Goal, _ status: GoalStatus) {
        guard let i = goals.firstIndex(of: goal) else { return }
        goals[i].status = status; save()
    }
    func reactivate(_ goal: Goal) { setGoalStatus(goal, .onTrack) }
    func pause(_ goal: Goal) { setGoalStatus(goal, .paused) }

    // MARK: manual ingestion
    func addGoal(_ g: Goal) { goals.insert(g, at: 0); save() }
    func addDeposit(_ d: Deposit) { deposits.append(d); save() }
    func addBank(_ b: BankAccount) { banks.append(b); save() }
    func addCard(_ c: CreditCard) { cards.append(c); save() }
    func addCategory(_ c: BudgetCategory) { categories.append(c); save() }
    func addIncomeStream(_ s: IncomeStream) { incomeStreams.append(s); save() }
    func addInvestment(_ i: Investment) { investments.append(i); save() }

    func remove(category: BudgetCategory) {
        guard !category.isSystem else { return }   // base categories are maintained, not deletable
        categories.removeAll { $0.id == category.id }; save()
    }
    func remove(bank: BankAccount) {
        banks.removeAll { $0.id == bank.id }
        txns.removeAll { $0.account == bank.name }   // don't leave its transactions orphaned
        recomputeSpent(); save()
    }
    func remove(card: CreditCard) {
        cards.removeAll { $0.id == card.id }
        txns.removeAll { $0.account == card.name }
        recomputeSpent(); save()
    }
    func remove(deposit: Deposit) { deposits.removeAll { $0.id == deposit.id }; save() }
    func remove(goal: Goal) { goals.removeAll { $0.id == goal.id }; save() }
    func remove(stream: IncomeStream) { incomeStreams.removeAll { $0.id == stream.id }; save() }
    func remove(investment: Investment) { investments.removeAll { $0.id == investment.id }; save() }

    // MARK: edit (update in place by id)
    func update(_ b: BankAccount) {
        guard let i = banks.firstIndex(where: { $0.id == b.id }) else { return }
        let oldName = banks[i].name
        banks[i] = b
        if oldName != b.name { for j in txns.indices where txns[j].account == oldName { txns[j].account = b.name } }
        save()
    }
    func update(_ c: CreditCard) {
        guard let i = cards.firstIndex(where: { $0.id == c.id }) else { return }
        let oldName = cards[i].name
        cards[i] = c
        if oldName != c.name { renameAccountTxns(from: oldName, to: c.name) }
        save()
    }
    func update(_ d: Deposit) { if let i = deposits.firstIndex(where: { $0.id == d.id }) { deposits[i] = d; save() } }
    func update(_ g: Goal) { if let i = goals.firstIndex(where: { $0.id == g.id }) { goals[i] = g; save() } }
    func update(_ s: IncomeStream) { if let i = incomeStreams.firstIndex(where: { $0.id == s.id }) { incomeStreams[i] = s; save() } }
    func update(_ inv: Investment) { if let i = investments.firstIndex(where: { $0.id == inv.id }) { investments[i] = inv; save() } }
    func update(_ c: BudgetCategory) {
        guard let i = categories.firstIndex(where: { $0.id == c.id }) else { return }
        var c = c
        let oldName = categories[i].name
        if categories[i].isSystem { c.name = oldName; c.isSystem = true }   // base names are locked
        categories[i] = c
        if oldName != c.name { for j in txns.indices where txns[j].category == oldName { txns[j].category = c.name } }
        save()
    }
    /// Edit a transaction: reverse its old balance effect, apply the new, recompute spend.
    func update(_ t: Txn) {
        guard let i = txns.firstIndex(where: { $0.id == t.id }) else { return }
        let old = txns[i]
        if let bi = banks.firstIndex(where: { $0.name == old.account }) { banks[bi].balance -= old.amount }
        txns[i] = t
        if let bi = banks.firstIndex(where: { $0.name == t.account }) { banks[bi].balance += t.amount }
        recomputeSpent()
        save()
        // If the user recategorised, remember it for this merchant/counterparty.
        if old.category != t.category, !t.income {
            let key = t.counterparty ?? t.merchant
            if !key.isEmpty { learnMerchant(key, category: t.category) }
        }
    }

    // MARK: live quotes (stocks via optional API, mutual funds via AMFI NAV)
    @MainActor
    func refreshQuotes() async {
        let updated = await QuoteProvider.shared.refresh(investments)
        guard !updated.isEmpty else { return }
        for inv in updated { if let i = investments.firstIndex(where: { $0.id == inv.id }) { investments[i] = inv } }
        save()
    }

    @MainActor
    func refreshFX() async {
        let codes = Array(Set(incomeStreams.map(\.currency)))
        guard codes.contains(where: { $0 != "INR" }) else { return }
        let r = await FXProvider.shared.ratesToINR(codes)
        guard !r.isEmpty else { return }
        for (k, v) in r { fxRates[k] = v }
        save()
    }
    func remove(txn: Txn) {
        txns.removeAll { $0.id == txn.id }; recomputeSpent(); save()
    }

    func logTxn(_ t: Txn) {
        var t = t
        let cls = classify(merchant: t.merchant, counterparty: t.counterparty, narration: t.merchant, income: t.income)
        if t.tags.isEmpty { t.tags = cls.tags }
        if !t.transfer { t.transfer = cls.transfer }
        txns.insert(t, at: 0)
        if let bi = banks.firstIndex(where: { $0.name == t.account }) { banks[bi].balance += t.amount }
        recomputeSpent()
        save()
    }

    // MARK: widgets + live activity
    var topGoal: Goal? { goals.first { $0.active } ?? goals.first }
    func publishSnapshot() {
        let g = topGoal
        WTMSnapshot(netWorth: liquidNetWorth, netWorthChange: nwChange, spent: spentTotal, plan: planTotal,
                    targetPct: toTargetPct, topGoalTitle: g?.title ?? "No goal yet",
                    topGoalSaved: g?.saved ?? 0, topGoalTarget: g?.target ?? 1,
                    streakMonths: streakMonths, nwHistory: nwHistory, updated: Date()).save()
        WidgetCenter.shared.reloadAllTimelines()
        if BudgetLiveActivity.isRunning {
            BudgetLiveActivity.update(spent: spentTotal, plan: planTotal, daysLeft: daysLeftInMonth)
        }
    }

    // MARK: bank-sync / statement merge
    /// `adjustBalances` true only for live feeds (Gmail) where each new txn moves the
    /// running balance; statement/CSV/AA imports are historical and must not.
    @discardableResult
    func mergeSynced(accounts: [SyncedAccount], txns incoming: [SyncedTxn], adjustBalances: Bool = false, reconcile: Bool = false) -> Int {
        for a in accounts { upsertAccount(a) }
        let known = Set(self.txns.compactMap(\.externalId))
        var added = 0
        for s in incoming.sorted(by: { $0.date < $1.date }) where !known.contains(s.externalId) {
            // auto-create the source bank/card by last-4 if unseen
            if s.source == .card { ensureCard(mask: s.accountMask, bankCode: s.bankCode) }
            else if s.source == .bank { ensureBank(mask: s.accountMask, bankCode: s.bankCode) }

            let accName = accountName(forMask: s.accountMask, source: s.source)
            // Statement imports reconcile against existing alert transactions by amount+date so the
            // same event isn't stored twice with two different merchant spellings.
            if reconcile, let i = duplicateBankIndex(for: s, accountName: accName) {
                if txns[i].statementId == nil { enrichBank(&txns[i], with: s) }
                continue   // already have this transaction — don't add, don't move the balance
            }
            let merchant = s.merchant ?? Self.prettyMerchant(s.narration)
            let cl = classify(merchant: merchant, counterparty: s.counterparty, narration: s.narration, income: s.amount > 0)
            txns.insert(Txn(merchant: merchant, symbol: cl.symbol, category: cl.category, account: accName,
                            amount: s.amount, date: s.date, externalId: s.externalId,
                            source: s.source, counterparty: s.counterparty, tags: cl.tags, transfer: cl.transfer), at: 0)
            if adjustBalances {
                if s.source == .bank, let bi = banks.firstIndex(where: { $0.mask == s.accountMask }) { banks[bi].balance += s.amount }
                else if s.source == .card, let ci = cards.firstIndex(where: { $0.mask == s.accountMask }) { cards[ci].outstanding = max(0, cards[ci].outstanding - s.amount) }
            }
            added += 1
        }
        correlateTransfers()
        recomputeSpent()
        save()
        return added
    }

    /// Import a parsed statement: set the account's exact figures (outstanding/limit/product/
    /// rewards) and reconcile each statement transaction against existing alert transactions —
    /// enriching a match in place (category/merchant/source) instead of creating a duplicate.
    @discardableResult
    func mergeStatement(account: SyncedAccount, txns incoming: [SyncedTxn]) -> (added: Int, enriched: Int) {
        upsertAccount(account)
        let accName = accountName(forMask: account.mask, source: account.kind)
        let knownExt = Set(self.txns.compactMap(\.externalId))
        var added = 0, enriched = 0
        for s in incoming.sorted(by: { $0.date < $1.date }) {
            if knownExt.contains(s.externalId) { continue }                 // this exact statement row already imported
            if let i = reconcileIndex(for: s, accountName: accName) {
                enrich(&txns[i], with: s); enriched += 1
            } else {
                let merchant = s.merchant ?? Self.prettyMerchant(s.narration)
                let cl = classify(merchant: merchant, counterparty: s.counterparty, narration: s.narration, income: s.amount > 0)
                let cat = (s.category?.isEmpty == false) ? s.category! : cl.category
                let sym = categories.first { $0.name == cat }?.symbol ?? cl.symbol
                txns.insert(Txn(merchant: merchant, symbol: sym, category: cat, account: accName,
                                amount: s.amount, date: s.date, externalId: s.externalId,
                                source: s.source, counterparty: s.counterparty, statementId: s.externalId,
                                tags: cl.tags, transfer: cl.transfer), at: 0)
                added += 1
            }
        }
        correlateTransfers()
        recomputeSpent()
        save()
        return (added, enriched)
    }

    /// Finds the closest unreconciled alert transaction matching this statement row.
    private func reconcileIndex(for s: SyncedTxn, accountName: String) -> Int? {
        let target = abs(s.amount), inc = s.amount > 0
        var best: Int? = nil, bestDelta = Double.greatestFiniteMagnitude
        for (i, t) in txns.enumerated() where t.statementId == nil && t.account == accountName && t.income == inc {
            guard abs(abs(t.amount) - target) < 0.01 else { continue }
            let delta = abs(t.date.timeIntervalSince(s.date))
            if delta <= 3 * 86400, delta < bestDelta { best = i; bestDelta = delta }
        }
        return best
    }
    /// Enriches an existing transaction with the statement's better data (category, merchant, tags).
    private func enrich(_ t: inout Txn, with s: SyncedTxn) {
        if let c = s.category, !c.isEmpty {
            t.category = c
            t.symbol = categories.first { $0.name == c }?.symbol ?? Self.symbolFor(c)
        }
        if let m = s.merchant, !m.isEmpty { t.merchant = m }
        let cl = classify(merchant: t.merchant, counterparty: t.counterparty, narration: s.narration, income: t.amount > 0)
        t.tags = Self.uniq(t.tags + cl.tags)
        if cl.transfer { t.transfer = true }
        t.source = .card
        t.statementId = s.externalId
        // spend is recomputed by the caller after the merge loop
    }
    private func renameAccountTxns(from old: String, to new: String) {
        for i in txns.indices where txns[i].account == old { txns[i].account = new }
    }

    /// Reconstruct a live bank balance from a statement's stated closing: add every transaction for
    /// this account dated strictly after the statement's as-of date. This is why a May-31 statement
    /// no longer pins the balance to May when June alerts already arrived. Called *before* the
    /// statement's own (≤ asOf) transactions are inserted, so they're never double-counted.
    private func liveBalance(statedBalance: Double, asOf: Date?, accountName: String) -> Double {
        guard let asOf else { return statedBalance }
        let later = txns.filter { $0.account == accountName && $0.date > asOf }.map(\.amount).reduce(0, +)
        return statedBalance + later
    }

    /// Finds an existing transaction that is the same real-world event as `s` regardless of merchant
    /// text (alert vs statement spell the payee differently): same account, same sign, equal amount,
    /// within a few days. Used to stop bank statements from duplicating Gmail alert transactions.
    private func duplicateBankIndex(for s: SyncedTxn, accountName: String) -> Int? {
        let target = abs(s.amount), inc = s.amount > 0
        var best: Int? = nil, bestDelta = Double.greatestFiniteMagnitude
        for (i, t) in txns.enumerated() where t.account == accountName && t.income == inc {
            guard t.externalId != s.externalId, abs(abs(t.amount) - target) < 0.01 else { continue }
            let delta = abs(t.date.timeIntervalSince(s.date))
            if delta <= 4 * 86400, delta < bestDelta { best = i; bestDelta = delta }
        }
        return best
    }
    /// Enrich a prior alert transaction with a bank statement's better data (cleaner merchant,
    /// category, tags) and mark it statement-confirmed. Unlike `enrich`, never forces `.card`.
    private func enrichBank(_ t: inout Txn, with s: SyncedTxn) {
        if let m = s.merchant, !m.isEmpty, m.count > t.merchant.count { t.merchant = m }
        if let c = s.category, !c.isEmpty {
            t.category = c
            t.symbol = categories.first { $0.name == c }?.symbol ?? Self.symbolFor(c)
        }
        if (t.counterparty ?? "").isEmpty, let cp = s.counterparty { t.counterparty = cp }
        let cl = classify(merchant: t.merchant, counterparty: t.counterparty, narration: s.narration, income: t.amount > 0)
        t.tags = Self.uniq(t.tags + cl.tags)
        if cl.transfer { t.transfer = true }
        if t.statementId == nil { t.statementId = s.externalId }
    }

    /// Unique, ordered bank + card display names for pickers.
    var accountNames: [String] {
        var seen = Set<String>()
        return (banks.map(\.name) + cards.map(\.name)).filter { seen.insert($0).inserted }
    }
    /// Legacy migration: make any colliding bank/card names unique by appending ••mask.
    private func dedupeAccountNames() {
        var seen = Set<String>()
        for i in banks.indices {
            if !seen.insert(banks[i].name).inserted, !banks[i].name.contains("••") {
                banks[i].name = "\(banks[i].name) ••\(banks[i].mask)"; seen.insert(banks[i].name)
            }
        }
        for i in cards.indices {
            if !seen.insert(cards[i].name).inserted, !cards[i].name.contains("••") {
                cards[i].name = "\(cards[i].name) ••\(cards[i].mask)"; seen.insert(cards[i].name)
            }
        }
    }

    /// Links a bank-side credit-card bill payment (debit) to the matching card-side payment
    /// credit, flagging both as transfers so neither is counted as spend or income.
    func correlateTransfers() {
        let cardCredits = txns.filter { $0.source == .card && $0.amount > 0 && ($0.transfer || Classifier.isCardPaymentCredit($0.merchant)) }
        for c in cardCredits {
            if let bi = txns.firstIndex(where: { $0.source == .bank && $0.amount < 0 && !$0.transfer
                && abs(abs($0.amount) - abs(c.amount)) < 0.01 && abs($0.date.timeIntervalSince(c.date)) <= 5 * 86400 }) {
                txns[bi].transfer = true
                if !txns[bi].tags.contains("Credit card bill") { txns[bi].tags.append("Credit card bill") }
            }
        }
    }

    /// Import a parsed statement (single or combined): cards reconcile via mergeStatement, bank
    /// accounts via mergeSynced (balances + classified txns), plus FD/RD deposits.
    @discardableResult
    func mergeImport(_ r: ImportResult) -> Int {
        var n = 0
        let cards = r.accounts.filter { $0.kind == .card }
        let banks = r.accounts.filter { $0.kind == .bank }
        for c in cards {
            let res = mergeStatement(account: c, txns: r.txns.filter { $0.accountMask == c.mask })
            n += res.added + res.enriched
        }
        let bankTxns = r.txns.filter { t in !cards.contains { $0.mask == t.accountMask } }
        if !banks.isEmpty || !bankTxns.isEmpty { n += mergeSynced(accounts: banks, txns: bankTxns, reconcile: true) }
        mergeDeposits(r.deposits)
        return n
    }
    /// Upsert deposits by their account-number identifier (so monthly re-imports don't duplicate).
    func mergeDeposits(_ ds: [Deposit]) {
        guard !ds.isEmpty else { return }
        for d in ds {
            if let id = d.identifier, let i = deposits.firstIndex(where: { $0.identifier == id }) {
                deposits[i].bank = d.bank; deposits[i].tag = d.tag; deposits[i].rate = d.rate
                deposits[i].current = d.current; deposits[i].startDate = d.startDate; deposits[i].maturityDate = d.maturityDate
            } else { deposits.append(d) }
        }
        save()
    }

    /// Set exact balances from authoritative signals (e.g. HDFC "available balance" emails).
    func applyBalances(_ updates: [BalanceUpdate]) {
        guard !updates.isEmpty else { return }
        for u in updates where u.kind == .bank {
            if let i = banks.firstIndex(where: { $0.mask == u.mask }) { banks[i].balance = u.balance }
        }
        save()
    }

    // MARK: auto-map helpers (catalog-driven, no logos)
    private func upsertAccount(_ a: SyncedAccount) {
        if a.kind == .card {
            ensureCard(mask: a.mask, bankCode: a.bankCode, cardName: a.cardName)
            if let i = cards.firstIndex(where: { $0.mask == a.mask }) {
                if let l = a.limit, l > 0 { cards[i].limit = l }
                if a.balance > 0 { cards[i].outstanding = a.balance }   // statement total due = exact outstanding
                if cards[i].tier == nil, let t = a.tier { cards[i].tier = t }
                if cards[i].bankCode == nil { cards[i].bankCode = a.bankCode }
                // A statement is authoritative about the product — set/correct it even if the
                // card was previously created with a generic or wrongly-guessed name.
                if let prod = a.cardName, let info = CardCatalog.all.first(where: { $0.name == prod }) {
                    let old = cards[i].name
                    let newName = "\(info.name) ••\(cards[i].mask)"
                    cards[i].name = newName
                    cards[i].network = info.network
                    cards[i].tier = info.tier
                    cards[i].colorHex = info.gradient.first
                    if old != newName { renameAccountTxns(from: old, to: newName) }
                }
                if let rk = a.rewardKind { cards[i].rewardKind = rk }
                if let rb = a.rewardBalance { cards[i].rewardBalance = rb }
            }
            return
        }
        if let i = banks.firstIndex(where: { $0.mask == a.mask }) {
            // A statement's closing balance is stated *as of* its period end. Don't clobber a newer
            // live balance with it — reconstruct by adding transactions dated after the statement.
            if a.balance != 0 { banks[i].balance = liveBalance(statedBalance: a.balance, asOf: a.asOf, accountName: banks[i].name) }
            if banks[i].bankCode == nil { banks[i].bankCode = a.bankCode }
            if banks[i].ifsc == nil { banks[i].ifsc = a.ifsc }
            if banks[i].branch == nil { banks[i].branch = a.branch }
            if banks[i].tier == nil { banks[i].tier = a.tier }
            enrichBankIdentity(&banks[i])
        } else {
            let info = BankCatalog.info(a.bankCode) ?? BankCatalog.match(name: a.bank)
            let base = info?.name ?? a.bank
            banks.append(BankAccount(name: "\(base) ••\(a.mask)", logo: info?.code ?? Self.shortLogo(a.bank),
                                     colorHex: info?.colorHex ?? "4F7FC4", type: a.type, mask: a.mask, balance: a.balance,
                                     bankCode: info?.code ?? a.bankCode, ifsc: a.ifsc, branch: a.branch, tier: a.tier))
        }
    }
    private func ensureBank(mask: String, bankCode: String?) {
        guard !mask.isEmpty, !banks.contains(where: { $0.mask == mask }) else { return }
        let info = BankCatalog.info(bankCode)
        banks.append(BankAccount(name: "\(info?.name ?? "Bank") ••\(mask)", logo: info?.code ?? "BANK",
                                 colorHex: info?.colorHex ?? "4F7FC4", type: "Savings", mask: mask, balance: 0,
                                 bankCode: info?.code))
    }
    private func ensureCard(mask: String, bankCode: String?, cardName: String? = nil) {
        guard !mask.isEmpty, !cards.contains(where: { $0.mask == mask }) else { return }
        let info = BankCatalog.info(bankCode)
        // Only adopt a specific product if it's actually known (from a statement). Never guess a
        // variant from the bank alone — keep it generic until a statement confirms it. The mask
        // keeps names unique across same-product/same-issuer cards.
        if let prod = cardName, let cat = CardCatalog.all.first(where: { $0.name == prod }) {
            cards.append(CreditCard(name: "\(cat.name) ••\(mask)", mask: mask, outstanding: 0, limit: 0, bankCode: bankCode,
                                    network: cat.network, tier: cat.tier, colorHex: cat.gradient.first))
        } else {
            cards.append(CreditCard(name: "\(info?.code ?? info?.name ?? "Card") card ••\(mask)", mask: mask,
                                    outstanding: 0, limit: 0, bankCode: bankCode, colorHex: info?.colorHex))
        }
    }
    private func enrichBankIdentity(_ b: inout BankAccount) {
        if let info = BankCatalog.info(b.bankCode) {
            if b.logo.isEmpty || b.logo == "BANK" { b.logo = info.code }
            if b.colorHex == "4F7FC4" { b.colorHex = info.colorHex }
        }
    }
    private func accountName(forMask mask: String, source: TxnSource) -> String {
        if source == .card, let c = cards.first(where: { $0.mask == mask }) { return c.name }
        if let b = banks.first(where: { $0.mask == mask }) { return b.name }
        return banks.first?.name ?? "Bank"
    }

    // MARK: merchant → category rules
    static func ruleKey(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespaces) }

    /// Full classification: category + symbol + facet tags + transfer flag + canonical brand.
    /// Order: transfers/refunds → learned rule → brand dictionary → keyword fallback.
    func classify(merchant: String, counterparty: String?, narration: String, income: Bool)
        -> (category: String, symbol: String, tags: [String], transfer: Bool, brand: String?) {
        let text = [merchant, counterparty ?? "", narration].joined(separator: " ")
        if Classifier.isCardBillPayment(text) || (income && Classifier.isCardPaymentCredit(text)) {
            return ("Transfer", "arrow.left.arrow.right", ["Credit card bill"], true, nil)
        }
        var tags: [String] = []
        let refund = income && Classifier.isRefund(text)
        if refund { tags.append("Refund") }
        if income && !refund { return ("Income", "indianrupeesign.circle.fill", [], false, nil) }
        let brand = BrandCatalog.classify(text)
        // learned rule wins for the category; brand still supplies tags
        for key in [counterparty, merchant].compactMap({ $0 }).map(Self.ruleKey) where !key.isEmpty {
            if let cat = merchantRules[key] {
                let sym = categories.first { $0.name == cat }?.symbol ?? Self.symbolFor(cat)
                return (cat, sym, Self.uniq(tags + brand.tags), false, brand.brand)
            }
        }
        if let cat = brand.category {
            let sym = categories.first { $0.name == cat }?.symbol ?? Self.symbolFor(cat)
            return (cat, sym, Self.uniq(tags + brand.tags), false, brand.brand)
        }
        let (cat, sym) = Self.categorize(narration, income: false)
        return (cat, sym, Self.uniq(tags), false, brand.brand)
    }
    func categoryFor(merchant: String, counterparty: String?, narration: String, income: Bool) -> (String, String) {
        let c = classify(merchant: merchant, counterparty: counterparty, narration: narration, income: income)
        return (c.category, c.symbol)
    }
    private static func uniq(_ a: [String]) -> [String] { var s = Set<String>(); return a.filter { s.insert($0).inserted } }
    static func symbolFor(_ cat: String) -> String {
        if let b = baseCategories.first(where: { $0.name == cat }) { return b.symbol }
        switch cat {
        case "Income": return "indianrupeesign.circle.fill"
        case "Transfer": return "arrow.left.arrow.right"; default: return "circle.grid.2x2"
        }
    }
    /// Learn a merchant/counterparty → category mapping and retro-apply to existing txns.
    func learnMerchant(_ rawKey: String, category: String) {
        let key = Self.ruleKey(rawKey); guard !key.isEmpty else { return }
        merchantRules[key] = category
        let sym = categories.first { $0.name == category }?.symbol ?? Self.symbolFor(category)
        for i in txns.indices {
            let k = Self.ruleKey(txns[i].counterparty ?? txns[i].merchant)
            guard k == key, !txns[i].income, txns[i].category != category else { continue }
            txns[i].category = category; txns[i].symbol = sym
        }
        recomputeSpent()
        save()
    }

    // MARK: recurring transfers
    struct RecurringGroup: Identifiable { var id: String { key }; var key: String; var name: String; var count: Int; var total: Double; var lastDate: Date; var category: String; var linked: Bool }
    var recurringGroups: [RecurringGroup] {
        let debits = txns.filter { spendContribution($0) > 0 }
        let groups = Dictionary(grouping: debits) { Self.ruleKey($0.counterparty ?? $0.merchant) }
        return groups.compactMap { key, items -> RecurringGroup? in
            guard key.count > 1, items.count >= 3 else { return nil }
            let total = items.map { abs($0.amount) }.reduce(0, +)
            let last = items.map(\.date).max() ?? Date()
            let name = items.first?.merchant ?? key
            return RecurringGroup(key: key, name: name, count: items.count, total: total, lastDate: last,
                                  category: items.first?.category ?? "Other", linked: merchantRules[key] != nil)
        }.sorted { $0.count > $1.count }
    }

    private static func shortLogo(_ bank: String) -> String {
        String(bank.components(separatedBy: " ").first?.prefix(4) ?? "BANK").uppercased()
    }
    private static func prettyMerchant(_ narration: String) -> String {
        let stop = ["UPI", "POS", "NEFT", "IMPS", "ACH", "BILLPAY", "MANDATE", "ATW", "ECS", "TXN", "REF"]
        let parts = narration.uppercased().split(whereSeparator: { "/ -*".contains($0) })
            .map(String.init).filter { !stop.contains($0) && !$0.allSatisfy(\.isNumber) && $0.count > 1 }
        return (parts.first.map { $0.capitalized } ?? narration).trimmingCharacters(in: .whitespaces)
    }
    /// Keyword → (category name, SF Symbol). Falls back to "Other".
    static func categorize(_ narration: String, income: Bool) -> (String, String) {
        if income { return ("Income", "indianrupeesign.circle.fill") }
        let n = narration.uppercased()
        func has(_ ks: [String]) -> Bool { ks.contains { n.contains($0) } }
        if has(["SWIGGY", "ZOMATO", "RESTAURANT", "CAFE", "FOOD"]) { return ("Eating out", "fork.knife") }
        if has(["BIGBASKET", "GROCER", "DMART", "SUPERMARKET", "BLINKIT", "ZEPTO"]) { return ("Groceries", "cart.fill") }
        if has(["UBER", "OLA", "FUEL", "PETROL", "METRO", "IRCTC", "RIDE"]) { return ("Transport", "car.fill") }
        if has(["AMAZON", "FLIPKART", "MYNTRA", "SHOP", "NYKAA", "AJIO"]) { return ("Shopping", "bag.fill") }
        if has(["NETFLIX", "SPOTIFY", "PRIME", "HOTSTAR", "SUBSCRIPTION", "YOUTUBE"]) { return ("Subscriptions", "play.rectangle.fill") }
        if has(["ELECTRICITY", "RENT", "KSEB", "BILL", "WATER", "GAS", "BROADBAND"]) { return ("Bills & Utilities", "bolt.fill") }
        if has(["PHARMACY", "APOLLO", "HOSPITAL", "MEDIC", "CLINIC", "HEALTH"]) { return ("Health", "heart.fill") }
        return ("Other", "circle.grid.2x2")
    }

    // MARK: refresh derived stored collections
    private func refreshMilestones() {
        let nw = liquidNetWorth
        var activeSet = false
        milestones = milestones.sorted { $0.amount < $1.amount }.map { m in
            var m = m
            if nw >= m.amount { m.reached = true; m.active = false; m.pct = 1; m.tag = "Reached" }
            else if !activeSet { m.reached = false; m.active = true; activeSet = true
                m.pct = m.amount > 0 ? min(1, nw / m.amount) : 0; m.tag = "In progress" }
            else { m.reached = false; m.active = false; m.pct = 0; m.tag = "Locked" }
            return m
        }
    }
    private func refreshBadges() {
        func set(_ label: String, _ earned: Bool) {
            if let i = badges.firstIndex(where: { $0.label == label }) { badges[i].earned = earned }
        }
        set("First lakh", liquidNetWorth >= 100_000)
        set("On budget", !categories.isEmpty && categories.allSatisfy { !$0.over })
        set("No debt", !cards.isEmpty && cards.allSatisfy { $0.outstanding <= 0 })
        set("Goal hit", goals.contains { $0.status == .achieved })
        set("Investor", !deposits.isEmpty)
        set("Streak", streakMonths >= 3)
    }
    private func recordNetWorthPoint() {
        let nw = liquidNetWorth
        let today = ISO8601DateFormatter.dayString(Date())
        let last = UserDefaults.standard.string(forKey: nwDayKey)
        if nwHistory.isEmpty { nwHistory = [nw] }
        else if last == today { nwHistory[nwHistory.count - 1] = nw }
        else { nwHistory.append(nw); if nwHistory.count > 90 { nwHistory.removeFirst(nwHistory.count - 90) } }
        UserDefaults.standard.set(today, forKey: nwDayKey)
    }

    // MARK: persistence
    static let schemaVersion = 3
    struct Persist: Codable {
        var schemaVersion = Store.schemaVersion
        var categories: [BudgetCategory] = []
        var txns: [Txn] = []
        var banks: [BankAccount] = []
        var cards: [CreditCard] = []
        var deposits: [Deposit] = []
        var goals: [Goal] = []
        var milestones: [Milestone] = []
        var badges: [Badge] = []
        var incomeStreams: [IncomeStream] = []
        var investments: [Investment] = []
        var nwHistory: [Double] = []
        var fxRates: [String: Double] = ["INR": 1]
        var taxProfile = TaxProfile()
        var payslips: [Payslip] = []
        var advanceTaxPaidStages: [Int] = []
        var merchantRules: [String: String] = [:]

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            categories = c.decode(.categories, default: [])
            txns       = c.decode(.txns, default: [])
            banks      = c.decode(.banks, default: [])
            cards      = c.decode(.cards, default: [])
            deposits   = c.decode(.deposits, default: [])
            goals      = c.decode(.goals, default: [])
            milestones = c.decode(.milestones, default: [])
            badges     = c.decode(.badges, default: [])
            incomeStreams = c.decode(.incomeStreams, default: [])
            investments = c.decode(.investments, default: [])
            nwHistory  = c.decode(.nwHistory, default: [])
            fxRates    = c.decode(.fxRates, default: ["INR": 1])
            taxProfile = c.decode(.taxProfile, default: TaxProfile())
            payslips   = c.decode(.payslips, default: [])
            advanceTaxPaidStages = c.decode(.advanceTaxPaidStages, default: [])
            merchantRules = c.decode(.merchantRules, default: [:])
        }
    }

    private func makePersist() -> Persist {
        var p = Persist()
        p.categories = categories; p.txns = txns; p.banks = banks; p.cards = cards
        p.deposits = deposits; p.goals = goals; p.milestones = milestones; p.badges = badges
        p.incomeStreams = incomeStreams; p.investments = investments; p.nwHistory = nwHistory
        p.fxRates = fxRates; p.taxProfile = taxProfile; p.payslips = payslips
        p.advanceTaxPaidStages = Array(advanceTaxPaidStages)
        p.merchantRules = merchantRules
        return p
    }

    private func apply(_ p: Persist) {
        categories = p.categories; txns = p.txns; banks = p.banks; cards = p.cards
        deposits = p.deposits; goals = p.goals; milestones = p.milestones; badges = p.badges
        incomeStreams = p.incomeStreams; investments = p.investments; nwHistory = p.nwHistory
        fxRates = p.fxRates.isEmpty ? ["INR": 1] : p.fxRates
        taxProfile = p.taxProfile; payslips = p.payslips
        advanceTaxPaidStages = Set(p.advanceTaxPaidStages)
        merchantRules = p.merchantRules
        if milestones.isEmpty { milestones = Self.defaultMilestones() }
        if badges.isEmpty { badges = Self.defaultBadges() }
        migrateRentBills()
        ensureBaseCategories()
        dedupeAccountNames()
    }

    // MARK: maintained base categories
    /// Canonical base taxonomy — always present, can't be deleted/renamed (budget + icon editable).
    static let baseCategories: [(name: String, symbol: String, color: String)] = [
        ("Eating out", "fork.knife", "6E9BD8"),
        ("Online food delivery", "takeoutbag.and.cup.and.straw.fill", "7FC4A3"),
        ("Groceries", "cart.fill", "5BA585"),
        ("Transport", "car.fill", "4F7FC4"),
        ("Travel", "airplane", "9AA7BE"),
        ("Fuel", "fuelpump.fill", "6E9BD8"),
        ("Shopping", "bag.fill", "7FC4A3"),
        ("Subscriptions", "play.rectangle.fill", "5BA585"),
        ("Entertainment", "popcorn.fill", "4F7FC4"),
        ("Bills & Utilities", "bolt.fill", "9AA7BE"),
        ("Insurance", "shield.lefthalf.filled", "6E9BD8"),
        ("EMI & Loans", "banknote.fill", "7FC4A3"),
        ("Health", "heart.fill", "5BA585"),
        ("Education", "graduationcap.fill", "4F7FC4"),
        ("Family", "person.2.fill", "9AA7BE"),
        ("Investments", "chart.line.uptrend.xyaxis", "6E9BD8"),
        ("Other", "circle.grid.2x2", "9AA7BE"),
    ]
    /// One-time rename of the old "Rent & Bills" category → "Bills & Utilities" (idempotent).
    func migrateRentBills() {
        let old = "Rent & Bills", new = "Bills & Utilities"
        guard categories.contains(where: { $0.name == old }) || txns.contains(where: { $0.category == old }) else { return }
        if let i = categories.firstIndex(where: { $0.name == old }) {
            if categories.contains(where: { $0.name == new }) { categories.remove(at: i) }   // base already seeded
            else { categories[i].name = new }
        }
        for j in txns.indices where txns[j].category == old { txns[j].category = new }
        for (k, v) in merchantRules where v == old { merchantRules[k] = new }
    }

    /// Re-run the brand library over existing transactions, updating category/tags — but only
    /// where the library actually matches, never overriding manual rules / transfers / income.
    func recategorizeAll() {
        for i in txns.indices {
            let t = txns[i]
            guard !t.transfer, !t.income else { continue }
            if merchantRules[Self.ruleKey(t.counterparty ?? t.merchant)] != nil { continue }
            let b = BrandCatalog.classify([t.merchant, t.counterparty ?? ""].joined(separator: " "))
            guard let cat = b.category else { continue }
            txns[i].category = cat
            txns[i].symbol = categories.first { $0.name == cat }?.symbol ?? Self.symbolFor(cat)
            txns[i].tags = Self.uniq(t.tags + b.tags)
        }
        recomputeSpent(); save()
    }

    /// Add any missing base category (preserving the user's edits to existing same-named ones).
    func ensureBaseCategories() {
        for b in Self.baseCategories {
            if let i = categories.firstIndex(where: { $0.name == b.name }) {
                if !categories[i].isSystem { categories[i].isSystem = true }   // adopt existing same-named as the base
            } else {
                categories.append(BudgetCategory(name: b.name, symbol: b.symbol, spent: 0, plan: 0, color: b.color, isSystem: true))
            }
        }
    }

    /// Wipe all financial records (accounts, cards, transactions, goals, income, rules) from this
    /// device. Profile name, net-worth target and preferences are kept; gamification is re-seeded.
    /// Full store-side reset: wipes all data, resets preferences to defaults, deletes owned
    /// files (user images, widget snapshot) and persisted keys. Auto-backups are intentionally
    /// kept (the user's recovery option). Gmail/Setu are reset by their own managers.
    func clearAll() {
        categories = []; txns = []; banks = []; cards = []; deposits = []; goals = []
        investments = []; incomeStreams = []; nwHistory = []
        taxProfile = TaxProfile(); payslips = []; advanceTaxPaidStages = []; merchantRules = [:]
        fxRates = ["INR": 1]
        milestones = Self.defaultMilestones()
        badges = Self.defaultBadges()
        ensureBaseCategories()

        // reset preferences to defaults (didSet persists the defaults)
        userName = ""
        netWorthTarget = 5_000_000
        preferStatementImport = false
        accountAggregatorEnabled = false
        notificationsEnabled = false; NotificationManager.setEnabled(false)
        autoBackupEnabled = true

        // remove owned persisted keys + files
        let d = UserDefaults.standard
        d.removeObject(forKey: key); d.removeObject(forKey: key + "_corrupt_backup"); d.removeObject(forKey: nwDayKey)
        let fm = FileManager.default
        if let imgs = try? fm.contentsOfDirectory(at: LocalImage.dir, includingPropertiesForKeys: nil) {
            for u in imgs where u.lastPathComponent.hasPrefix("img_") { try? fm.removeItem(at: u) }
        }
        try? fm.removeItem(at: WTMShared.snapshotURL)

        save()
    }

    func save() {
        refreshMilestones(); refreshBadges(); recordNetWorthPoint()
        if let d = try? JSONEncoder().encode(makePersist()) { UserDefaults.standard.set(d, forKey: key) }
        publishSnapshot()
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key) else { firstRun(); return }
        do { apply(try JSONDecoder().decode(Persist.self, from: d)) }
        catch {
            UserDefaults.standard.set(d, forKey: key + "_corrupt_backup")
            firstRun()
        }
    }

    // MARK: - Backup / restore (device migration). NO Keychain secrets included.
    struct BackupBundle: Codable {
        var schemaVersion = Store.schemaVersion
        var exportedAt = Date()
        var data = Persist()
        var userName = ""
        var netWorthTarget = 5_000_000.0
        var preferStatementImport = false
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = c.decode(.schemaVersion, default: Store.schemaVersion)
            exportedAt = c.decode(.exportedAt, default: Date())
            data = c.decode(.data, default: Persist())
            userName = c.decode(.userName, default: "")
            netWorthTarget = c.decode(.netWorthTarget, default: 5_000_000)
            preferStatementImport = c.decode(.preferStatementImport, default: false)
        }
    }

    private static var backupCoder: (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    func exportBundle() -> Data {
        var b = BackupBundle()
        b.data = makePersist(); b.userName = userName
        b.netWorthTarget = netWorthTarget; b.preferStatementImport = preferStatementImport
        return (try? Self.backupCoder.0.encode(b)) ?? Data()
    }

    @discardableResult
    func importBundle(_ data: Data, replace: Bool) -> Bool {
        guard let b = try? Self.backupCoder.1.decode(BackupBundle.self, from: data) else { return false }
        if replace { apply(b.data) } else { mergeIn(b.data) }
        userName = b.userName
        netWorthTarget = b.netWorthTarget > 0 ? b.netWorthTarget : netWorthTarget
        preferStatementImport = b.preferStatementImport
        save()
        return true
    }

    /// Union by id (txns also dedup by externalId).
    private func mergeIn(_ p: Persist) {
        func union<T: Identifiable>(_ base: inout [T], _ extra: [T]) {
            let ids = Set(base.map { $0.id }); base += extra.filter { !ids.contains($0.id) }
        }
        union(&categories, p.categories); union(&banks, p.banks); union(&cards, p.cards)
        union(&deposits, p.deposits); union(&goals, p.goals); union(&incomeStreams, p.incomeStreams)
        union(&investments, p.investments)
        let extIds = Set(txns.compactMap(\.externalId)); let ids = Set(txns.map(\.id))
        txns += p.txns.filter { !ids.contains($0.id) && !($0.externalId.map { extIds.contains($0) } ?? false) }
    }

    func transactionsCSV() -> String {
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        var rows = ["Date,Merchant,Category,Account,Amount,Type"]
        for t in txns.sorted(by: { $0.date < $1.date }) {
            rows.append([df.string(from: t.date), esc(t.merchant), esc(t.category), esc(t.account),
                         String(format: "%.2f", abs(t.amount)), t.income ? "Credit" : "Debit"].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// First launch: NO financial data. Only the milestone ladder + badge templates
    /// (both derived against real balances, starting at 0 / locked).
    private func firstRun() {
        milestones = Self.defaultMilestones()
        badges = Self.defaultBadges()
        ensureBaseCategories()
        save()
    }

    private static func defaultMilestones() -> [Milestone] {
        [100_000, 500_000, 1_000_000, 2_500_000, 5_000_000, 10_000_000].map {
            Milestone(amount: $0, name: milestoneName($0), tag: "Locked", reached: false, active: false, pct: 0)
        }
    }
    private static func milestoneName(_ a: Double) -> String {
        switch a {
        case 100_000: return "First lakh"
        case 500_000: return "Five lakh"
        case 1_000_000: return "Ten lakh"
        case 2_500_000: return "Quarter crore"
        case 5_000_000: return "Half crore"
        default: return "First crore"
        }
    }
    private static func defaultBadges() -> [Badge] {
        [ Badge(symbol: "flame.fill", label: "Streak", earned: false),
          Badge(symbol: "checkmark.seal.fill", label: "On budget", earned: false),
          Badge(symbol: "banknote.fill", label: "First lakh", earned: false),
          Badge(symbol: "chart.line.uptrend.xyaxis", label: "Investor", earned: false),
          Badge(symbol: "trophy.fill", label: "Goal hit", earned: false),
          Badge(symbol: "crown.fill", label: "No debt", earned: false) ]
    }
}

private extension ISO8601DateFormatter {
    static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
