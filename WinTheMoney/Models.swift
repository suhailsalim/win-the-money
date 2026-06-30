import SwiftUI

// MARK: - Tabs
enum Tab: String, CaseIterable, Identifiable {
    case home, plan, insights, goals, wealth, income
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .plan: return "Plan"
        case .insights: return "Insights"
        case .goals: return "Goals"
        case .wealth: return "Wealth"
        case .income: return "Income"
        }
    }
}

// MARK: - Budget cap period
/// The window a category's `plan` (cap) applies over. Most spends are monthly, but some — insurance,
/// subscriptions billed yearly, school fees — are naturally quarterly / annual / custom-length.
enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case monthly, quarterly, annual, custom
    var id: String { rawValue }
    /// Cycle length in months (custom is handled via `BudgetCategory.customMonths`).
    var months: Int { switch self { case .monthly: 1; case .quarterly: 3; case .annual: 12; case .custom: 1 } }
    var label: String { switch self { case .monthly: "Monthly"; case .quarterly: "Quarterly"; case .annual: "Annual"; case .custom: "Custom" } }
    /// Short noun for "this <noun>" / "per <noun>".
    var noun: String { switch self { case .monthly: "month"; case .quarterly: "quarter"; case .annual: "year"; case .custom: "period" } }
}

// MARK: - Category (budget)
struct BudgetCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String        // SF Symbol
    var spent: Double         // recomputed: spend within the current cap cycle (see Store.recomputeSpent)
    var plan: Double          // the cap, expressed per cycle (e.g. ₹24,000 / year for annual insurance)
    var color: String         // hex for icon tint
    var isSystem: Bool = false // a maintained base category — can't be deleted/renamed
    var period: BudgetPeriod = .monthly   // window the cap applies over
    var customMonths: Int = 1             // cycle length when period == .custom
    var anchor: Date? = nil               // cycle start (e.g. insurance renewal); nil → financial-year start

    /// Effective cycle length in months (≥ 1).
    var periodMonths: Int { period == .custom ? max(1, customMonths) : period.months }
    /// The cap normalised to a per-month figure, so non-monthly caps still fold into the monthly overview.
    var monthlyPlan: Double { plan / Double(periodMonths) }

    var pct: Double { plan > 0 ? spent / plan : 0 }
    var left: Double { plan - spent }
    var over: Bool { spent > plan }
    // zen: slate caution (not red), calm blue near-limit, sage green ok
    var barColorHex: String { over ? "9AA7BE" : (pct > 0.85 ? "6E9BD8" : "7FC4A3") }
}

// MARK: - Transaction
enum TxnSource: String, Codable { case bank, card, unknown }

struct Txn: Identifiable, Codable, Hashable {
    var id = UUID()
    var merchant: String
    var symbol: String
    var category: String
    var account: String
    var amount: Double        // negative = spend, positive = income
    var date: Date
    var externalId: String? = nil   // stable id from the bank/AA feed, for dedup
    var source: TxnSource = .unknown
    var counterparty: String? = nil // VPA / payee / account — key for recurring + rules
    var statementId: String? = nil  // set once confirmed/enriched by a statement (prevents re-match)
    var tags: [String] = []         // facet labels (Entertainment, Tech, …) + "Refund"
    var transfer: Bool = false      // CC bill payment / self-transfer — excluded from spend & income
    var income: Bool { amount > 0 }
    var isRefund: Bool { tags.contains("Refund") }
}

// MARK: - Bank account
struct BankAccount: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var logo: String          // short monogram e.g. HDFC
    var colorHex: String
    var type: String
    var mask: String
    var balance: Double
    var bankCode: String? = nil
    var ifsc: String? = nil
    var branch: String? = nil
    var tier: String? = nil
    var imageRef: String? = nil   // user-supplied logo (file name in Documents or URL)
}

// MARK: - Credit card
struct CreditCard: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var mask: String
    var outstanding: Double
    var limit: Double
    var bankCode: String? = nil
    var network: String? = nil
    var tier: String? = nil
    var colorHex: String? = nil
    var imageRef: String? = nil
    var rewardKind: String? = nil    // Points / Miles / Coins / Cashback
    var rewardBalance: Double? = nil
    var util: Int { limit > 0 ? Int((outstanding / limit * 100).rounded()) : 0 }
    var rewardLabel: String? {
        guard let k = rewardKind, let b = rewardBalance else { return nil }
        let g = NumberFormatter.localizedString(from: NSNumber(value: b), number: .decimal)
        switch k.lowercased() {
        case "cashback": return "₹\(g) cashback"
        case "miles": return "\(g) miles"
        case "coins": return "\(g) coins"
        default: return "\(g) pts"
        }
    }
    var utilColorHex: String { util > 70 ? "9AA7BE" : (util > 40 ? "6E9BD8" : "7FC4A3") }
}

