// MCP Agent Class - Gemini対応版
class MCPAgent {
    constructor(id, name, description, capabilities = [], config = {}) {
        this.id = id;
        this.name = name;
        this.description = description;
        this.capabilities = capabilities;
        this.config = {
            model: 'gemini-pro',
            provider: 'Google Gemini',
            temperature: 0.7,
            maxTokens: 2048,
            ...config
        };
        
        this.conversationHistory = [];
        this.systemPrompt = this.generateSystemPrompt();
        this.performance = {
            totalRequests: 0,
            averageResponseTime: 0,
            totalTokens: 0,
            successRate: 100
        };
    }

    // システムプロンプト生成
    generateSystemPrompt() {
        const basePrompt = `あなたは${this.name}です。${this.description}`;
        
        const capabilityPrompts = {
            'technical': 'プログラミング、システム設計、デバッグに特化して回答してください。コード例や具体的な解決策を提供してください。',
            'creative': '創造的で独創的なアイデアを提供してください。想像力豊かで革新的な提案をしてください。',
            'analytical': 'データに基づいた客観的な分析を提供してください。論理的で構造化された回答を心がけてください。',
            'japanese': '自然で丁寧な日本語で回答してください。日本の文化や習慣を考慮したコミュニケーションを心がけてください。',
            'general': 'ユーザーの質問に適切で有用な回答を提供してください。'
        };

        let specificPrompt = '';
        for (const capability of this.capabilities) {
            if (capabilityPrompts[capability]) {
                specificPrompt += capabilityPrompts[capability] + ' ';
            }
        }

        return `${basePrompt} ${specificPrompt}`.trim();
    }

    // メッセージ送信
    async sendMessage(message, options = {}) {
        const startTime = Date.now();
        
        try {
            // 会話履歴に追加
            this.conversationHistory.push({
                role: 'user',
                content: message,
                timestamp: new Date().toISOString()
            });

            // APIリクエスト用メッセージ配列作成
            const messages = [
                { role: 'system', content: this.systemPrompt },
                ...this.conversationHistory.slice(-10) // 最新10件のみ保持
            ];

            // Gemini API呼び出し
            const response = await window.apiClient.sendMessage(messages, {
                agentId: this.id,
                temperature: options.temperature || this.config.temperature,
                maxTokens: options.maxTokens || this.config.maxTokens,
                ...options
            });

            // レスポンスを会話履歴に追加
            this.conversationHistory.push({
                role: 'assistant',
                content: response.content,
                timestamp: new Date().toISOString(),
                usage: response.usage,
                finishReason: response.finishReason
            });

            // パフォーマンス統計更新
            this.updatePerformanceStats(Date.now() - startTime, response.usage, true);

            return {
                success: true,
                content: response.content,
                usage: response.usage,
                finishReason: response.finishReason,
                responseTime: Date.now() - startTime,
                agentId: this.id,
                provider: this.config.provider,
                model: this.config.model
            };

        } catch (error) {
            console.error(`Agent ${this.id} Error:`, error);
            
            // エラーを会話履歴に記録
            this.conversationHistory.push({
                role: 'error',
                content: error.message,
                timestamp: new Date().toISOString()
            });

            // パフォーマンス統計更新(失敗)
            this.updatePerformanceStats(Date.now() - startTime, null, false);

            return {
                success: false,
                error: window.apiClient.handleGeminiError(error),
                responseTime: Date.now() - startTime,
                agentId: this.id
            };
        }
    }

    // パフォーマンス統計更新
    updatePerformanceStats(responseTime, usage, success) {
        this.performance.totalRequests++;
        
        // 平均レスポンス時間更新
        this.performance.averageResponseTime = 
            ((this.performance.averageResponseTime * (this.performance.totalRequests - 1)) + responseTime) / 
            this.performance.totalRequests;

        // トークン使用量更新
        if (usage && usage.totalTokens) {
            this.performance.totalTokens += usage.totalTokens;
        }

        // 成功率更新
        const successfulRequests = Math.round(this.performance.successRate * (this.performance.totalRequests - 1) / 100);
        const newSuccessfulRequests = successfulRequests + (success ? 1 : 0);
        this.performance.successRate = Math.round((newSuccessfulRequests / this.performance.totalRequests) * 100);
    }

