import Foundation

/// How a receipt described the amount of something.
enum ReceiptUnit: String, Codable {
    case kilograms
    case grams
    case litres
    case count
    case none

    /// The amount in grams, when the receipt said so. A litre is treated as a kilogram, which is
    /// right for milk, oil and drinks within a few percent.
    func grams(_ quantity: Double?) -> Double? {
        guard let quantity else { return nil }
        switch self {
        case .kilograms, .litres: return quantity * 1000
        case .grams: return quantity
        case .count, .none: return nil
        }
    }

    /// The number of items, when the receipt said so.
    func count(_ quantity: Double?) -> Double? {
        guard let quantity, self == .count else { return nil }
        return quantity
    }
}

/// One priced row read off a receipt.
struct ReceiptLine: Identifiable, Hashable {
    let id = UUID()
    /// The line as it appeared, kept so the person can check what was read.
    let raw: String
    /// The product name with prices and quantities stripped out.
    let name: String
    let quantity: Double?
    let unit: ReceiptUnit
    /// What was paid for the row.
    let total: Double

    var grams: Double? { unit.grams(quantity) }
    var count: Double? { unit.count(quantity) }
}

/// Rebuilds printed rows from OCR fragments.
///
/// Text recognition reports each block it finds, so a receipt's product name and its price arrive
/// as two separate fragments on the same printed line. A row means nothing until the fragments are
/// joined again, in reading order.
enum ReceiptRows {
    struct Fragment: Equatable {
        var text: String
        /// Horizontal position, 0...1.
        var x: Double
        /// Vertical position, 0...1, with 1 at the top of the page.
        var y: Double
    }

    static func join(_ fragments: [Fragment], tolerance: Double = 0.02) -> [String] {
        let sorted = fragments.sorted { $0.y > $1.y }
        var groups: [[Fragment]] = []
        for fragment in sorted {
            if let last = groups.last, let reference = last.first?.y, abs(reference - fragment.y) <= tolerance {
                groups[groups.count - 1].append(fragment)
            } else {
                groups.append([fragment])
            }
        }
        return groups.map { group in
            group.sorted { $0.x < $1.x }.map(\.text).joined(separator: "  ")
        }
    }
}

/// Turns the text of a grocery receipt into priced rows.
///
/// Receipts are messy and every shop prints them differently, so the parser is deliberately
/// conservative: it only keeps a row when it can find a name and a money amount, and it refuses
/// to guess a weight that is not printed. Anything it skips is simply not offered.
enum ReceiptParser {
    /// Words that mark a line as the shop's own accounting rather than a product. Matched as whole
    /// words, so "DATTES" is not mistaken for "DATE".
    private static let ignoredWords: Set<String> = [
        "total", "sous", "tva", "remise", "reduction", "réduction", "especes", "espèces",
        "rendu", "monnaie", "carte", "bancaire", "cheque", "chèque", "merci", "bienvenue",
        "ticket", "caisse", "caissier", "date", "heure", "article", "qte", "qté", "pu",
        "montant", "payer", "payé", "paye", "nombre", "vendeur", "magasin", "ice", "rc", "if"
    ]

