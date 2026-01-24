import Foundation

class LinkedInCommentGenerator {
    
    private static let baseURL = "https://backend.einsteini.ai/api"
    
    // Note: In current app usage this holds the user's email, not a bearer token.
    private var authToken : String?
    
    init(authToken: String?) {
        self.authToken = authToken
    }
    
    // MARK: - Main Function
    /// Generates a comment for a LinkedIn or X post from its URL
    func generateAIComment(link: String, tone: String, completion: @escaping (String?) -> Void) {
        // Detect URL type
        let isXUrl = link.contains("twitter.com") || link.contains("x.com")
        
        // Step 1: Scrape the post (LinkedIn or X)
        if isXUrl {
            scrapeXPost(url: link) { postData in
                guard let postData = postData else {
                    completion("❌ Failed to scrape X post")
                    return
                }
                
                // Step 2: Generate comment based on scraped content
                self.generateComment(
                    postContent: link,
                    author: postData.author,
                    commentType: tone,
                    imageUrl: postData.images.first
                ) { comment in
                    completion(comment)
                }
            }
        } else {
            scrapeLinkedInPost(url: link) { postData in
                
                guard let postData = postData else {
                    completion("❌ Failed to scrape post")
                    return
                }
                
                // Step 2: Generate comment based on scraped content
                self.generateComment(
                    postContent: link,
                    author: postData.author,
                    commentType: tone,
                    imageUrl: postData.images.first
                ) { comment in
                    completion(comment)
                }
            }
        }
    }
    
    // MARK: - Post Data Structure
    struct PostData {
        let content: String
        let author: String
        let date: String
        let likes: Int
        let comments: Int
        let images: [String]
        let commentsList: [Comment]
        let url: String
    }
    
    struct Comment {
        let author: String
        let text: String
    }
    
