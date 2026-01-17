//  ApiService.swift
//  ApiService.swift
//  LinkedInCompanionApp
//
//  Created by Gnanendra Naidu N on 01/07/25.
//

import Foundation

class ApiService {
    static let shared = ApiService()
    private let baseURL = "https://backend.einsteini.ai/api"

    private var authToken: String? {
        get { UserDefaults.standard.string(forKey: "authToken") }
        set { UserDefaults.standard.set(newValue, forKey: "authToken") }
    }

    private init() {}

    // MARK: - Login



    // MARK: - Signup
    func signup(name: String, email: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        let url = URL(string: "\(baseURL)/auth/signup")!
        let body = ["name": name, "email": email, "password": password]

        sendPOSTRequest(to: url, body: body) { result in
            switch result {
            case .success(let json):
                if let token = json["token"] as? String {
                    self.authToken = token
                    UserDefaults.standard.set(true, forKey: "isLoggedIn")
                    UserDefaults.standard.set(email, forKey: "userEmail")
                    UserDefaults.standard.set(name, forKey: "userName")
                    completion(true, nil)
                } else {
                    completion(false, "Signup failed: Token not received")
                }
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }

    // MARK: - Logout
    func logout(completion: @escaping (Bool) -> Void) {
        authToken = nil
        UserDefaults.standard.removeObject(forKey: "isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "subscriptionStatus")
        UserDefaults.standard.removeObject(forKey: "remainingComments")
        completion(true)
    }

    func isLoggedIn() -> Bool {
        return authToken != nil
    }

    private var headers: [String: String] {
        var base = ["Content-Type": "application/json"]
        if let token = authToken {
            base["Authorization"] = "Bearer \(token)"
        }
        return base
    }

    // MARK: - New Features

    func getSubscriptionType(email: String, completion: @escaping (String?, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/getProductDetails") else {
            completion(nil, "Invalid URL")
            return
        }

        let body = ["email": email]

        sendPOSTRequest(to: url, body: body) { result in
            switch result {
            case .success(let json):
                if let product = json["product"] as? String {
                    completion(product, nil)
                } else {
                    completion(nil, "Product field missing in response")
                }
            case .failure(let error):
                completion(nil, error.localizedDescription)
            }
        }
    }

    func getRemainingComments(email: String, completion: @escaping (Int?) -> Void) {
        guard let url = URL(string: "https://backend.einsteini.ai/api/getNOC") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data = data,
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let remaining = result["NOC"] as? Int else {
                    completion(nil)
                    return
                }

                UserDefaults.standard.set(remaining, forKey: "remainingComments")
                completion(remaining)
            }
        }.resume()
    }


    func logCommentUsage(email: String) {
        guard let url = URL(string: "\(baseURL)/logCommentUsage") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers

        let body = ["email": email]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Generic POST Request
    private func sendPOSTRequest(to url: URL, body: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                    return
                }

                completion(.success(json))
            }
        }.resume()
    }
}