    private static let quantityPattern = try! NSRegularExpression(
        pattern: #"(?i)(\d+(?:[.,]\d+)?)\s*(kg|kgs|g|gr|grs)\b"#)
    private static let volumePattern = try! NSRegularExpression(
        pattern: #"(?i)(\d+(?:[.,]\d+)?)\s*(l|litres?|cl|ml)\b"#)
    private static let countPattern = try! NSRegularExpression(
        pattern: #"(?i)(\d+)\s*(?:x|pcs|pc|u|pi[eè]ce[s]?)\b"#)
    private static let timesPattern = try! NSRegularExpression(
        pattern: #"(?i)(\d+)\s*[x×]\s*(\d+(?:[.,]\d{1,2}))"#)
    private static let moneyPattern = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,3}(?:[ .]\d{3})*(?:[.,]\d{1,2})|\d+(?:[.,]\d{1,2}))(?!\d)"#)

    static func parse(_ lines: [String]) -> [ReceiptLine] {
        var result: [ReceiptLine] = []
        for raw in lines {
            if let line = parseLine(raw) { result.append(line) }
        }
        return result
    }

    static func parseLine(_ raw: String) -> ReceiptLine? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        guard !isAccountingLine(trimmed) else { return nil }

        let amounts = amounts(in: trimmed)
        guard let total = amounts.last, total > 0 else { return nil }

        // "2 x 12,50" describes two units at a unit price; the total is the product.
        var quantity: Double? = nil
        var unit: ReceiptUnit = .none
        var paid = total

        if let times = firstMatch(timesPattern, in: trimmed),
           let count = Double(times[1].replacingOccurrences(of: ",", with: ".")),
           let unitPrice = Double(times[2].replacingOccurrences(of: ",", with: ".")),
           count >= 1, count <= 100 {
            quantity = count
            unit = .count
            if amounts.count == 1 {
                paid = count * unitPrice
            }
        } else if let weight = firstMatch(quantityPattern, in: trimmed),
                  let value = Double(weight[1].replacingOccurrences(of: ",", with: ".")),
                  value > 0 {
            quantity = value
            unit = weight[2].lowercased().hasPrefix("k") ? .kilograms : .grams
        } else if let volume = firstMatch(volumePattern, in: trimmed),
                  let value = Double(volume[1].replacingOccurrences(of: ",", with: ".")),
                  value > 0 {
            unit = .litres
            switch volume[2].lowercased() {
            case "cl": quantity = value / 100
            case "ml": quantity = value / 1000
            default: quantity = value
            }
        } else if let pieces = firstMatch(countPattern, in: trimmed),
                  let value = Double(pieces[1]), value > 0, value <= 100 {
            quantity = value
            unit = .count
        }

        // A bare count at the end of the line is how shops print a pack: "OEUF 30  45,00" is a
        // tray of thirty eggs, so the price has to be divided by the pack.
        if unit == .none, let trailing = trailingCount(strippingAmounts(trimmed)) {
            quantity = trailing
            unit = .count
        }

        let name = cleanName(trimmed)
        guard name.count >= 2, name.rangeOfCharacter(from: .letters) != nil else { return nil }

        return ReceiptLine(raw: trimmed, name: name, quantity: quantity, unit: unit, total: paid)
    }

    /// Every money-shaped number on the line, in order.
    private static func amounts(in text: String) -> [Double] {
        let range = NSRange(text.startIndex..., in: text)
        return moneyPattern.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            var raw = String(text[r]).replacingOccurrences(of: " ", with: "")
            let parts = raw.split(whereSeparator: { $0 == "." || $0 == "," })
            let separatorCount = raw.filter { $0 == "." || $0 == "," }.count
            if separatorCount > 1 {
                raw = parts.joined()                                  // 1 234,50 read as thousands
            } else if parts.count == 2, parts[1].count == 3 {
                raw = parts.joined()                                  // 1,250 means 1250 on a receipt
            } else {
                raw = raw.replacingOccurrences(of: ",", with: ".")    // 12,50 is a decimal
            }
            return Double(raw)
        }
    }

    private static func isAccountingLine(_ text: String) -> Bool {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        let words = folded.split(separator: " ").map(String.init)
        return words.contains { ignoredWords.contains($0) }
    }

