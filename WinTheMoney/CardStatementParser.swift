import Foundation

/// Parses **credit-card** statements (distinct from bank passbooks). Extracts the card's
/// last-4, credit limit and total amount due (→ exact outstanding), plus spend transactions.
/// Verified against real HDFC (Diners), Axis (Atlas), ICICI (Amazon Pay) and Scapia (Federal)
/// June statements — each issuer has its own layout, handled by a dedicated parser.
enum CardStatementParser {
    enum Issuer: String { case hdfc = "HDFC", axis = "AXIS", icici = "ICICI", federal = "FED", generic = "" }

    static func isCardStatement(_ text: String) -> Bool {
        let t = text.lowercased()
        let cardish = t.contains("credit card") || t.contains("card number") || t.contains("card no")
        let dueish = t.contains("total amount due") || t.contains("total dues") || t.contains("total payment due") ||
                     t.contains("total due") || t.contains("minimum amount due") || t.contains("minimum due") ||
                     t.contains("payment due date") || t.contains("credit limit")
        let bankish = t.contains("opening balance") && t.contains("closing balance")
        return cardish && dueish && !bankish
    }

    static func detectIssuer(_ text: String) -> Issuer {
        let t = text.lowercased()
        if t.contains("scapia") || (t.contains("federal") && !t.contains("hdfc")) { return .federal }
        if t.contains("hdfc") { return .hdfc }
        if t.contains("axis bank") || t.contains("axis credit") { return .axis }
        if t.contains("icici") { return .icici }
        return .generic
    }

    static func parse(text: String, pages: [[PDFWord]] = []) -> (account: SyncedAccount, txns: [SyncedTxn])? {
        guard isCardStatement(text) else { return nil }
        switch detectIssuer(text) {
        case .hdfc:    return parseHDFC(text)
        case .axis:    return parseAxis(text)
        case .icici:   return parseICICI(text)
        case .federal: return parseScapia(text)
        case .generic: return nil
        }
    }