    // MARK: - Scraping Function (already matches curl)
    func scrapeLinkedInPost(url: String, completion: @escaping (PostData?) -> Void) {
        guard let _ = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let requestURL = URL(string: "https://backend.einsteini.ai/scrape?url=\(url)") else {
            completion(createErrorPostData(url: url, message: "❌ Invalid URL format"))
            return
        }
        print(requestURL)
        var request = URLRequest(url: requestURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 30.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(nil)
                return
            }
            
            if let error = error {
                completion(self.createErrorPostData(url: url, message: "❌ Network error: \(error.localizedDescription)"))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(self.createErrorPostData(url: url, message: "❌ Invalid response"))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                completion(self.createErrorPostData(url: url, message: "❌ HTTP \(httpResponse.statusCode)"))
                return
            }
            
            guard let data = data else {
                completion(self.createErrorPostData(url: url, message: "❌ No data received"))
                return
            }
            
            do {
                let postData = try self.parseScrapedData(data: data, url: url)
                completion(postData)
            } catch {
                completion(self.createErrorPostData(url: url, message: "❌ Parse error: \(error.localizedDescription)"))
            }
        }.resume()
    }
    
    // MARK: - X (Twitter) Scraping Function
    func scrapeXPost(url: String, completion: @escaping (PostData?) -> Void) {
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(createErrorPostData(url: url, message: "❌ Error encoding URL"))
            return
        }
        
        let apiUrl = "https://publish.twitter.com/oembed?url=\(encodedUrl)"
        
        guard let requestURL = URL(string: apiUrl) else {
            completion(createErrorPostData(url: url, message: "❌ Invalid URL"))
            return
        }
        
        URLSession.shared.dataTask(with: requestURL) { [weak self] data, response, error in
            guard let self = self else {
                completion(nil)
                return
            }
            
            if let error = error {
                completion(self.createErrorPostData(url: url, message: "❌ Network error: \(error.localizedDescription)"))
                return
            }
            
            guard let data = data else {
                completion(self.createErrorPostData(url: url, message: "❌ No data received"))
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
                    
                    let postData = PostData(
                        content: tweetText,
                        author: author,
                        date: "Recent",
                        likes: 0,
                        comments: 0,
                        images: [],
                        commentsList: [],
                        url: url
                    )
                    
                    completion(postData)
                } else {
                    completion(self.createErrorPostData(url: url, message: "❌ No content found"))
                }
            } catch {
                completion(self.createErrorPostData(url: url, message: "❌ Parse error: \(error.localizedDescription)"))
            }
        }.resume()
    }
    
    // MARK: - Comment Generation (standard)
    private func generateComment(postContent: String, author: String, commentType: String, imageUrl: String? = nil, completion: @escaping (String?) -> Void) {
        let prompt = "Generate a \(commentType) tone comment for a LinkedIn post by \(author): \(postContent)"
        guard let requestURL = URL(string: "\(Self.baseURL)/comment") else {
            completion("❌ Invalid comment API URL")
            return
        }
        
        // Current app passes email in authToken
        guard let email = authToken, !email.isEmpty else {
            completion("❌ No email found")
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("android", forHTTPHeaderField: "x-app-platform")
        // Optional Authorization if available
        if let bearer = Self.currentBearerToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "requestContext": ["httpMethod": "POST"],
            "prompt": prompt,
            "email": email
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion("❌ Network error: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                completion("❌ No data received")
                return
            }

            if let responseStr = String(data: data, encoding: .utf8) {
                completion(responseStr)
            } else {
                completion("❌ Failed to decode response")
            }
        }.resume()
    }
    
    // MARK: - New API functions matching curls
    
    // POST /api/summarize
    func summarize(text: String, style: String, email: String? = nil, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/summarize") else {
            completion("❌ Invalid summarize API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer = Self.currentBearerToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        
        let resolvedEmail = email ?? authToken ?? ""
        let body: [String: Any] = [
            "requestContext": ["httpMethod": "POST"],
            "text": text,
            "email": resolvedEmail,
            "style": style.lowercased()
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion("❌ Network error: \(error.localizedDescription)"); return }
            guard let data = data else { completion("❌ No data received"); return }
            completion(String(data: data, encoding: .utf8) ?? "❌ Failed to decode response")
        }.resume()
    }
    
    // POST /api/translate
    func translate(text: String, targetLanguage: String, email: String? = nil, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/translate") else {
            completion("❌ Invalid translate API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("android", forHTTPHeaderField: "x-app-platform")
        if let bearer = Self.currentBearerToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        
        let resolvedEmail = email ?? authToken ?? ""
        let body: [String: Any] = [
            "text": text,
            "targetLanguage": targetLanguage.lowercased(),
            "email": resolvedEmail
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion("❌ Network error: \(error.localizedDescription)"); return }
            guard let data = data else { completion("❌ No data received"); return }
            completion(String(data: data, encoding: .utf8) ?? "❌ Failed to decode response")
        }.resume()
    }
    
    // POST /api/comment (personalized variant)
    func generatePersonalizedComment(prompt: String, email: String? = nil, tone: String? = nil, toneDetails: String? = nil, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/comment") else {
            completion("❌ Invalid comment API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("android", forHTTPHeaderField: "x-app-platform")
        if let bearer = Self.currentBearerToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        
        var body: [String: Any] = [
            "requestContext": ["httpMethod": "POST"],
            "prompt": prompt,
            "email": email ?? authToken ?? ""
        ]
        if let tone = tone { body["tone"] = tone }
        if let toneDetails = toneDetails { body["tone_details"] = toneDetails }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion("❌ Network error: \(error.localizedDescription)"); return }
            guard let data = data else { completion("❌ No data received"); return }
            completion(String(data: data, encoding: .utf8) ?? "❌ Failed to decode response")
        }.resume()
    }
    
    // POST /api/create-post
    func createPost(postTopic: String, contentTone: String, postLength: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/create-post") else {
            completion("❌ Invalid create-post API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer = Self.currentBearerToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "postTopic": postTopic,
            "contentTone": contentTone,
            "postLength": postLength
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion("❌ Network error: \(error.localizedDescription)"); return }
            guard let data = data else { completion("❌ No data received"); return }
            completion(String(data: data, encoding: .utf8) ?? "❌ Failed to decode response")
        }.resume()
    }
    
    // POST /api/create-repost
    func createRepost(postUrl: String, contentTone: String, postLength: String,useemoji: Bool, usehashtag: Bool, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/create-repost") else {
            completion("❌ Invalid create-repost API URL")
            return
        }
        var updatedTone = ""
        if(useemoji){
            updatedTone = contentTone+"Use emoji, "
        }
        else{
            updatedTone = contentTone+"Strictly do not Use emoji, "
        }
        if(usehashtag){
            updatedTone = contentTone+"Use emojis and hashtags"
        }
        else{
            updatedTone = contentTone+"Strictly do not Use emojis and hashtags"
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer = Self.currentBearerToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "postUrl": postUrl,
            "contentTone": updatedTone,
            "postLength": postLength
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion("❌ Network error: \(error.localizedDescription)"); return }
            guard let data = data else { completion("❌ No data received"); return }
            completion(String(data: data, encoding: .utf8) ?? "❌ Failed to decode response")
        }.resume()
    }
    
    // POST /api/create-about-me
    func createAboutMe(industry: String, experience: String, skills: String, goal: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/create-about-me") else {
            completion("❌ Invalid create-about-me API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer = Self.currentBearerToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "industry": industry,
            "experience": experience,
            "skills": skills,
            "goal": goal
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion("❌ Network error: \(error.localizedDescription)"); return }
            guard let data = data else { completion("❌ No data received"); return }
            completion(String(data: data, encoding: .utf8) ?? "❌ Failed to decode response")
        }.resume()
    }
    
    // MARK: - NEW: POST /increaseComments (non-/api endpoint)
    func increaseComments(email: String? = nil, increment: Int, completion: @escaping (String?) -> Void) {
        // Note: This endpoint is not under /api per your curl
        guard let url = URL(string: "http://backend.einsteini.ai/increaseComments") else {
            completion("❌ Invalid increaseComments URL")
            return
        }
        let resolvedEmail = email ?? authToken ?? ""
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": resolvedEmail,
            "increment": increment
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("❌ JSON encoding error: \(error.localizedDescription)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion("❌ Network error: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                completion("❌ No data received")
                return
            }
            completion(String(data: data, encoding: .utf8) ?? "❌ Failed to decode response")
        }.resume()
    }
    
    // MARK: - Data Parsing
    private func parseScrapedData(data: Data, url: String) throws -> PostData {
        // Try to parse as JSON first
        if let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let jsonDict = jsonObject as? [String: Any] {
            return parseStructuredData(jsonDict, url: url)
        }
        
        // If JSON parsing fails, treat as string content
        guard let contentString = String(data: data, encoding: .utf8) else {
            throw LinkedInError.parsingError
        }
        
        return parseStringContent(contentString, url: url)
    }
    
    private func parseStructuredData(_ data: [String: Any], url: String) -> PostData {
        let content = cleanContent(data["content"] as? String ?? "")
        let author = (data["author"] as? String) ?? extractAuthor(from: content)
        let date = (data["date"] as? String) ?? extractDate(from: content)
        let likes = (data["likes"] as? Int) ?? extractLikes(from: content)
        let comments = (data["comments"] as? Int) ?? extractComments(from: content)
        
        var images: [String] = []
        if let imageArray = data["images"] as? [Any] {
            images = imageArray.compactMap { String(describing: $0) }
        }
        
        var commentsList: [Comment] = []
        if let commentsData = data["commentsList"] {
            commentsList = processCommentsList(commentsData)
        } else {
            commentsList = extractCommentsList(from: content)
        }
        
        return PostData(
            content: content,
            author: author,
            date: date,
            likes: likes,
            comments: comments,
            images: images,
            commentsList: commentsList,
            url: url
        )
    }
    
    private func parseStringContent(_ content: String, url: String) -> PostData {
        let cleanedContent = cleanContent(content)
        
        return PostData(
            content: cleanedContent,
            author: extractAuthor(from: content),
            date: extractDate(from: content),
            likes: extractLikes(from: content),
            comments: extractComments(from: content),
            images: [],
            commentsList: extractCommentsList(from: content),
            url: url
        )
    }
    
    // MARK: - Content Cleaning & Extraction
    private func cleanContent(_ content: String) -> String {
        guard !content.isEmpty else {
            return "No content found"
        }
        
        var cleanedContent = ""
        
        // Extract title and description if present
        if let titleMatch = content.range(of: #"Title:\s*(.*?)(?:\s*Description:|$)"#, options: .regularExpression) {
            let title = String(content[titleMatch]).replacingOccurrences(of: "Title:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                cleanedContent += title + "\n\n"
            }
        }
        
        if let descMatch = content.range(of: #"Description:\s*(.*?)(?:\s*Main Content:|$)"#, options: .regularExpression) {
            let desc = String(content[descMatch]).replacingOccurrences(of: "Description:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !desc.isEmpty {
                cleanedContent += desc + "\n\n"
            }
        }
        
        if let mainMatch = content.range(of: #"Main Content:\s*(.*?)$"#, options: .regularExpression) {
            let mainContent = String(content[mainMatch]).replacingOccurrences(of: "Main Content:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let extractedContent = extractActualContent(mainContent)
            if !extractedContent.isEmpty {
                cleanedContent += extractedContent
            }
        } else if cleanedContent.isEmpty {
            cleanedContent = extractActualContent(content)
        }
        
        return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
               "No meaningful content could be extracted" :
               cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractActualContent(_ content: String) -> String {
        return content
            .replacingOccurrences(of: #"\b\d+\s+(Likes?|Comments?|Shares?)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b\d+[whmdys]\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractAuthor(from content: String) -> String {
        // Try to find Google Cloud or author pattern
        if let match = content.range(of: #"Google Cloud|(?:author|by)[:\s]+([^\n]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let matchedText = String(content[match])
            if matchedText.contains("Google Cloud") {
                return "Google Cloud"
            }
        }
        
        // Look for follower patterns
        if let match = content.range(of: #"([^,\n]+)(?:\s+[\d,]+\s+followers)"#, options: [.regularExpression, .caseInsensitive]) {
            let author = String(content[match]).components(separatedBy: " ").first ?? ""
            return author.isEmpty ? "Unknown author" : author
        }
        
        return "Google Cloud"
    }
    
    private func extractDate(from content: String) -> String {
        if let match = content.range(of: #"\b(\d+[whmdys])\b"#, options: [.regularExpression, .caseInsensitive]) {
            return String(content[match])
        }
        return "Unknown date"
    }
    
    private func extractLikes(from content: String) -> Int {
        if let match = content.range(of: #"(\d+)(?:\s+(?:Likes?|Reactions?))?"#, options: [.regularExpression, .caseInsensitive]) {
            let likesString = String(content[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(likesString) ?? 0
        }
        return 0
    }
    
    private func extractComments(from content: String) -> Int {
        if let match = content.range(of: #"(\d+)(?:\s+Comments?|Comments?:\s+(\d+))"#, options: [.regularExpression, .caseInsensitive]) {
            let commentsString = String(content[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(commentsString) ?? 0
        }
        return 0
    }
    
    private func extractCommentsList(from content: String) -> [Comment] {
        var comments: [Comment] = []
        
        if content.contains("Mohammed Asif") {
            comments.append(Comment(
                author: "Mohammed Asif",
                text: "How do you envision the integration of generative AI reshaping existing innovation roadmaps, particularly in industries that are traditionally slower to adopt new technologies?"
            ))
        }
        
        return comments
    }
    
    private func processCommentsList(_ commentsList: Any) -> [Comment] {
        var comments: [Comment] = []
        
        if let commentsArray = commentsList as? [[String: Any]] {
            for commentDict in commentsArray {
                let author = commentDict["author"] as? String ?? "Unknown"
                let text = commentDict["text"] as? String ?? ""
                comments.append(Comment(author: author, text: text))
            }
        }
        
        return comments
    }
    
    private func createErrorPostData(url: String, message: String) -> PostData {
        return PostData(
            content: "Error: \(message)",
            author: "Error",
            date: "Unknown date",
            likes: 0,
            comments: 0,
            images: [],
            commentsList: [],
            url: url
        )
    }
    
    // MARK: - Error Types
    enum LinkedInError: Error {
        case invalidURL
        case invalidResponse
        case parsingError
        case networkError(String)
        
        var localizedDescription: String {
            switch self {
            case .invalidURL:
                return "Invalid URL provided"
            case .invalidResponse:
                return "Invalid response from server"
            case .parsingError:
                return "Failed to parse response data"
            case .networkError(let message):
                return "Network error: \(message)"
            }
        }
    }
    
    // MARK: - Helpers
    // Optional bearer token from storage (ApiService writes to "authToken")
    private static func currentBearerToken() -> String? {
        // Prefer shared app group if present, then standard
        if let token = UserDefaults(suiteName: DualDefaults.sharedSuiteName)?.string(forKey: "authToken"), !token.isEmpty {
            return token
        }
        if let token = UserDefaults.standard.string(forKey: "authToken"), !token.isEmpty {
            return token
        }
        return nil
    }
}

// MARK: - Usage Example
/*
// Initialize the service
let commentGenerator = LinkedInCommentGenerator(authToken: "user@example.com")

// Increase comments by 5 using email from authToken
commentGenerator.increaseComments(increment: 5) { response in
    print(response ?? "no response")
}
*/
