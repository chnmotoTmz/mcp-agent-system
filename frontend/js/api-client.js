// MCP Agent API Client - Gemini対応版
class APIClient {
    constructor(baseURL = 'http://localhost:8080/api') {
        this.baseURL = baseURL;
        this.token = localStorage.getItem('auth_token');
        this.provider = 'Google Gemini';
        this.model = 'gemini-pro';
    }

    // 認証ヘッダー取得
    getHeaders() {
        const headers = {
            'Content-Type': 'application/json'
        };
        
        if (this.token) {
            headers['Authorization'] = `Bearer ${this.token}`;
        }
        
        return headers;
    }

    // HTTP リクエスト実行
    async request(endpoint, options = {}) {
        const url = `${this.baseURL}${endpoint}`;
        const config = {
            headers: this.getHeaders(),
            ...options
        };

        try {
            const response = await fetch(url, config);
            
            if (!response.ok) {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.error || `HTTP ${response.status}: ${response.statusText}`);
            }

            return await response.json();
        } catch (error) {
            console.error(`API Request Failed [${endpoint}]:`, error);
            throw error;
        }
    }

    // チャット送信 (Gemini対応)
    async sendMessage(messages, options = {}) {
        const payload = {
            messages: messages,
            agentId: options.agentId || 'default',
            temperature: options.temperature || 0.7,
            max_tokens: options.maxTokens || 2048,
            model: this.model
        };

        const response = await this.request('/chat', {
            method: 'POST',
            body: JSON.stringify(payload)
        });

        // Gemini特有のレスポンス処理
        if (response.success) {
            return {
                content: response.response,
                agentId: response.agentId,
                usage: response.usage,
                finishReason: response.finishReason,
                model: response.model || this.model,
                provider: this.provider,
                timestamp: response.timestamp
            };
        } else {
            throw new Error(response.error || 'Unknown error occurred');
        }
    }

    // エージェント一覧取得
    async getAgents() {
        const response = await this.request('/agents');
        return {
            agents: response.agents || [],
            count: response.count || 0,
            provider: response.provider || this.provider,
            model: response.model || this.model
        };
    }

    // システム状態確認
    async getHealth() {
        const response = await this.request('/health');
        return {
            status: response.status,
            provider: response.provider || this.provider,
            model: response.model || this.model,
            version: response.version,
            uptime: response.uptime,
            timestamp: response.timestamp,
            endpoints: response.endpoints || [],
            features: response.features || []
        };
    }

    // ログイン
    async login(username, password) {
        const response = await this.request('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ username, password })
        });

        if (response.success && response.token) {
            this.token = response.token;
            localStorage.setItem('auth_token', this.token);
            return {
                success: true,
                token: response.token,
                expiresIn: response.expiresIn,
                provider: response.provider || this.provider
            };
        } else {
            throw new Error(response.error || 'Login failed');
        }
    }

    // ログアウト
    logout() {
        this.token = null;
        localStorage.removeItem('auth_token');
    }

    // 認証状態確認
    isAuthenticated() {
        return !!this.token;
    }

    // Gemini特有のエラーハンドリング
    handleGeminiError(error) {
        const errorMessage = error.message || 'Unknown error';
        
        // Gemini API特有のエラーパターン
        if (errorMessage.includes('API_KEY')) {
            return 'Gemini APIキーが無効または設定されていません';
        } else if (errorMessage.includes('QUOTA_EXCEEDED')) {
            return 'Gemini APIの使用量制限に達しました';
        } else if (errorMessage.includes('SAFETY')) {
            return 'コンテンツがGeminiの安全性フィルターに引っかかりました';
        } else if (errorMessage.includes('RECITATION')) {
            return 'Geminiが引用コンテンツを検出しました';
        } else if (errorMessage.includes('BLOCKED_REASON')) {
            return 'リクエストがGeminiによりブロックされました';
        }
        
        return errorMessage;
    }

    // トークン使用量監視
    trackTokenUsage(usage) {
        if (!usage) return;
        
        const tokenData = {
            promptTokens: usage.promptTokens || 0,
            completionTokens: usage.completionTokens || 0,
            totalTokens: usage.totalTokens || 0,
            timestamp: new Date().toISOString(),
            provider: this.provider,
            model: this.model
        };
        
        // ローカルストレージに使用量を記録
        const existingData = JSON.parse(localStorage.getItem('token_usage') || '[]');
        existingData.push(tokenData);
        
        // 最新100件のみ保持
        if (existingData.length > 100) {
            existingData.splice(0, existingData.length - 100);
        }
        
        localStorage.setItem('token_usage', JSON.stringify(existingData));
        
        console.log('Token Usage:', tokenData);
    }

    // 使用量統計取得
    getTokenStats() {
        const data = JSON.parse(localStorage.getItem('token_usage') || '[]');
        
        if (data.length === 0) {
            return {
                totalSessions: 0,
                totalTokens: 0,
                averageTokens: 0,
                provider: this.provider
            };
        }
        
        const totalTokens = data.reduce((sum, session) => sum + (session.totalTokens || 0), 0);
        
        return {
            totalSessions: data.length,
            totalTokens: totalTokens,
            averageTokens: Math.round(totalTokens / data.length),
            provider: this.provider,
            model: this.model,
            lastUsed: data[data.length - 1]?.timestamp
        };
    }

    // 接続テスト
    async testConnection() {
        try {
            const health = await this.getHealth();
            return {
                success: true,
                status: health.status,
                provider: health.provider,
                model: health.model,
                responseTime: Date.now() - startTime
            };
        } catch (error) {
            return {
                success: false,
                error: this.handleGeminiError(error),
                provider: this.provider
            };
        }
    }
}