// MARK: - Deposit (FD / RD)
struct Deposit: Identifiable, Codable, Hashable {
    var id = UUID()
    var bank: String
    var tag: String           // "FD" / "RD"
    var symbol: String
    var rate: Double          // interest %
    var current: Double       // current value
    var startDate: Date
    var maturityDate: Date
    var identifier: String? = nil   // deposit account number — for de-dup on re-import

    var progress: Double {
        let total = maturityDate.timeIntervalSince(startDate)
        return total > 0 ? min(1, max(0, Date().timeIntervalSince(startDate) / total)) : 0
    }
    var rateText: String {
        let r = (rate * 100).rounded() / 100
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.2f", r)) + "%"
    }
    var maturesText: String { maturityDate.formatted(.dateTime.month(.abbreviated).year()) }
    var sub: String { tag == "RD" ? "Recurring deposit" : "Fixed deposit" }
}

// MARK: - Investment (stocks & mutual funds)
enum InvestmentKind: String, Codable, CaseIterable {
    case stock, etf, mutualFund
    var label: String {
        switch self { case .stock: return "Stock"; case .etf: return "ETF"; case .mutualFund: return "Mutual fund" }
    }
    var symbol: String {
        switch self { case .stock: return "chart.bar.xaxis"; case .etf: return "chart.bar.doc.horizontal"; case .mutualFund: return "chart.pie.fill" }
    }
    var idLabel: String {
        switch self { case .stock: return "Stock symbol"; case .etf: return "ETF symbol"; case .mutualFund: return "AMFI scheme code" }
    }
    /// Stocks & ETFs trade on exchanges (Yahoo); mutual funds use AMFI (India).
    var usesMarket: Bool { self != .mutualFund }
    /// Yahoo `quoteType` to filter search results.
    var yahooType: String { self == .etf ? "ETF" : "EQUITY" }
}

struct Investment: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: InvestmentKind
    var units: Double
    var avgCost: Double        // per unit
    var identifier: String     // NSE symbol or AMFI scheme code
    var lastPrice: Double      // cached latest quote/NAV
    var lastUpdated: Date?

    var invested: Double { units * avgCost }
    var currentValue: Double { units * (lastPrice > 0 ? lastPrice : avgCost) }
    var pnl: Double { currentValue - invested }
    var pnlPct: Double { invested > 0 ? pnl / invested * 100 : 0 }
}

// MARK: - Goal
enum GoalStatus: String, Codable, CaseIterable {
    case onTrack = "On track"
    case atRisk  = "At risk"
    case paused  = "Paused"
    case achieved = "Achieved"
    var colorHex: String {
        switch self {
        case .onTrack: return "7FC4A3"   // sage
        case .atRisk:  return "9AA7BE"   // slate caution (not red)
        case .paused:  return "9AA3B2"   // muted
        case .achieved: return "6E9BD8"  // calm blue
        }
    }
    var next: GoalStatus {
        switch self {
        case .onTrack: return .atRisk
        case .atRisk:  return .paused
        case .paused:  return .onTrack
        case .achieved: return .achieved
        }
    }
}

struct Goal: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String
    var saved: Double
    var target: Double
    var monthly: Double
    var deadline: Date
    var status: GoalStatus
    var pct: Double { target > 0 ? min(1, saved / target) : 0 }
    var active: Bool { status == .onTrack || status == .atRisk }
    var deadlineText: String { deadline.formatted(.dateTime.month(.abbreviated).year()) }
}

// MARK: - Milestone
struct Milestone: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Double
    var name: String
    var tag: String
    var reached: Bool
    var active: Bool
    var pct: Double           // 0...1 for active ring
}

// MARK: - Badge
struct Badge: Identifiable, Codable, Hashable {
    var id = UUID()
    var symbol: String
    var label: String
    var earned: Bool
}

// MARK: - Currencies (for multi-currency income)
enum Currencies {
    static let common = ["INR", "USD", "EUR", "GBP", "AED", "SGD", "CAD", "AUD"]
    /// Offline fallback rates → INR (used until live FX loads).
    static let fallbackINR: [String: Double] = ["INR": 1, "USD": 83, "EUR": 90, "GBP": 105,
                                                "AED": 22.6, "SGD": 62, "CAD": 61, "AUD": 55]
    static func symbol(_ c: String) -> String {
        ["INR": "₹", "USD": "$", "EUR": "€", "GBP": "£", "AED": "AED ", "SGD": "S$", "CAD": "C$", "AUD": "A$"][c] ?? (c + " ")
    }
}

