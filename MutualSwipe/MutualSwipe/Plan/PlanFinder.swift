import Foundation
import MapKit
import MutualKit

/// Looks places up in Apple Maps: where they are, their address and their
/// website. Answers are kept for the session, so a card's map only searches once.
@MainActor
enum PlaceFinder {
    struct Found: Equatable {
        let latitude: Double
        let longitude: Double
        let address: String
        let website: String

        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    private static var cache: [String: Found] = [:]
    private static var misses: Set<String> = []

    static func find(_ query: String, near: CLLocationCoordinate2D? = nil) async -> Found? {
        let key = query.lowercased()
        guard !key.isEmpty, !misses.contains(key) else { return nil }
        if let hit = cache[key] { return hit }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let near {
            request.region = MKCoordinateRegion(center: near, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            misses.insert(key)
            return nil
        }
        let mark = item.placemark
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, mark.locality].filter { !($0 ?? "").isEmpty }.compactMap { $0 }.joined(separator: ", ")
        let found = Found(latitude: mark.coordinate.latitude, longitude: mark.coordinate.longitude, address: address,
                          website: item.url.map { CardText.safeURL($0.absoluteString) } ?? "")
        cache[key] = found
        return found
    }

    /// Fills in where each stop is, plus any missing address or website.
    /// Each search looks near the stop before it.
    static func locate(_ plan: Itinerary) async -> Itinerary {
        var plan = plan
        var near: CLLocationCoordinate2D?
        for index in plan.stops.indices {
            var stop = plan.stops[index]
            if let lat = stop.latitude, let lon = stop.longitude {
                near = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                continue
            }
            guard !stop.place.isEmpty, let found = await find(stop.searchText(area: plan.area), near: near) else { continue }
            stop.latitude = found.latitude
            stop.longitude = found.longitude
            if stop.address.isEmpty { stop.address = found.address }
            if stop.website.isEmpty { stop.website = found.website }
            plan.stops[index] = stop
            near = found.coordinate
        }
        return plan
    }
}

/// Reads the parts of a web page Mutual uses: its title, the words on it,
/// and the photo it shares in link previews.
enum PageReader {
    struct Page {
        var title = ""
        var description = ""
        var image: URL?
        var text = ""
    }

    static func read(_ url: URL) async -> Page? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
              data.count < 4_000_000 else { return nil }
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard !html.isEmpty else { return nil }
        return parse(html, base: response.url ?? url)
    }

    static func parse(_ html: String, base: URL) -> Page {
        var page = Page()
        var meta: [String: String] = [:]
        for tag in matches("<meta\\b[^>]*>", in: html) {
            let attributes = attributesOf(tag)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"] else { continue }
            meta[key] = meta[key] ?? decode(content)
        }
        let titleTag = matches("<title[^>]*>([\\s\\S]*?)</title>", in: html, group: 1).first.map(decode) ?? ""
        page.title = (meta["og:title"] ?? meta["twitter:title"] ?? titleTag).trimmingCharacters(in: .whitespacesAndNewlines)
        page.description = meta["og:description"] ?? meta["description"] ?? ""
        if let raw = meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"],
           let image = URL(string: raw, relativeTo: base)?.absoluteURL, image.scheme?.lowercased() == "https" {
            page.image = image
        }
        page.text = visibleText(html)
        return page
    }

    /// The page's words, one block per line.
    static func visibleText(_ html: String) -> String {
        var text = html
        for pattern in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<noscript[\\s\\S]*?</noscript>",
                        "<!--[\\s\\S]*?-->", "<svg[\\s\\S]*?</svg>"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\\b[^>]*>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li\\b[^>]*>", with: "\n- ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decode(text)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "-" }
        return lines.prefix(400).joined(separator: "\n")
    }

    private static func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    private static func attributesOf(_ tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "([\\w:-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')") else { return [:] }
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let name = Range(match.range(at: 1), in: tag).map({ tag[$0].lowercased() }) else { continue }
            let value = Range(match.range(at: 2), in: tag) ?? Range(match.range(at: 3), in: tag)
            result[name] = value.map { String(tag[$0]) } ?? ""
        }
        return result
    }

    static func decode(_ text: String) -> String {
        var text = text
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                     "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&ndash;": "–", "&mdash;": "—",
                     "&middot;": "·", "&hellip;": "…", "&rarr;": "→", "&#x27;": "'"]
        for (entity, value) in named { text = text.replacingOccurrences(of: entity, with: value) }
        // Numeric entities like &#8217;.
        guard let regex = try? NSRegularExpression(pattern: "&#(\\d{2,6});") else { return text }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text),
                  let code = Int(text[digits]), let scalar = Unicode.Scalar(code) else { continue }
            text.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return text
    }
}

/// "Paste a link or text, and Mutual builds the card for you to check."
///
/// Only the outline of a pasted plan is kept: its name, times and places.
/// Its write-up and photos are left behind; photos come from each place's
/// own website instead, and people write their own notes.
@MainActor
enum PlanBuilder {
    struct Built {
        var title: String
        var link: String
        var plan: Itinerary
        /// Something to tell the person, like "Couldn't open that page".
        var notice: String?
    }

    static func build(from input: String, progress: (String) -> Void) async -> Built {
        let link = firstLink(in: input)
        let typed = input.components(separatedBy: .newlines)
            .filter { line in link.map { !line.contains($0.absoluteString) } ?? true }
            .joined(separator: "\n")
        var parsed = ItineraryText.parse(typed)
        var notice: String?

        if let link {
            progress("Reading the page…")
            if let page = await PageReader.read(link) {
                if parsed.plan.stops.isEmpty {
                    let fromPage = ItineraryText.parse([page.title, page.description, page.text].joined(separator: "\n"))
                    parsed.plan = fromPage.plan
                }
                if parsed.title.isEmpty || parsed.plan.stops.isEmpty {
                    parsed.title = page.title.isEmpty ? parsed.title : String(page.title.prefix(120))
                }
                if parsed.plan.area.isEmpty { parsed.plan.area = ItineraryText.area(in: parsed.title) }
                if parsed.plan.stops.isEmpty {
                    notice = "Couldn’t find the stops on that page. Add them below."
                }
            } else {
                notice = "Couldn’t open that page. Add the stops below."
            }
        }

        if !parsed.plan.stops.isEmpty {
            progress("Finding the places…")
            parsed.plan = await PlaceFinder.locate(parsed.plan)
            progress("Getting photos from the places’ websites…")
            parsed.plan.photos = await venuePhotos(for: parsed.plan)
        }
        return Built(title: parsed.title, link: link.map { CardText.safeURL($0.absoluteString) } ?? "",
                     plan: parsed.plan.cleaned(), notice: notice)
    }

    /// The photo each stop's own website shares, in stop order.
    static func venuePhotos(for plan: Itinerary) async -> [String] {
        var photos = plan.photos
        for stop in plan.stops where photos.count < Itinerary.maxPhotos {
            guard let site = URL(string: stop.website), !stop.website.isEmpty,
                  let image = await PageReader.read(site)?.image else { continue }
            if !photos.contains(image.absoluteString) { photos.append(image.absoluteString) }
        }
        return photos
    }

    static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        guard let url = match?.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
