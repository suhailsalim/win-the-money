import Foundation

/// Parses Indian bank/credit-card transaction-alert emails into transactions.
/// Built from real HDFC / Axis / Scapia-Federal alert formats. Pure Foundation
/// (testable). Returns nil for non-transaction mail (promos, OTPs, statements).
enum EmailTransactionParser {

    struct Source { var id: String; var sender: String; var subject: String; var dateHeader: String; var body: String }

    static func parse(_ src: Source) -> SyncedTxn? {
        let text = htmlToText(src.body)
        let headerDate = rfcDate(src.dateHeader)

        // 1) HDFC Bank account (UPI / IMPS) — debit or credit
        if let g = cap(#"Rs\.?\s*([\d,]+(?:\.\d{1,2})?)\s+(?:is|has been)\s+(debited|credited)\s+(?:from|to)\s+your account ending\s+(\d+)\s+(?:towards|by|from)\s+VPA\s+(\S+)\s*(?:\(([^)]+)\))?\s+on\s+(\d{2}-\d{2}-\d{2,4})"#, text, 6) {
            let credit = g[2].lowercased() == "credited"
            let name = g[5].isEmpty ? g[4] : g[5]
            return make(src, mask: g[3], amount: g[1], credit: credit, source: .bank, bankCode: "HDFC",
                        counterparty: g[4], merchant: clean(name), narration: "UPI \(g[4]) \(g[5])",
                        date: date(g[6]) ?? headerDate)
        }

        // 2) HDFC Bank Credit Card
        if let g = cap(#"Rs\.?\s*([\d,]+(?:\.\d{1,2})?)\s+has been\s+(debited|credited)\s+(?:from|to)\s+your HDFC Bank Credit Card ending\s+(\d+)\s+towards\s+(.+?)\s+on\s+(\d{1,2}\s+\w{3},?\s+\d{4})"#, text, 5) {
            let credit = g[2].lowercased() == "credited"
            return make(src, mask: g[3], amount: g[1], credit: credit, source: .card, bankCode: "HDFC",
                        counterparty: clean(g[4]), merchant: clean(g[4]), narration: "HDFC Credit Card · \(g[4])",
                        date: date(g[5]) ?? headerDate)
        }

        // 3) Axis Bank Credit Card (spend = debit)
        if let g = cap(#"Transaction Amount:\s*(?:INR|Rs\.?)\s*([\d,]+(?:\.\d{1,2})?)\s*Merchant Name:\s*(.+?)\s*Axis Bank Credit Card No\.?\s*[Xx]+(\d+)"#, text, 3) {
            let credit = text.lowercased().contains("reversal") || text.lowercased().contains("refund")
            return make(src, mask: g[3], amount: g[1], credit: credit, source: .card, bankCode: "AXIS",
                        counterparty: clean(g[2]), merchant: clean(g[2]), narration: "Axis Credit Card · \(g[2])",
                        date: date(cap(#"Date[:\s]+(\d{2}[-/]\d{2}[-/]\d{2,4})"#, text, 1)?[1] ?? "") ?? headerDate)
        }

        // 4a) Scapia Federal — payment processed (spend)
        if let g = cap(#"using your Scapia Federal[^.]*?Credit Card ending in\s+(\d+)[\s\S]*?Amount\s*(?:₹|Rs\.?|INR)\s*([\d,]+(?:\.\d{1,2})?)\s*Merchant\s+([^\n]{2,40})"#, text, 3) {
            let d = date(cap(#"payment on\s*(\d{2}-\d{2}-\d{4})"#, text, 1)?[1] ?? "") ?? headerDate
            let merchant = boundMerchant(g[3])
            return make(src, mask: g[1], amount: g[2], credit: false, source: .card, bankCode: "FED",
                        counterparty: merchant, merchant: merchant, narration: "Scapia Federal CC · \(merchant)", date: d)
        }

        // 4b) Scapia Federal — waiver / credit-debit notice
        if let g = cap(#"(?:₹|Rs\.?|INR)\s*([\d,]+(?:\.\d{1,2})?)\s+has been\s+(credited|debited)\s+to your Scapia Federal Credit Card ending in\s+(\d+)\s+on\s+(\d{2}-\d{2}-\d{4})"#, text, 4) {
            let credit = g[2].lowercased() == "credited"
            let what = text.lowercased().contains("fuel surcharge") ? "Fuel surcharge waiver" : "Scapia Federal CC"
            return make(src, mask: g[3], amount: g[1], credit: credit, source: .card, bankCode: "FED",
                        counterparty: what, merchant: what, narration: "Scapia Federal Credit Card",
                        date: date(g[4]) ?? headerDate)
        }

        return nil
    }

    /// An exact account balance from an HDFC "available balance" email.
    static func balance(_ src: Source) -> BalanceUpdate? {
        let text = htmlToText(src.body)
        guard let g = cap(#"available balance in your account ending\s+[Xx]*(\d+)\s+is\s+Rs\.?\s*(?:INR)?\s*([\d,]+(?:\.\d{1,2})?)"#, text, 2),
              let v = money(g[2]) else { return nil }
        return BalanceUpdate(mask: String(g[1].suffix(4)), balance: v, kind: .bank)
    }

    private static func make(_ src: Source, mask: String, amount: String, credit: Bool,
                             source: TxnSource, bankCode: String, counterparty: String,
                             merchant: String, narration: String, date: Date) -> SyncedTxn? {
        guard let v = money(amount), v > 0 else { return nil }
        return SyncedTxn(externalId: "gmail:\(src.id)", narration: narration,
                         amount: credit ? v : -v, date: date,
                         accountMask: String(mask.suffix(4)), merchant: merchant.isEmpty ? nil : merchant,
                         source: source, counterparty: counterparty.isEmpty ? nil : counterparty, bankCode: bankCode)
    }

    // MARK: helpers
    static func htmlToText(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"(?is)<(script|style|head)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (e, r) in ["&amp;": "&", "&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&rsquo;": "'"] {
            t = t.replacingOccurrences(of: e, with: r)
        }
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    private static func money(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "")) }
    private static func clean(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.range(of: #"^[A-Z0-9 .&'-]+$"#, options: .regularExpression) != nil ? t.capitalized : t
    }
    /// Trim a merchant string at boilerplate tokens and cap length.
    private static func boundMerchant(_ s: String) -> String {
        let stop: Set<String> = ["Need", "Powered", "View", "Track", "Help", "If", "Your", "Thank", "Visit"]
        var words: [String] = []
        for w in s.split(separator: " ").map(String.init) {
            if stop.contains(w) { break }
            words.append(w); if words.count >= 4 { break }
        }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,-"))
    }
    private static func cap(_ pattern: String, _ s: String, _ groups: Int) -> [String]? {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0...groups).map { i in i < m.numberOfRanges && m.range(at: i).location != NSNotFound ? ns.substring(with: m.range(at: i)) : "" }
    }
    private static let fmts = ["dd-MM-yy", "dd-MM-yyyy", "dd MMM yyyy", "dd MMM, yyyy", "dd/MM/yyyy", "dd/MM/yy"]
    private static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in fmts { f.dateFormat = fmt; if let d = f.date(from: t) { return d } }
        return nil
    }
    private static func rfcDate(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return df.date(from: s) ?? Date()
    }
}
