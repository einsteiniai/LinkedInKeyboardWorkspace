import Foundation
import UIKit

class LinkedInCommentGenerator {
    
    private static let baseURL = "https://backend.einsteini.ai/api"
    private static let scrapeBase = "https://backend.einsteini.ai"
    
    private var authToken : String?
    
    init(authToken: String?) {
        self.authToken = authToken
        
    }
    
    
    
    func generateComment(
        url: String,
        tone: String,
        includeEmoji: Bool,
        emojiText: String?,
        includeHashtag: Bool,
        hashtagText: String?,
        language: String? = "English",
        completion: @escaping (String?) -> Void
    ) {
        performScrape(for: url) { scraped in
            let postText = scraped?.content ?? ""
            let author = scraped?.author ?? "Unknown author"
            var prompt = ""
            if url.contains("x.com") || url.contains("twitter.com") {
                prompt = self.buildPrompt_X(
                    tone: tone,
                    postText: postText,
                    author: author,
                    language: language ?? "English",
                    includeEmoji: includeEmoji,
                    emojiText: emojiText,
                    includeHashtag: includeHashtag,
                    hashtagText: hashtagText
                )
                }

                if url.contains("linkedin.com") {
                    prompt = self.buildPrompt_Linkedin(
                        tone: tone,
                        postText: postText,
                        author: author,
                        language: language ?? "English",
                        includeEmoji: includeEmoji,
                        emojiText: emojiText,
                        includeHashtag: includeHashtag,
                        hashtagText: hashtagText
                    )
                }
            
            self.callCommentAPI(prompt: prompt, email: self.authToken ?? "", completion: completion)        }
    }


    private func performScrape(for urlString: String, completion: @escaping ((content: String, author: String)?) -> Void) {
        // Detect URL type
        let isXUrl = urlString.contains("twitter.com") || urlString.contains("x.com")
        
        if isXUrl {
            // Use X/Twitter oEmbed API
            scrapeXPost(url: urlString, completion: completion)
        } else {
            // Use LinkedIn backend scraper
            scrapeLinkedInPost(url: urlString, completion: completion)
        }
    }
    
    private func scrapeLinkedInPost(url: String, completion: @escaping ((content: String, author: String)?) -> Void) {
        // Construct query properly
        guard var components = URLComponents(string: "https://backend.einsteini.ai/scrape") else {
            completion(nil)
            return
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: url)
        ]

