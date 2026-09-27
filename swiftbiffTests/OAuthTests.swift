import Foundation
import Testing
@testable import SwiftBiff

struct OAuthTests {
    @Test func challengeMatchesRFC7636Example() {
        #expect(codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomTokenIsAValidVerifier() {
        let token = randomToken()
        #expect(token.count == 64)
        #expect(token.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) })
        #expect(token != randomToken())
    }

    @Test func consentURLHasRequiredParameters() throws {
        let url = consentURL(clientID: "id", redirectURI: "http://127.0.0.1:1234", challenge: "abc", state: "xyz")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")
        #expect(items["client_id"] == "id")
        #expect(items["redirect_uri"] == "http://127.0.0.1:1234")
        #expect(items["response_type"] == "code")
        #expect(items["scope"] == "https://www.googleapis.com/auth/gmail.metadata")
        #expect(items["code_challenge"] == "abc")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["state"] == "xyz")
        #expect(items["prompt"] == "consent")
    }

    @Test func callbackReturnsCode() throws {
        let line = "GET /?state=xyz&code=4%2F0Abc&scope=https://www.googleapis.com/auth/gmail.metadata HTTP/1.1"
        #expect(try parseCallback(line, expectedState: "xyz") == "4/0Abc")
    }

    @Test func callbackRejectsWrongState() {
        let line = "GET /?state=evil&code=4%2F0Abc HTTP/1.1"
        #expect(throws: OAuthError.stateMismatch) { try parseCallback(line, expectedState: "xyz") }
    }

    @Test func callbackSurfacesError() {
        let line = "GET /?error=access_denied&state=xyz HTTP/1.1"
        #expect(throws: OAuthError.denied("access_denied")) { try parseCallback(line, expectedState: "xyz") }
    }

    @Test func loopbackListenerReceivesCallback() async throws {
        let (code, redirectURI) = try await receiveCallback(state: "xyz", timeout: .seconds(10)) { redirectURI in
            let url = URL(string: "\(redirectURI)/?state=xyz&code=4%2F0Abc")!
            let page = try? await URLSession.shared.data(from: url).0
            #expect(String(decoding: page ?? Data(), as: UTF8.self).contains("You can close this tab"))
        }
        #expect(code == "4/0Abc")
        #expect(redirectURI.hasPrefix("http://127.0.0.1:"))
    }

    @Test func loopbackListenerIgnoresWrongState() async throws {
        let (code, _) = try await receiveCallback(state: "xyz", timeout: .seconds(10)) { redirectURI in
            for query in ["state=evil&code=bad", "state=xyz&code=good"] {
                _ = try? await URLSession.shared.data(from: URL(string: "\(redirectURI)/?\(query)")!)
            }
        }
        #expect(code == "good")
    }

    @Test func loopbackListenerTimesOut() async {
        await #expect(throws: OAuthError.timedOut) {
            try await receiveCallback(state: "xyz", timeout: .milliseconds(100)) { _ in }
        }
    }

    @Test func invalidGrantBodyMapsToInvalidGrant() {
        let body = Data(#"{"error": "invalid_grant", "error_description": "Token has been expired or revoked."}"#.utf8)
        #expect(tokenError(status: 400, body: body) == .invalidGrant)
    }

    @Test func otherTokenErrorsKeepStatus() {
        let body = Data(#"{"error": "invalid_client"}"#.utf8)
        #expect(tokenError(status: 401, body: body) == .http(401))
    }
}