// APIクライアントインスタンスをエクスポート
window.APIClient = APIClient;

// デフォルトインスタンス作成
window.apiClient = new APIClient();

// Gemini固有のユーティリティ関数
window.GeminiUtils = {
    // Geminiモデル情報
    getModelInfo() {
        return {
            name: 'Gemini Pro',
            provider: 'Google',
            capabilities: [
                'テキスト生成',
                '質問応答',
                'コード生成',
                'クリエイティブライティング',
                '論理的推論',
                '多言語対応'
            ],
            limits: {
                maxInputTokens: 30720,
                maxOutputTokens: 2048,
                rateLimit: '60 requests/minute'
            }
        };
    },

    // 安全性フィルター情報
    getSafetyInfo() {
        return {
            categories: [
                'HARM_CATEGORY_HARASSMENT',
                'HARM_CATEGORY_HATE_SPEECH', 
                'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                'HARM_CATEGORY_DANGEROUS_CONTENT'
            ],
            thresholds: [
                'BLOCK_NONE',
                'BLOCK_ONLY_HIGH',
                'BLOCK_MEDIUM_AND_ABOVE',
                'BLOCK_LOW_AND_ABOVE'
            ]
        };
    },

    // Geminiレスポンス品質評価
    evaluateResponse(response) {
        if (!response || !response.content) {
            return { score: 0, reason: 'Empty response' };
        }

        let score = 100;
        const content = response.content;

        // 長さチェック
        if (content.length < 10) score -= 30;
        if (content.length > 2000) score -= 10;

        // 完了理由チェック
        if (response.finishReason === 'MAX_TOKENS') score -= 20;
        if (response.finishReason === 'SAFETY') score -= 50;
        if (response.finishReason === 'RECITATION') score -= 30;

        // 内容品質の簡易評価
        const sentences = content.split(/[.!?。！？]/).filter(s => s.trim());
        if (sentences.length < 2) score -= 15;

        return {
            score: Math.max(0, score),
            finishReason: response.finishReason,
            tokenEfficiency: response.usage ? 
                (content.length / (response.usage.totalTokens || 1)) * 100 : 0
        };
    }
};

console.log('🚀 Gemini対応APIクライアントが読み込まれました');