        guard let requestURL = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 30.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error:", error.localizedDescription)
                completion(nil)
                return
            }

            guard let data = data else {
                print("⚠️ No data returned")
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let content = (json["content"] as? String) ??
                                  (json["text"] as? String) ??
                                  String(data: data, encoding: .utf8) ?? ""
                    let author = (json["author"] as? String) ?? "Unknown author"
                    completion((content: content, author: author))
                } else {
                    let asString = String(data: data, encoding: .utf8) ?? ""
                    completion((content: asString, author: "Unknown author"))
                }
            } catch {
                print("⚠️ JSON parse error:", error.localizedDescription)
                let asString = String(data: data, encoding: .utf8) ?? ""
                completion((content: asString, author: "Unknown author"))
            }
        }.resume()
    }
    
    private func scrapeXPost(url: String, completion: @escaping ((content: String, author: String)?) -> Void) {
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(nil)
            return
        }
        
        let apiUrl = "https://publish.twitter.com/oembed?url=\(encodedUrl)"
        
        guard let requestURL = URL(string: apiUrl) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: requestURL) { data, response, error in
            if let error = error {
                print("❌ Error:", error.localizedDescription)
                completion(nil)
                return
            }
            
            guard let data = data else {
                print("⚠️ No data returned")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let html = json["html"] as? String {
                    
                    // Parse X/Twitter oEmbed response - strip HTML tags
                    let tweetText = html
                        .replacingOccurrences(of: "<blockquote[^>]*>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "</blockquote>", with: "")
                        .replacingOccurrences(of: "<a[^>]*>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "</a>", with: "")
                        .replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "</p>", with: " ")
                        .replacingOccurrences(of: "<br[^>]*>", with: " ", options: .regularExpression)
                        .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "&mdash;", with: "—")
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&#39;", with: "'")
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let author = json["author_name"] as? String ?? "Unknown author"
                    
                    completion((content: tweetText, author: author))
                } else {
                    completion(nil)
                }
            } catch {
                print("⚠️ JSON parse error:", error.localizedDescription)
                completion(nil)
            }
        }.resume()
    }

    
    
    // MARK: - Helper function for showing alerts
    private func showAlert(on viewController: UIViewController, title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }

    private func callCommentAPI(prompt: String, email: String, completion: @escaping (String?) -> Void) {
        // Build the comment API URL safely
        let commentEndpoint = Self.baseURL.hasSuffix("/") ? "comment" : "/comment"
        guard let url = URL(string: Self.baseURL + commentEndpoint) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("android", forHTTPHeaderField: "x-app-platform")

        let body: [String: Any] = [
            
            "email": self.authToken ?? "gnanendranaidun101@gmail.com",
            "prompt": prompt,
            
            "requestContext": ["httpMethod": "POST"]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let _ = error {
                completion(nil)
                return
            }
            guard let data = data else {
                completion(nil)
                return
            }
            let respStr = String(data: data, encoding: .utf8)
            completion(respStr)
        }.resume()
    }
    
    private func buildPrompt_X(
        tone: String,
        postText: String,
        author: String,
        language: String,
        includeEmoji: Bool,
        emojiText: String?,
        includeHashtag: Bool,
        hashtagText: String?
    ) -> String {

        let t = tone.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var basePrompt: String

        switch t {

        case "applaud":
            basePrompt = """
            Write a short, positive, and authentic reply in \(language) for an X (Twitter) post that congratulates or applauds the author. Keep it casual and human. Do not promote anything or ask questions.

            Post: \(postText)
            Author: \(author)
            """

        case "agree":
            basePrompt = """
            Generate a concise X (Twitter) reply (under 12 words) in \(language) that clearly expresses agreement with the author's point.

            Guidelines:
            - Sound natural and conversational.
            - Avoid repeating the post text.
            - No quotes.

            Post: \(postText)
            Author: \(author)
            """

        case "fun":
            basePrompt = """
            Write a fun, witty, and relatable reply in \(language) for this X (Twitter) post.

            Guidelines:
            - Light humor or clever observation.
            - Casual and human, not forced.
            - Relevant to the post content.
            - Avoid offensive or edgy jokes.

            Post: \(postText)
            Author: \(author)
            """

        case "perspective":
            basePrompt = """
            Generate a thoughtful yet concise reply in \(language) for an X (Twitter) post by \(author) that adds a fresh perspective or builds on their idea.

            Guidelines:
            - Acknowledge the idea naturally.
            - Add a new angle or insight.
            - Keep it under 30 words.
            - No quotes.

            Post: \(postText)
            """

        case "question":
            basePrompt = """
            Write a meaningful, curiosity-driven question in \(language) as a reply to this X (Twitter) post.

            Guidelines:
            - Directly relate to the post.
            - Encourage discussion.
            - Keep it short (under 25 words).
            - Avoid generic phrases.

            Post: \(postText)
            Author: \(author)
            """

        case "repost":
            basePrompt = """
            Generate a short repost (retweet with comment) caption in \(language) for an X (Twitter) post by \(author).

            Guidelines:
            - Add a personal takeaway or insight.
            - Avoid generic praise.
            - Keep it under 30 words.
            - No quotes.

            Post: \(postText)
            """

        default:
            basePrompt = """
            Generate a short, natural X (Twitter) reply in \(language) for the post by \(author).

            Post: \(postText)
            """
        }

        var additions = ""

        if includeEmoji {
            additions += "\n\nWhen producing the reply, you may use suitable emojis sparingly."
        } else {
            additions += "\n\nWhen producing the reply, strictly do not use any emojis."
        }

        if includeHashtag {
            additions += "\n\nWhen producing the reply, you may use relevant hashtags (max 1–2)."
        } else {
            additions += "\n\nWhen producing the reply, strictly do not use any hashtags."
        }

        additions += "\n\nEnsure the reply feels natural for X and stays concise."

        return basePrompt + additions
    }


    private func buildPrompt_Linkedin(
        tone: String,
        postText: String,
        author: String,
        language: String,
        includeEmoji: Bool,
        emojiText: String?,
        includeHashtag: Bool,
        hashtagText: String?
    ) -> String {
        let t = tone
        var basePrompt: String
        switch t {
        case "applaud", " applaud", "Applaud", "Applaud ", " Applaud", " Applaud ":
            basePrompt = """
            Write a short, positive, and genuine comment in \(language) that applauds or congratulates the author for their post. Do not mention any products, companies, or ask any questions. Just express appreciation or applause in a friendly, human way.

            Post: \(postText)
            Author: \(author)
            """
        case "agree", " agree", "Agree", " Agree", " Agree ", "Agree ":
            basePrompt = """
            Generate a short (max 10 words) LinkedIn comment in \(language) that expresses agreement with a post by \(author). Avoid using quotation marks, emojis, or hashtags.

            Guidelines:
            1. Make the tone friendly and conversational.
            2. Acknowledge the main message of the post naturally.
            3. Keep it simple, relatable, and human.
            4. Avoid repeating the exact words of the post or being overly generic.

            Post: \(postText)
            Author: \(author)
            """
        case "fun", " fun", "Fun", " Fun", "Fun ", " Fun ":
            basePrompt = """
            Generate an engaging, genuine, and human-like fun comment in \(language) for this LinkedIn post:

            Post: \(postText)
            Author: \(author)

            Reply to this LinkedIn post with a comment that contains a touch of humor or amusement, while still being respectful and relevant.

            The comment should:
            - Feel human and simple.
            - Have a tinge of humor.
            - Not use quotes.
            - Be a very humorous person, like people can't help but laugh at your jokes.
            - Jokes must align with societal norms and LinkedIn terms and conditions.
            - Analyze the description and image (if provided) to relate to a similar experience or common situation.
            - Use varied language and structure to avoid repetitive phrasing.
            - Don't always start with "Wow".
            """
        case "perspective","perspective ", " perspective ", " perspective", "Perspective", "Perspective ", " Perspective", " Perspective ":
            basePrompt = """
            Read the post by \(author) titled "\(postText)". Generate a thoughtful and unique comment in \(language) that offers a fresh perspective or expands on the author's ideas, ensuring it feels natural and conversational.

            Guidelines:
            1. Start by acknowledging or appreciating the author's viewpoint in a friendly, non-repetitive way.
            2. Offer a new perspective or build on the ideas presented without contradicting the author.
            3. Keep the tone positive and encouraging.
            4. Keep the language simple, friendly, and human-like.
            5. Avoid using any quotes, hashtags, or emojis.
            6. Keep the reply short, around 20-30 words.
            7. Make sure every comment generated feels personal and unique.
            """
        case "question", " question", "Question", " Question", "Question ", " Question ":
            basePrompt = """
            Generate a unique, thoughtful, human-like question in \(language) for a LinkedIn post by \(author). The question should express genuine curiosity and encourage further discussion in a natural and professional manner.

            Guidelines:
            1. Start by acknowledging the author's post in a way that feels personal and tailored.
            2. Ask a specific, meaningful question that relates directly to the content of the post.
            3. Avoid generic phrases like "Great post" or "Nice work."
            4. Keep the tone conversational, warm, and professional.
            5. Ensure the language is clear and concise, limiting the question to under 30 words.
            6. No quotes, emojis, or hashtags.

            Post: \(postText)
            Author: \(author)
            """
        case "Repost", " Repost", "Repost ", " Repost ", "repost", " repost", "repost "," repost ":
            basePrompt = """
            Generate a unique, thoughtful, human-like repost caption in \(language) for a LinkedIn post by \(author). The caption should provide an original perspective while staying relevant to the author’s content.

            Guidelines:
            1. Begin with a concise, personalized reflection that connects to the original post.
            2. Add a meaningful insight, takeaway, or opinion that builds on the author’s message.
            3. Avoid generic phrases like "Great post" or "Must read."
            4. Keep the tone conversational, warm, and professional.
            5. Ensure the caption is clear and concise, limited to under 35 words.
            6. No quotes, emojis, or hashtags.

            Post: \(postText)
            Author: \(author)
            """

        default:
            basePrompt = "Generate a short, friendly LinkedIn comment in \(language) for the post by \(author): \(postText)"
        }

        var additions = ""
        if includeEmoji{
            additions += "\n\nWhen producing the comment, Use Suitable emojis"
        }
        else{
            additions += "\n\nWhen producing the comment, Strictly Do not use any emojis"
        }
        if includeHashtag{
            additions += "\n\nWhen producing the comment, Use Suitable hashtags"
        }
        else{
            additions += "\n\nWhen producing the comment, Strictly Do not use any hashtags"
        }

        return basePrompt + additions
    }

}