    // MARK: - HDFC (Diners etc.) — "C" rupee glyph, multi-line rows, credits flagged by keyword
    private static func parseHDFC(_ text: String) -> (SyncedAccount, [SyncedTxn]) {
        let mask = cap(#"X{2,}(\d{4})"#, text) ?? ""
        let limit = headerMoney(["TOTAL CREDIT LIMIT"], text, gap: 50)
        let due = headerMoney(["TOTAL AMOUNT DUE"], text, gap: 50)
        let product = pickProduct(.hdfc, text)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        // domestic rows: "dd/MM/yyyy|", international rows: "dd/MM/yyyy |" (space before pipe)
        let recs = records(lines, start: { matches(#"^\d{2}/\d{2}/\d{4}\s*\|"#, $0) }, stop: { hdfcNoise($0) })
        var txns: [SyncedTxn] = []
        for g in recs {
            // first C-amount on the row (later "C…" tokens can be trailing summaries / refs)
            guard let amt = lastMoney(#"C\s*([\d,]+\.\d{2})"#, g, lazyFirst: true) else { continue }
            var m = replace(#"^\d{2}/\d{2}/\d{4}\s*\|\s*\d{2}:\d{2}\s*"#, in: g, with: "")
            m = replace(#"(?:[+\-]\s*\d+\s*)?C\s*[\d,]+\.\d{2}[\s\S]*$"#, in: m, with: "")
            m = replace(#"\(Ref#[^)]*\)"#, in: m, with: "")
            let merchant = tidy(m)
            let credit = creditByKeyword(g)
            let date = parseDate(cap(#"^(\d{2}/\d{2}/\d{4})"#, g) ?? "", ["dd/MM/yyyy"]) ?? Date()
            txns.append(mk("hdfc", date, merchant, amt, credit, mask, "HDFC"))
        }
        let rw = reward("Points", #"Reward Points[\s\S]{0,15}?([\d,]{2,})"#, text)
        return (cardAccount(.hdfc, mask: mask, due: due, limit: limit, product: product, reward: rw), txns)
    }
    private static func hdfcNoise(_ l: String) -> Bool {
        l.contains("Diners") || l.contains("Page ") || l.contains("HDFC Bank Credit Cards") ||
        l.contains("Domestic Transaction") || l.contains("Reward Points") || l.isEmpty
    }

    // MARK: - Axis (Atlas etc.) — single-line rows ending in amount + Dr/Cr
    private static func parseAxis(_ text: String) -> (SyncedAccount, [SyncedTxn]) {
        let mask = cap(#"(?:Credit Card Number|Card No:?)\s*\d{6}\*+(\d{4})"#, text) ?? cap(#"\*{2,}(\d{4})"#, text) ?? ""
        let limit = cap(#"Credit Limit\s+([\d,]+\.\d{2})\s+Available"#, text).flatMap(money)
        let due = lastMoney(#"Total Payment Due[\s\S]{0,90}?\n\s*([\d,]+\.\d{2})"#, text, lazyFirst: true)
        let product = pickProduct(.axis, text)
        var txns: [SyncedTxn] = []
        let rowRe = re(#"^(\d{2}/\d{2}/\d{4})\s+(.+?)\s+([\d,]+\.\d{2})\s+(Dr|Cr)$"#)
        for l in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let g = match(rowRe, l), let v = money(g[3]) else { continue }
            let credit = g[4] == "Cr"
            let date = parseDate(g[1], ["dd/MM/yyyy"]) ?? Date()
            txns.append(mk("axis", date, tidy(g[2]), v, credit, mask, "AXIS", category: mapCategory(g[2])))
        }
        let rw = reward("Miles", #"eDGE MILES[\s\S]{0,600}?([\d,]{3,})\s+\d{2}-\d{2}-\d{4}"#, text)
        return (cardAccount(.axis, mask: mask, due: due, limit: limit, product: product, reward: rw), txns)
    }

    // MARK: - ICICI (Amazon Pay etc.) — "`" rupee glyph; date+serno line then points+amount line
    private static func parseICICI(_ text: String) -> (SyncedAccount, [SyncedTxn]) {
        let mask = cap(#"\d{4}X{2,}(\d{4})"#, text) ?? ""
        // anchor to the ` (₹) glyph so MITC sample limits (e.g. "Credit Limit 35,000") aren't matched
        let limit = cap(#"Credit Limit \(Including cash\)[\s\S]{0,160}?`\s*([\d,]+\.\d{2})"#, text).flatMap(money)
        let due = cap(#"Total Amount due[\s\S]{0,160}?`\s*([\d,]+\.\d{2})"#, text).flatMap(money)
        let product = pickProduct(.icici, text)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let recs = records(lines, start: { matches(#"^\d{2}/\d{2}/\d{4}\s+\d{6,}\s"#, $0) },
                           stop: { $0.contains("Page ") || $0.lowercased().contains("statement period") })
        var txns: [SyncedTxn] = []
        for g in recs {
            guard let amt = lastMoney(#"([\d,]+\.\d{2})"#, g) else { continue }
            var m = replace(#"^\d{2}/\d{2}/\d{4}\s+\d{6,}\s*"#, in: g, with: "")
            m = replace(#"\s+\d+\s+[\d,]+\.\d{2}(\s+(?:IN|CR))?.*$"#, in: m, with: "")
            let credit = creditByKeyword(g) || g.uppercased().contains(" CR")
            let date = parseDate(cap(#"^(\d{2}/\d{2}/\d{4})"#, g) ?? "", ["dd/MM/yyyy"]) ?? Date()
            txns.append(mk("icici", date, tidy(m), amt, credit, mask, "ICICI"))
        }
        let rw = reward("Cashback", #"EARNINGS[\s\S]{0,200}?\b(\d{1,7})\s+\1\b"#, text)
        return (cardAccount(.icici, mask: mask, due: due, limit: limit, product: product, reward: rw), txns)
    }

    // MARK: - Scapia (Federal) — "₹" glyph, multi-line rows; credits shown as "+₹" / Payment / Refund
    private static func parseScapia(_ text: String) -> (SyncedAccount, [SyncedTxn]) {
        let mask = cap(#"X{2,}(\d{4})"#, text) ?? ""
        let limit = headerMoney(["Total Limit"], text, gap: 20)
        let due = headerMoney(["Total Due", "New balance"], text, gap: 20)
        // Scapia lists rows either inline ("date merchant ₹amount") or in columns
        // (merchant1, merchant2, …, then amount1, amount2, …). Collect merchants (each
        // opened by a date line) and amounts in document order, then zip — works for both.
        let dateRe = re(#"^(\d{2}-\d{2}-\d{4})\s*·\s*\d{2}:\d{2}\s*(.*)$"#)
        let amtRe = re(#"(\+)?₹\s*([\d,]+\.\d{2})"#)
        func isNoise(_ l: String) -> Bool {
            l.isEmpty || l.contains("Your Transactions") || l.contains("Billing Cycle") || l == "Suhail Salim"
                || l.hasPrefix("•") || matches(#"^\d{2} \w{3} \d{4} - "#, l)
        }
        func isStop(_ l: String) -> Bool {
            l.contains("Let’s talk") || l.contains("Let's talk") || l.contains("All about your")
                || l.contains("Most Important") || l.contains("GRIEVANCE") || l.contains("Illustration of")
        }
        // Gather the transactions section, then split on EVERY embedded date so multiple
        // transactions packed on one physical line become separate logical rows.
        var inSection = false; var blob = ""
        for l in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if !inSection { if l.contains("Your Transactions") { inSection = true }; continue }
            if isStop(l) { break }
            if isNoise(l) { continue }
            blob += " " + l
        }
        let split = replace(#"(?=\d{2}-\d{2}-\d{4}\s*·\s*\d{2}:\d{2})"#, in: blob, with: "\n")
        let lines = split.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        var txns: [SyncedTxn] = []
        var pending: [(date: Date, merchant: String)] = []   // merchants awaiting an amount (FIFO)
        var n = 0
        // Scapia prefixes every credit with "+₹" and never a debit → sign comes from the token.
        func pop(_ v: Double, _ credit: Bool) {
            guard !pending.isEmpty else { return }
            let p = pending.removeFirst()
            txns.append(mk("scapia\(n)", p.date, p.merchant.isEmpty ? "Scapia Federal" : p.merchant, v, credit, mask, "FED")); n += 1
        }
        func amts(_ s: String) -> [(Double, Bool)] {
            guard let r = amtRe else { return [] }
            let ns = s as NSString
            return r.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
                (money(ns.substring(with: $0.range(at: 2))) ?? 0, $0.range(at: 1).location != NSNotFound)
            }
        }
        for l in lines where !l.isEmpty {
            if let g = match(dateRe, l) {
                let d = parseDate(g[1], ["dd-MM-yyyy"]) ?? Date()
                pending.append((d, tidy(replace(#"\+?₹\s*[\d,]+\.\d{2}.*$"#, in: g[2], with: ""))))
                for a in amts(l) { pop(a.0, a.1) }                 // FIFO: oldest merchant gets the next amount
            } else {
                let a = amts(l)
                if a.isEmpty, !pending.isEmpty {                   // wrapped merchant continuation
                    pending[pending.count - 1].merchant = tidy(pending[pending.count - 1].merchant + " " + l)
                } else { for x in a { pop(x.0, x.1) } }
            }
        }
        let rw = reward("Coins", #"into\s+([\d,]+)\s+Scapia Coins"#, text) ?? reward("Coins", #"([\d,]+)\s+Scapia Coins"#, text)
        return (cardAccount(.federal, mask: mask, due: due, limit: limit, product: "Scapia Federal", reward: rw), txns)
    }

    // MARK: - shared builders
    private static func cardAccount(_ issuer: Issuer, mask: String, due: Double?, limit: Double?,
                                    product: String?, reward: (String, Double)? = nil) -> SyncedAccount {
        let code = issuer == .generic ? nil : issuer.rawValue
        return SyncedAccount(bank: BankCatalog.info(code)?.name ?? "Card", mask: mask, type: "Credit card",
                             balance: due ?? 0, kind: .card, bankCode: code, limit: limit, cardName: product,
                             rewardKind: reward?.0, rewardBalance: reward?.1)
    }
    private static func reward(_ kind: String, _ pattern: String, _ text: String) -> (String, Double)? {
        guard let v = cap(pattern, text).flatMap(money) else { return nil }
        return (kind, v)
    }
    private static func mk(_ tag: String, _ date: Date, _ merchant: String, _ v: Double, _ credit: Bool,
                           _ mask: String, _ code: String, category: String? = nil) -> SyncedTxn {
        let name = merchant.isEmpty ? "\(code) card" : merchant
        return SyncedTxn(externalId: "cc:\(tag):\(date.timeIntervalSince1970):\(name.prefix(14)):\(v)",
                         narration: name, amount: credit ? v : -v, date: date,
                         accountMask: mask, merchant: name.capitalized,
                         source: .card, counterparty: name, bankCode: code, category: category)
    }
    /// Maps an issuer's merchant-category text to one of our budget categories (best-effort).
    private static func mapCategory(_ s: String) -> String? {
        let u = s.uppercased()
        func has(_ ks: [String]) -> Bool { ks.contains { u.contains($0) } }
        if has(["HOTEL", "RESTAURANT", "CAFE", "FOOD", "DINING", "BAKER", "BREW"]) { return "Eating out" }
        if has(["GROCER", "SUPERMARKET", "DEPT STORE", "DEPARTMENT"]) { return "Groceries" }
        if has(["CAR RENTAL", "UBER", "TRAVEL", "FUEL", "PETROL", "AIRLINE", "AUTO SERVICE", "TRANSPORT", "RAIL"]) { return "Transport" }
        if has(["MEDICAL", "PHARMAC", "HOSPITAL", "HEALTH", "CLINIC"]) { return "Health" }
        if has(["CLOTH", "APPAREL", "RETAIL", "STORE", "SHOP", "FASHION", "ELECTRONIC"]) { return "Shopping" }
        if has(["SUBSCRIPTION", "STREAM", "NETFLIX", "ENTERTAIN"]) { return "Subscriptions" }
        return nil
    }
    private static func pickProduct(_ issuer: Issuer, _ text: String) -> String? {
        let t = text.lowercased()
        switch issuer {
        case .hdfc:
            if t.contains("diners black") { return "HDFC Diners Black" }
            if t.contains("infinia") { return "HDFC Infinia" }
            if t.contains("regalia") { return "HDFC Regalia Gold" }
            if t.contains("millennia") { return "HDFC Millennia" }
            if t.contains("swiggy") { return "HDFC Swiggy" }
        case .axis:
            if t.contains("atlas") { return "Axis Atlas" }
            if t.contains("magnus") { return "Axis Magnus" }
            if t.contains("ace") { return "Axis ACE" }
        case .icici:
            if t.contains("amazon pay") { return "ICICI Amazon Pay" }
            if t.contains("sapphiro") { return "ICICI Sapphiro" }
            if t.contains("coral") { return "ICICI Coral" }
        case .federal: return "Scapia Federal"
        case .generic: break
        }
        return nil   // unknown product — never assume a variant
    }
    private static func creditByKeyword(_ s: String) -> Bool {
        let u = s.uppercased()
        return ["PAYMENT", "AUTOPAY", "THANK YOU", "REVERSAL", "REFUND", "CASHBACK", "RECEIVED"].contains { u.contains($0) }
    }

    // MARK: - multi-line record assembly
    private static func records(_ lines: [String], start: (String) -> Bool, stop: (String) -> Bool) -> [String] {
        var out: [String] = []; var cur: String? = nil
        for l in lines where !l.isEmpty {
            if start(l) { if let c = cur { out.append(c) }; cur = l }
            else if stop(l) { if let c = cur { out.append(c); cur = nil } }
            else if cur != nil { cur! += " " + l }
        }
        if let c = cur { out.append(c) }
        return out
    }

    // MARK: - regex / money helpers
    private static func headerMoney(_ labels: [String], _ text: String, gap: Int) -> Double? {
        for label in labels {
            let p = "\(NSRegularExpression.escapedPattern(for: label))[\\s\\S]{0,\(gap)}?(?:`|₹|Rs\\.?|INR|C)?\\s*([\\d,]+(?:\\.\\d{2})?)"
            if let v = cap(p, text).flatMap(money) { return v }
        }
        return nil
    }
    private static func lastMoney(_ pattern: String, _ s: String, lazyFirst: Bool = false) -> Double? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = s as NSString
        let ms = r.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard let m = (lazyFirst ? ms.first : ms.last), m.numberOfRanges > 1 else { return nil }
        return money(ns.substring(with: m.range(at: 1)))
    }
    private static func cap(_ pattern: String, _ text: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = r.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
    private static func matches(_ pattern: String, _ s: String) -> Bool {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return r.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
    private static func replace(_ pattern: String, in s: String, with t: String) -> String {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        return r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
    }
    private static func re(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p, options: []) }
    private static func match(_ r: NSRegularExpression?, _ s: String) -> [String]? {
        guard let r else { return nil }
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }
    private static func money(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }
    private static func tidy(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    private static func parseDate(_ s: String, _ formats: [String]) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }
}
