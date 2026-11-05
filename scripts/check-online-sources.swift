#!/usr/bin/env swift
// Optional, read-only public service smoke check. No account or token needed.
import Foundation

@main
struct OnlineSourceChecks {
    static func main() async {
        do {
            var components = URLComponents(string: "https://api.mangadex.org/manga")!
            components.queryItems = [.init(name: "limit", value: "1"), .init(name: "includes[]", value: "cover_art"), .init(name: "includes[]", value: "author"), .init(name: "contentRating[]", value: "safe")]
            var request = URLRequest(url: components.url!); request.timeoutInterval = 30
            request.setValue("Koma/1.0 (local macOS reader source check)", forHTTPHeaderField: "User-Agent")
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: body) as? [String: Any], object["result"] as? String == "ok",
                  let data = object["data"] as? [[String: Any]], let id = data.first?["id"] as? String else {
                throw NSError(domain: "SourceCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "MangaDex unavailable or schema changed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
            }
            print("PASS MangaDex catalog: \(id)")
            var feed = URLComponents(string: "https://api.mangadex.org/manga/\(id)/feed")!
            feed.queryItems = [.init(name: "limit", value: "1"), .init(name: "translatedLanguage[]", value: "en"), .init(name: "includeExternalUrl", value: "0")]
            let (_, feedResponse) = try await URLSession.shared.data(from: feed.url!)
            guard (feedResponse as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain: "SourceCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "MangaDex feed unavailable"]) }
            print("PASS MangaDex chapter feed")
            var aniList = URLRequest(url: URL(string: "https://graphql.anilist.co")!); aniList.httpMethod = "POST"; aniList.timeoutInterval = 30
            aniList.setValue("application/json", forHTTPHeaderField: "Content-Type")
            aniList.httpBody = try JSONSerialization.data(withJSONObject: ["query": "query { Page(perPage: 1) { media(type: MANGA) { id } } }"])
            let (anibody, aniresponse) = try await URLSession.shared.data(for: aniList)
            let aniobject = try JSONSerialization.jsonObject(with: anibody) as? [String: Any]
            guard (aniresponse as? HTTPURLResponse)?.statusCode == 200, aniobject?["data"] != nil else { throw NSError(domain: "SourceCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "AniList public search unavailable"]) }
            print("PASS AniList public GraphQL search (account writes not tested)")
        } catch { fputs("Source check: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
