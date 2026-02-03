import SwiftUI
import WebKit

#if os(iOS)
/// WebView for logging into Outlier and capturing cookies
struct OutlierLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var loginSuccess = false
    @State private var showManualEntry = false
    @State private var manualCookie = ""
    @State private var manualCsrf = ""
    var onLogin: ((String, String) -> Void)? // (cookie, csrf)
    
    var body: some View {
        NavigationStack {
            ZStack {
                if showManualEntry {
                    manualEntryView
                } else {
                    OutlierWebView(
                        isLoading: $isLoading,
                        onCookiesCaptured: { cookie, csrf in
                            loginSuccess = true
                            onLogin?(cookie, csrf)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                dismiss()
                            }
                        }
                    )
                    
                    if isLoading {
                        ProgressView("Loading...")
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    }
                    
                    if loginSuccess {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.green)
                            Text("Login Successful!")
                                .font(.title2)
                                .bold()
                        }
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
            }
            .navigationTitle(showManualEntry ? "Manual Entry" : "Login to Outlier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(showManualEntry ? "Use WebView" : "Manual Entry") {
                        showManualEntry.toggle()
                    }
                }
            }
        }
    }
    
    // MARK: - Manual Entry View
    
    private var manualEntryView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cookie String")
                        .font(.headline)
                    TextEditor(text: $manualCookie)
                        .frame(height: 100)
                        .font(.system(.caption, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3))
                        )
                    Text("Must contain _jwt=...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Cookie")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("X-CSRF-Token")
                        .font(.headline)
                    TextField("Paste CSRF token here", text: $manualCsrf)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("CSRF Token")
            }
            
            Section {
                Button {
                    if !manualCookie.isEmpty {
                        onLogin?(manualCookie, manualCsrf)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Save Credentials")
                            .bold()
                        Spacer()
                    }
                }
                .disabled(manualCookie.isEmpty || !manualCookie.contains("_jwt="))
            }
            
            Section {
                howToGetCredentialsView
            } header: {
                Text("How to Get Credentials")
            }
        }
    }
    
    private var howToGetCredentialsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepView(1, "Open app.outlier.ai in Chrome/Safari")
            stepView(2, "Login to your account")
            stepView(3, "Open DevTools (F12 or Cmd+Opt+I)")
            stepView(4, "Go to Network tab")
            stepView(5, "Refresh the page")
            stepView(6, "Click any request to app.outlier.ai")
            stepView(7, "Find 'Cookie' header - copy the whole value")
            stepView(8, "Find 'X-CSRF-Token' header - copy that too")
        }
        .font(.caption)
    }
    
    private func stepView(_ num: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(num).")
                .bold()
                .foregroundStyle(.blue)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

/// WKWebView wrapper for capturing Outlier cookies
struct OutlierWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    var onCookiesCaptured: ((String, String) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        
        // Add script to intercept XHR/fetch and capture CSRF token
        let csrfCaptureScript = WKUserScript(source: """
            (function() {
                window.__capturedCSRF__ = '';
                
                // Intercept XMLHttpRequest
                var origOpen = XMLHttpRequest.prototype.open;
                var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
                
                XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
                    if (name.toLowerCase() === 'x-csrf-token' && value) {
                        window.__capturedCSRF__ = value;
                        console.log('[CSRF Captured from XHR]', value.substring(0, 20) + '...');
                    }
                    return origSetHeader.apply(this, arguments);
                };
                
                // Intercept fetch
                var origFetch = window.fetch;
                window.fetch = function(url, options) {
                    if (options && options.headers) {
                        var headers = options.headers;
                        if (headers instanceof Headers) {
                            var csrf = headers.get('X-CSRF-Token') || headers.get('x-csrf-token');
                            if (csrf) {
                                window.__capturedCSRF__ = csrf;
                                console.log('[CSRF Captured from fetch]', csrf.substring(0, 20) + '...');
                            }
                        } else if (typeof headers === 'object') {
                            var csrf = headers['X-CSRF-Token'] || headers['x-csrf-token'];
                            if (csrf) {
                                window.__capturedCSRF__ = csrf;
                                console.log('[CSRF Captured from fetch]', csrf.substring(0, 20) + '...');
                            }
                        }
                    }
                    return origFetch.apply(this, arguments);
                };
                
                console.log('[OutlierLoginView] CSRF interceptor installed');
            })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        
        config.userContentController.addUserScript(csrfCaptureScript)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        if let url = URL(string: "https://app.outlier.ai/en/expert/login") {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OutlierWebView
        private var hasCheckedCookies = false
        
        init(_ parent: OutlierWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
            
            if let url = webView.url?.absoluteString {
                if !url.contains("/login") && url.contains("outlier.ai") {
                    startCookieCheck(webView: webView)
                }
            }
        }
        
        private func startCookieCheck(webView: WKWebView) {
            extractCredentials(from: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.extractCredentials(from: webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.extractCredentials(from: webView)
            }
        }
        
        private func extractCredentials(from webView: WKWebView) {
            guard !hasCheckedCookies else { return }
            
            let dataStore = webView.configuration.websiteDataStore
            dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                
                let outlierCookies = cookies.filter { $0.domain.contains("outlier.ai") }
                let cookieString = outlierCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                
                guard cookieString.contains("_jwt=") else { return }
                
                // More comprehensive CSRF extraction - check multiple sources
                // First priority: check our intercepted value from XHR/fetch
                webView.evaluateJavaScript("""
                    (function() {
                        // FIRST: Check our intercepted value (most reliable)
                        if (window.__capturedCSRF__ && window.__capturedCSRF__.length > 10) {
                            return window.__capturedCSRF__;
                        }
                        
                        // Check meta tags
                        var meta = document.querySelector('meta[name="csrf-token"]');
                        if (meta && meta.getAttribute('content')) return meta.getAttribute('content');
                        
                        // Check hidden inputs
                        var input = document.querySelector('input[name="_csrf"]');
                        if (input && input.value) return input.value;
                        
                        // Check window globals (React apps often store here)
                        if (window.__CSRF_TOKEN__) return window.__CSRF_TOKEN__;
                        if (window.csrfToken) return window.csrfToken;
                        if (window.__NEXT_DATA__ && window.__NEXT_DATA__.props && window.__NEXT_DATA__.props.csrfToken) {
                            return window.__NEXT_DATA__.props.csrfToken;
                        }
                        
                        // Check localStorage
                        try {
                            var lsToken = localStorage.getItem('csrf_token') || localStorage.getItem('csrfToken') || localStorage.getItem('_csrf');
                            if (lsToken) return lsToken;
                        } catch(e) {}
                        
                        // Check sessionStorage
                        try {
                            var ssToken = sessionStorage.getItem('csrf_token') || sessionStorage.getItem('csrfToken') || sessionStorage.getItem('_csrf');
                            if (ssToken) return ssToken;
                        } catch(e) {}
                        
                        // Check for Redux/state stores
                        if (window.__REDUX_STATE__ && window.__REDUX_STATE__.csrf) return window.__REDUX_STATE__.csrf;
                        
                        // Check cookies as last resort
                        var cookies = document.cookie.split(';');
                        for (var i = 0; i < cookies.length; i++) {
                            var c = cookies[i].trim();
                            var name = c.split('=')[0].toLowerCase();
                            if (name.includes('csrf') || name.includes('xsrf')) {
                                return c.split('=')[1];
                            }
                        }
                        
                        // Try to find it in any script tags (embedded JSON)
                        var scripts = document.querySelectorAll('script');
                        for (var i = 0; i < scripts.length; i++) {
                            var text = scripts[i].textContent || '';
                            var match = text.match(/["']?csrf["']?\\s*[:=]\\s*["']([^"']+)["']/i);
                            if (match) return match[1];
                        }
                        
                        return '';
                    })()
                """) { [weak self] result, error in
                    guard let self = self else { return }
                    
                    var csrf = (result as? String) ?? ""
                    
                    if csrf.isEmpty {
                        for cookie in outlierCookies {
                            let name = cookie.name.lowercased()
                            if name.contains("csrf") || name.contains("xsrf") {
                                csrf = cookie.value
                                break
                            }
                        }
                    }
                    
                    print("[OutlierLoginView] Cookie string length: \(cookieString.count)")
                    print("[OutlierLoginView] Has _jwt: \(cookieString.contains("_jwt="))")
                    print("[OutlierLoginView] CSRF token length: \(csrf.count)")
                    print("[OutlierLoginView] CSRF preview: \(csrf.prefix(30))...")
                    
                    // Only mark as checked if we have both cookie AND csrf
                    if !csrf.isEmpty {
                        self.hasCheckedCookies = true
                        
                        DispatchQueue.main.async {
                            self.parent.onCookiesCaptured?(cookieString, csrf)
                        }
                    } else {
                        print("[OutlierLoginView] ⚠️ CSRF empty, will retry...")
                        // Retry after a delay - user might need to trigger an API call
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.extractCredentials(from: webView)
                        }
                    }
                }
            }
        }
    }
}

#else
// macOS version - manual entry only
struct OutlierLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manualCookie = ""
    @State private var manualCsrf = ""
    var onLogin: ((String, String) -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Login to Outlier")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Cookie String")
                    .font(.headline)
                TextEditor(text: $manualCookie)
                    .frame(height: 80)
                    .font(.system(.caption, design: .monospaced))
                    .border(Color.gray.opacity(0.3))
                Text("Must contain _jwt=...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("X-CSRF-Token")
                    .font(.headline)
                TextField("Paste CSRF token", text: $manualCsrf)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    onLogin?(manualCookie, manualCsrf)
                    dismiss()
                }
                .disabled(manualCookie.isEmpty || !manualCookie.contains("_jwt="))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}
#endif

#Preview {
    OutlierLoginView()
}
