//
//  Copyright © 2017-2025 PSPDFKit GmbH. All rights reserved.
//
//  The Nutrient Sample applications are licensed with a modified BSD license.
//  Please see License for details. This notice may not be removed from this file.
//

import Foundation

enum Result<Wrapped> {
    case failure(reason: String)
    case success(Wrapped)
}

/// Generates URL requests for using the API of the example server.
struct APIClient {
    let baseURL: URL
    let userID: String
    let password: String

    /// Models a document as returned by the example server API.
    struct Document {
        let title: String
        let identifier: String
        let JWTs: [String]
    }

    func fetchDocumentListTask(completionHandler: @escaping (Result<[Document]>) -> Void) -> URLSessionTask {
        return URLSession.shared.dataTask(with: authorizedRequest(forEndpoint: "documents")) { data, response, error in
            switch resultFromJSONResponse(expectedStatusCode: 200, data: data, response: response, error: error) {

            case .failure(let reason):
                completionHandler(.failure(reason: reason))

            case .success(let jsonObject):
                guard let jsonDocuments = jsonObject["documents"] as? NSArray else {
                    completionHandler(.failure(reason: "Response is missing a documents array. \(jsonObject)"))
                    return
                }

                let documents = jsonDocuments.compactMap { document -> Document? in
                    guard
                        let document = document as? NSDictionary,
                        let title = document["title"] as? String,
                        let identifier = document["id"] as? String,
                        let JWTs = document["tokens"] as? [String]
                    else {
                        return nil
                    }

                    return Document(title: title, identifier: identifier, JWTs: JWTs)
                }

                completionHandler(.success(documents))
            }
        }
    }

    /// Models an Instant layer
    struct Layer: Hashable {
        let documentID: String
        let name: String
    }

    func fetchAuthenticationTokenTask(for layer: Layer, completionHandler: @escaping (Result<String>) -> Void) -> URLSessionTask {
        var endpoint = "document/\(layer.documentID)"
        if !layer.name.isEmpty {
            endpoint += "/\(layer.name)"
        }
        return URLSession.shared.dataTask(with: authorizedRequest(forEndpoint: endpoint)) { data, response, error in
            switch resultFromJSONResponse(expectedStatusCode: 200, data: data, response: response, error: error) {

            case .failure(let reason):
                completionHandler(.failure(reason: reason))

            case .success(let jsonObject):
                guard let authenticationToken = jsonObject["token"] as? String else {
                    completionHandler(.failure(reason: "Response is missing token. \(jsonObject)"))
                    return
                }

                completionHandler(.success(authenticationToken))
            }
        }
    }

    private func authorizedRequest(forEndpoint endpoint: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api", isDirectory: true).appendingPathComponent(endpoint, isDirectory: false))
        let base64Encoded = "\(userID):\(password)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(base64Encoded)", forHTTPHeaderField: "Authorization")
        return request
    }
}

private func resultFromJSONResponse(expectedStatusCode: Int, data: Data?, response: URLResponse?, error: Error?) -> Result<NSDictionary> {
    if let error {
        var reason = error.localizedDescription
        let errorCode = (error as NSError).code
        if errorCode == NSURLErrorNotConnectedToInternet || errorCode == NSURLErrorTimedOut {
            reason = "The application failed to connect to the server. Please ensure that you are conected to the internet and have the Local Network access permission enabled in Settings."
        }
        return .failure(reason: reason)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        return .failure(reason: "Response is not an HTTP response")
    }

    guard httpResponse.statusCode == expectedStatusCode else {
        return .failure(reason: "Status code is \(httpResponse.statusCode) (Response body: '\(describe(body: data))')")
    }

    guard let data else {
        return .failure(reason: "No data or error")
    }

    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data, options: [])
    } catch {
        return .failure(reason: "Could not parse JSON: \(error)\nData: '\(describe(body: data))'")
    }
    guard let dictionary = object as? NSDictionary else {
        return .failure(reason: "JSON object has type \(type(of: object)) instead of \(NSDictionary.self)")
    }

    return .success(dictionary)
}

private func describe(body: Data?) -> String {
    guard let body else { return "<no body data>" }
    if let string = String(data: body, encoding: .utf8) {
        return string
    } else {
        return "Body isn’t even UTF-8…"
    }
}