    // 会話リセット
    clearHistory() {
        this.conversationHistory = [];
        console.log(`Agent ${this.id}: 会話履歴をリセットしました`);
    }

    // エージェント設定更新
    updateConfig(newConfig) {
        this.config = { ...this.config, ...newConfig };
        console.log(`Agent ${this.id}: 設定を更新しました`, this.config);
    }

    // エージェント情報取得
    getInfo() {
        return {
            id: this.id,
            name: this.name,
            description: this.description,
            capabilities: this.capabilities,
            config: this.config,
            performance: this.performance,
            conversationLength: this.conversationHistory.length,
            systemPrompt: this.systemPrompt
        };
    }

    // 会話履歴エクスポート
    exportHistory() {
        return {
            agentId: this.id,
            agentName: this.name,
            exportTime: new Date().toISOString(),
            totalMessages: this.conversationHistory.length,
            conversations: this.conversationHistory.map(msg => ({
                role: msg.role,
                content: msg.content,
                timestamp: msg.timestamp,
                usage: msg.usage,
                finishReason: msg.finishReason
            })),
            performance: this.performance
        };
    }

    // 会話履歴インポート
    importHistory(historyData) {
        if (historyData.agentId !== this.id) {
            throw new Error('エージェントIDが一致しません');
        }
        
        this.conversationHistory = historyData.conversations || [];
        this.performance = historyData.performance || this.performance;
        
        console.log(`Agent ${this.id}: 会話履歴をインポートしました`);
    }

    // Gemini特有の機能
    
    // コンテンツ安全性評価
    evaluateContentSafety(content) {
        const safetyChecks = [
            { pattern: /[暴力|殺害|攻撃]/g, category: 'violence', severity: 'high' },
            { pattern: /[差別|偏見|ヘイト]/g, category: 'hate', severity: 'medium' },
            { pattern: /[性的|アダルト|わいせつ]/g, category: 'sexual', severity: 'high' },
            { pattern: /[危険|有害|違法]/g, category: 'dangerous', severity: 'medium' }
        ];

        const issues = [];
        for (const check of safetyChecks) {
            const matches = content.match(check.pattern);
            if (matches) {
                issues.push({
                    category: check.category,
                    severity: check.severity,
                    matches: matches.length,
                    examples: matches.slice(0, 3)
                });
            }
        }

        return {
            safe: issues.length === 0,
            score: Math.max(0, 100 - (issues.length * 20)),
            issues: issues,
            recommendation: issues.length > 0 ? 'コンテンツの修正を推奨' : '安全なコンテンツ'
        };
    }

    // レスポンス品質分析
    analyzeResponseQuality(response) {
        if (!response || !response.content) {
            return { score: 0, analysis: 'レスポンスなし' };
        }

        const content = response.content;
        let score = 100;
        const analysis = [];

        // 長さ評価
        if (content.length < 20) {
            score -= 30;
            analysis.push('レスポンスが短すぎます');
        } else if (content.length > 1500) {
            score -= 10;
            analysis.push('レスポンスが長すぎる可能性があります');
        }

        // 構造評価
        const sentences = content.split(/[.!?。！？]/).filter(s => s.trim());
        if (sentences.length < 2) {
            score -= 15;
            analysis.push('文章構造が簡素すぎます');
        }

        // 完了理由評価
        if (response.finishReason === 'MAX_TOKENS') {
            score -= 25;
            analysis.push('トークン制限により途中で切れました');
        } else if (response.finishReason === 'SAFETY') {
            score -= 50;
            analysis.push('安全性フィルターにより制限されました');
        }

        // 有用性評価
        const helpfulIndicators = ['例えば', 'つまり', 'しかし', 'そのため', 'また'];
        const helpfulCount = helpfulIndicators.filter(indicator => 
            content.includes(indicator)
        ).length;
        
        if (helpfulCount === 0) {
            score -= 10;
            analysis.push('説明がやや不十分な可能性があります');
        }

        return {
            score: Math.max(0, score),
            analysis: analysis,
            metrics: {
                length: content.length,
                sentences: sentences.length,
                helpfulIndicators: helpfulCount,
                finishReason: response.finishReason
            },
            recommendation: score >= 80 ? '高品質なレスポンス' : 
                           score >= 60 ? '良好なレスポンス' : 
                           score >= 40 ? '改善の余地あり' : '品質要改善'
        };
    }

