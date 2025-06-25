// API Client - バックエンドとの通信を管理
class APIClient {
    constructor(config = {}) {
        this.baseURL = config.baseURL || 'http://localhost:8080/api';
        this.headers = {
            'Content-Type': 'application/json',
            ...config.headers
        };
        this.token = null;
        this.requestQueue = [];
        this.isProcessing = false;
        this.maxRetries = 3;
        this.retryDelay = 1000;
    }

    // 認証トークン設定
    setAuthToken(token) {
        this.token = token;
        if (token) {
            this.headers['Authorization'] = `Bearer ${token}`;
        } else {
            delete this.headers['Authorization'];
        }
    }

    // APIリクエスト実行
    async request(endpoint, options = {}) {
        const url = `${this.baseURL}${endpoint}`;
        const config = {
            ...options,
            headers: {
                ...this.headers,
                ...options.headers
            }
        };

        // リトライロジック
        let lastError;
        for (let i = 0; i < this.maxRetries; i++) {
            try {
                const response = await fetch(url, config);
                
                // レート制限チェック
                if (response.status === 429) {
                    const retryAfter = response.headers.get('Retry-After') || 60;
                    throw new Error(`Rate limit exceeded. Retry after ${retryAfter} seconds.`);
                }

                if (!response.ok) {
                    const error = await response.json();
                    throw new Error(error.error || `HTTP ${response.status}`);
                }

                return await response.json();
            } catch (error) {
                lastError = error;
                
                // ネットワークエラーの場合はリトライ
                if (error.name === 'TypeError' && error.message.includes('fetch')) {
                    await this.delay(this.retryDelay * Math.pow(2, i));
                    continue;
                }
                
                throw error;
            }
        }

        throw lastError;
    }

    // 遅延ユーティリティ
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // エージェント一覧取得
    async getAgents() {
        return this.request('/agents');
    }

    // チャット送信
    async sendChat(messages, options = {}) {
        return this.request('/chat', {
            method: 'POST',
            body: JSON.stringify({
                messages,
                ...options
            })
        });
    }

    // ヘルスチェック
    async healthCheck() {
        return this.request('/health');
    }

    // ログイン
    async login(username, password) {
        const response = await this.request('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ username, password })
        });
        
        if (response.success && response.token) {
            this.setAuthToken(response.token);
        }
        
        return response;
    }

    // バッチリクエスト
    async batchRequest(requests) {
        const results = [];
        
        for (const req of requests) {
            try {
                const result = await this.request(req.endpoint, req.options);
                results.push({ success: true, data: result });
            } catch (error) {
                results.push({ success: false, error: error.message });
            }
        }
        
        return results;
    }

    // WebSocket接続（将来の拡張用）
    connectWebSocket(endpoint = '/ws') {
        const wsURL = this.baseURL.replace(/^http/, 'ws') + endpoint;
        
        this.ws = new WebSocket(wsURL);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
            if (this.token) {
                this.ws.send(JSON.stringify({
                    type: 'auth',
                    token: this.token
                }));
            }
        };
        
        this.ws.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                this.handleWebSocketMessage(data);
            } catch (error) {
                console.error('WebSocket message parse error:', error);
            }
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
        
        this.ws.onclose = () => {
            console.log('WebSocket disconnected');
            // 再接続ロジック
            setTimeout(() => this.connectWebSocket(endpoint), 5000);
        };
        
        return this.ws;
    }

    // WebSocketメッセージハンドラー
    handleWebSocketMessage(data) {
        // カスタムイベントを発火
        window.dispatchEvent(new CustomEvent('ws-message', { detail: data }));
    }

    // エラーハンドリング
    handleError(error) {
        console.error('API Error:', error);
        
        // エラー通知
        window.dispatchEvent(new CustomEvent('api-error', {
            detail: {
                message: error.message,
                timestamp: new Date().toISOString()
            }
        }));
        
        return {
            success: false,
            error: error.message
        };
    }
}

// シングルトンインスタンス
const apiClient = new APIClient();

// エクスポート
window.APIClient = APIClient;
window.apiClient = apiClient;