    private static func cleanName(_ text: String) -> String {
        var name = text
        for pattern in [quantityPattern, volumePattern, countPattern, moneyPattern] {
            let range = NSRange(name.startIndex..., in: name)
            name = pattern.stringByReplacingMatches(in: name, range: range, withTemplate: " ")
        }
        let stopwords = ["dh", "dhs", "mad", "dirham", "dirhams", "x", "×", "kg", "kgs", "g", "gr", "grs",
                         "l", "cl", "ml", "litre", "litres"]
        let tokens = name
            .replacingOccurrences(of: "*", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: " .:;,-_|/\\\\"))
            .filter { token in
                !token.isEmpty && !stopwords.contains(token.lowercased())
            }
        return tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The line with its money amounts removed, so a pack count is the last number left.
    private static func strippingAmounts(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return moneyPattern.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    /// The last number on the line when it stands alone between 2 and 99: a pack size, not a price.
    private static func trailingCount(_ text: String) -> Double? {
        let pattern = try! NSRegularExpression(pattern: #"(?<![.,\d])(\d{1,2})\s*$"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text),
              let value = Double(text[r]), value >= 2, value <= 99 else { return nil }
        return value
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

/// Picks the food a receipt row most likely refers to.
enum ReceiptMatcher {
    /// Shop receipts in Morocco are printed in French while the diary is usually written in
    /// English, so a plain word overlap finds nothing. This bridges the everyday food words.
    private static let glossary: [String: [String]] = [
        "poulet": ["chicken"], "blanc": ["breast", "white"], "boeuf": ["beef"],
        "veau": ["veal"], "agneau": ["lamb"], "hache": ["beef", "ground", "minced"],
        "dinde": ["turkey"], "poisson": ["fish"], "thon": ["tuna"], "saumon": ["salmon"],
        "sardine": ["sardines"], "crevette": ["shrimp"], "oeuf": ["egg"], "oeufs": ["egg"],
        "lait": ["milk"], "fromage": ["cheese"], "yaourt": ["yogurt", "yoghurt"],
        "beurre": ["butter"], "huile": ["oil"], "olive": ["olive"], "riz": ["rice"],
        "pain": ["bread"], "farine": ["flour"], "sucre": ["sugar"], "sel": ["salt"],
        "dattes": ["dates"], "datte": ["dates"], "banane": ["banana"], "bananes": ["banana"],
        "pomme": ["apple"], "pommes": ["apple", "potato"], "terre": ["potato"],
        "patate": ["potato"], "douce": ["sweet"],
        "tomate": ["tomato"], "tomates": ["tomato"], "avocat": ["avocado"],
        "orange": ["orange"], "citron": ["lemon"], "raisin": ["grapes"],
        "legumes": ["vegetables"], "salade": ["salad"], "eau": ["water"], "jus": ["juice"],
        "cafe": ["coffee"], "the": ["tea"], "chocolat": ["chocolate"], "miel": ["honey"],
        "amande": ["almond"], "amandes": ["almond"], "noix": ["walnut", "nuts"],
        "flocons": ["oats"], "avoine": ["oats"], "semoule": ["semolina"], "couscous": ["couscous"]
    ]

    /// Tokens plus their equivalents in the other language.
    static func expanded(_ tokens: Set<String>) -> Set<String> {
        var result = tokens
        for token in tokens {
            if let equivalents = glossary[token] { result.formUnion(equivalents) }
            for (french, english) in glossary where english.contains(token) {
                result.insert(french)
            }
        }
        return result
    }

    static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        return Set(folded.split(separator: " ").map(String.init).filter { $0.count >= 3 })
    }

    static func score(_ line: ReceiptLine, food: Food) -> Double {
        let a = expanded(tokens(line.name))
        let b = expanded(tokens(food.name + " " + food.brand))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let shared = a.intersection(b).count
        guard shared > 0 else { return 0 }
        return Double(shared) / Double(min(a.count, b.count))
    }

    /// The foods that might be what a row refers to, best first.
    static func candidates(for line: ReceiptLine, in foods: [Food], limit: Int = 5) -> [(food: Food, score: Double)] {
        foods
            .map { (food: $0, score: score(line, food: $0)) }
            .filter { $0.score >= 0.3 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// What a row implies for a food's price, given what the receipt printed.
    static func price(for line: ReceiptLine, food: Food) -> FoodPrice? {
        if let grams = line.grams, grams > 0 {
            return FoodPrice(per100g: line.total / grams * 100,
                             boughtGrams: grams,
                             paid: line.total)
        }
        if let count = line.count, count > 0 {
            return FoodPrice(perServing: line.total / count,
                             boughtServings: count,
                             paid: line.total)
        }
        // No quantity printed: the row is treated as one serving only when the food has no weight.
        if food.gramsPerServing == nil {
            return FoodPrice(perServing: line.total)
        }
        return nil
    }
}