// MARK: - Income stream (manual, multi-currency)
struct IncomeStream: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var annual: Double             // annual amount, in `currency`
    var currency: String = "INR"
    var monthly: Bool = false      // whether the figure was entered per-month
    var accountId: UUID? = nil     // linked bank account
    var creditDay: Int? = nil      // day of month credited (monthly salary)

    var perPeriodAmount: Double { monthly ? annual / 12 : annual }
    var periodLabel: String { monthly ? "mo" : "yr" }
}

// MARK: - Income & tax: track, regime, profile, payslip
/// Which earning situation the user is in — drives how taxable income is computed.
enum IncomeTrack: String, Codable, CaseIterable, Identifiable {
    case salaried, selfEmployed, business, mixed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .salaried: return "Salaried"
        case .selfEmployed: return "Self-employed"
        case .business: return "Business"
        case .mixed: return "Mixed"
        }
    }
    var blurb: String {
        switch self {
        case .salaried: return "Salary with TDS; import payslips"
        case .selfEmployed: return "Professional — 44ADA presumptive (50%)"
        case .business: return "Business — 44AD presumptive (6/8%)"
        case .mixed: return "Salary + profession/other income"
        }
    }
    var symbol: String {
        switch self {
        case .salaried: return "briefcase.fill"
        case .selfEmployed: return "laptopcomputer"
        case .business: return "storefront.fill"
        case .mixed: return "rectangle.3.group.fill"
        }
    }
}

enum TaxRegime: String, Codable, CaseIterable, Identifiable {
    case new, old
    var id: String { rawValue }
    var label: String { self == .new ? "New regime" : "Old regime" }
}

/// All the inputs needed to estimate India income tax. Amounts are annual ₹ for the current FY.
struct TaxProfile: Codable, Hashable {
    var track: IncomeTrack = .salaried
    var regime: TaxRegime = .new          // user's chosen/declared regime (engine still compares both)
    var autoPickRegime: Bool = true       // when true, follow whichever regime is cheaper

    // Salary (annual, taxable — i.e. gross salary; standard deduction applied by the engine)
    var grossSalary: Double = 0
    var tdsPaid: Double = 0               // TDS already deducted by employer (from payslips)

    // Presumptive
    var professionalReceipts: Double = 0  // 44ADA — gross professional receipts
    var businessTurnover: Double = 0      // 44AD — gross turnover/sales
    var businessDigitalShare: Double = 1  // 0…1 share of turnover received digitally (6% vs 8%)

    // Other taxable income (interest, rent net, capital gains treated as slab income — simplified)
    var otherIncome: Double = 0

    // Old-regime deductions (ignored under the new regime)
    var ded80C: Double = 0                // capped 1.5L
    var ded80D: Double = 0                // health insurance
    var ded80CCD1B: Double = 0            // NPS extra, capped 50k
    var dedHomeLoanInterest: Double = 0   // 24(b), capped 2L (self-occupied)
    var dedHRA: Double = 0                // exempt HRA
    var otherDeductions: Double = 0       // 80G, 80E, etc.

    // New-regime employer NPS 80CCD(2) — allowed in both regimes
    var employerNPS: Double = 0

    var advanceTaxPaid: Double = 0        // self-paid advance tax (separate from TDS)
    var seeded: Bool = false              // whether the user has set this up
}

/// A parsed/entered salary slip — drives TDS tracking, salary-component view, and annual projection.
struct Payslip: Identifiable, Codable, Hashable {
    var id = UUID()
    var employer: String = ""
    var period: Date = Date()             // the month this slip is for
    var basic: Double = 0
    var hra: Double = 0
    var allowances: Double = 0            // special + other allowances
    var grossEarnings: Double = 0
    var pf: Double = 0                    // employee PF (80C-eligible)
    var profTax: Double = 0
    var tds: Double = 0                   // income tax deducted this month
    var otherDeductions: Double = 0
    var netPay: Double = 0

    var monthLabel: String { period.formatted(.dateTime.month(.abbreviated).year()) }
}

// MARK: - Net worth composition segment
struct Segment: Identifiable, Hashable {
    var id = UUID()
    var label: String
    var value: Double
    var colorHex: String
}

// MARK: - Plan month (bar chart)
struct PlanMonth: Identifiable, Hashable {
    var id = UUID()
    var month: String
    var pct: Int              // % of budget used
    var over: Bool
}