    // 学習・適応機能
    adaptToUserFeedback(feedback, messageIndex = -1) {
        const targetMessage = messageIndex >= 0 ? 
            this.conversationHistory[messageIndex] : 
            this.conversationHistory[this.conversationHistory.length - 1];

        if (!targetMessage || targetMessage.role !== 'assistant') {
            return false;
        }

        // フィードバックに基づく設定調整
        if (feedback.type === 'too_long') {
            this.config.maxTokens = Math.max(512, this.config.maxTokens * 0.8);
        } else if (feedback.type === 'too_short') {
            this.config.maxTokens = Math.min(4096, this.config.maxTokens * 1.2);
        } else if (feedback.type === 'too_creative') {
            this.config.temperature = Math.max(0.1, this.config.temperature - 0.1);
        } else if (feedback.type === 'too_boring') {
            this.config.temperature = Math.min(1.0, this.config.temperature + 0.1);
        }

        // フィードバックを履歴に記録
        targetMessage.feedback = {
            type: feedback.type,
            rating: feedback.rating,
            comment: feedback.comment,
            timestamp: new Date().toISOString()
        };

        console.log(`Agent ${this.id}: フィードバックを適用しました`, feedback);
        return true;
    }

    // Gemini特有のメタデータ取得
    getGeminiMetadata() {
        return {
            model: this.config.model,
            provider: this.config.provider,
            capabilities: window.GeminiUtils.getModelInfo().capabilities,
            safetySettings: window.GeminiUtils.getSafetyInfo(),
            currentConfig: this.config,
            performance: this.performance
        };
    }
}

// MCPエージェントマネージャー
class MCPAgentManager {
    constructor() {
        this.agents = new Map();
        this.activeAgent = null;
        this.loadPredefinedAgents();
    }

    // 定義済みエージェント読み込み
    async loadPredefinedAgents() {
        try {
            const agentsData = await window.apiClient.getAgents();
            
            for (const agentData of agentsData.agents) {
                const agent = new MCPAgent(
                    agentData.id,
                    agentData.name,
                    agentData.description,
                    agentData.capabilities,
                    { model: agentData.model }
                );
                
                this.agents.set(agentData.id, agent);
            }
            
            // デフォルトエージェント設定
            this.activeAgent = this.agents.get('default') || this.agents.values().next().value;
            
            console.log(`MCPエージェントマネージャー: ${this.agents.size}個のエージェントを読み込みました`);
            
        } catch (error) {
            console.error('エージェント読み込みエラー:', error);
            this.createFallbackAgent();
        }
    }

    // フォールバックエージェント作成
    createFallbackAgent() {
        const fallbackAgent = new MCPAgent(
            'fallback',
            'フォールバック アシスタント',
            'サーバー接続時のフォールバック用エージェント',
            ['general']
        );
        
        this.agents.set('fallback', fallbackAgent);
        this.activeAgent = fallbackAgent;
    }

    // エージェント取得
    getAgent(id) {
        return this.agents.get(id);
    }

    // アクティブエージェント設定
    setActiveAgent(id) {
        const agent = this.agents.get(id);
        if (agent) {
            this.activeAgent = agent;
            console.log(`アクティブエージェントを ${agent.name} に設定しました`);
            return true;
        }
        return false;
    }

    // 全エージェント取得
    getAllAgents() {
        return Array.from(this.agents.values());
    }

    // エージェント統計取得
    getAgentStats() {
        const stats = {
            totalAgents: this.agents.size,
            activeAgent: this.activeAgent?.id,
            totalRequests: 0,
            totalTokens: 0,
            averageSuccessRate: 0
        };

        let totalSuccessRate = 0;
        for (const agent of this.agents.values()) {
            stats.totalRequests += agent.performance.totalRequests;
            stats.totalTokens += agent.performance.totalTokens;
            totalSuccessRate += agent.performance.successRate;
        }

        stats.averageSuccessRate = this.agents.size > 0 ? 
            Math.round(totalSuccessRate / this.agents.size) : 0;

        return stats;
    }
}

// グローバルインスタンス作成
window.MCPAgent = MCPAgent;
window.MCPAgentManager = MCPAgentManager;
window.mcpAgentManager = new MCPAgentManager();

console.log('🤖 MCP Agent System (Gemini対応) が初期化されました');