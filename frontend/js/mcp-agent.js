// MCP Agent - Model Context Protocol対応AIエージェントクラス
class MCPAgent {
    constructor(config) {
        this.id = config.id;
        this.name = config.name;
        this.description = config.description;
        this.avatar = config.avatar;
        this.capabilities = config.capabilities || [];
        this.isActive = false;
        this.conversationHistory = [];
        this.context = {
            messages: [],
            metadata: {},
            tools: [],
            resources: []
        };
        this.systemPrompt = config.systemPrompt || this.getDefaultSystemPrompt();
        this.temperature = config.temperature || 0.7;
        this.maxTokens = config.maxTokens || 2000;
        this.model = config.model || 'gpt-4';
    }

    // デフォルトシステムプロンプト
    getDefaultSystemPrompt() {
        const prompts = {
            'default': 'あなたは親切で役立つAIアシスタントです。ユーザーの質問に丁寧に答えてください。',
            'technical': 'あなたは技術的な質問に特化したエキスパートです。プログラミング、システム設計、デバッグなどの技術的な問題を解決することが得意です。',
            'creative': 'あなたは創造的で独創的なアイデアを提供するクリエイターです。文章作成、ブレインストーミング、デザインの提案などが得意です。',
            'analytical': 'あなたは論理的で分析的な思考を行うアナリストです。データ分析、調査、計画立案などが得意です。'
        };
        return prompts[this.id] || prompts.default;
    }

    // エージェント有効化
    activate() {
        this.isActive = true;
        this.emit('activated', { agent: this });
    }

    // エージェント無効化
    deactivate() {
        this.isActive = false;
        this.emit('deactivated', { agent: this });
    }

    // メッセージ送信
    async sendMessage(content, options = {}) {
        if (!this.isActive) {
            throw new Error('Agent is not active');
        }

        // ユーザーメッセージをコンテキストに追加
        const userMessage = {
            role: 'user',
            content: content,
            timestamp: new Date().toISOString(),
            metadata: options.metadata || {}
        };

        this.addToContext(userMessage);

        // API呼び出し用のメッセージ配列構築
        const messages = this.buildMessageHistory();

        try {
            this.emit('thinking', { agent: this });

            // API呼び出し
            const response = await apiClient.sendChat(messages, {
                agentId: this.id,
                model: this.model,
                temperature: this.temperature,
                max_tokens: this.maxTokens,
                ...options
            });

            if (response.success) {
                // アシスタントメッセージをコンテキストに追加
                const assistantMessage = {
                    role: 'assistant',
                    content: response.response,
                    timestamp: new Date().toISOString(),
                    metadata: {
                        usage: response.usage,
                        agentId: this.id
                    }
                };

                this.addToContext(assistantMessage);

                this.emit('response', {
                    agent: this,
                    message: assistantMessage,
                    usage: response.usage
                });

                return assistantMessage;
            } else {
                throw new Error(response.error || 'Failed to get response');
            }
        } catch (error) {
            this.emit('error', { agent: this, error });
            throw error;
        }
    }

    // コンテキストにメッセージ追加
    addToContext(message) {
        this.context.messages.push(message);
        this.conversationHistory.push(message);

        // コンテキスト長制限（最新の50メッセージを保持）
        if (this.context.messages.length > 50) {
            this.context.messages = this.context.messages.slice(-50);
        }
    }

    // API呼び出し用メッセージ履歴構築
    buildMessageHistory() {
        const messages = [
            {
                role: 'system',
                content: this.systemPrompt
            }
        ];

        // 最新の10メッセージを含める
        const recentMessages = this.context.messages.slice(-10);
        for (const msg of recentMessages) {
            messages.push({
                role: msg.role,
                content: msg.content
            });
        }

        return messages;
    }

    // ツール追加（MCP拡張）
    addTool(tool) {
        this.context.tools.push(tool);
        this.emit('tool-added', { agent: this, tool });
    }

    // リソース追加（MCP拡張）
    addResource(resource) {
        this.context.resources.push(resource);
        this.emit('resource-added', { agent: this, resource });
    }

    // メタデータ更新
    updateMetadata(key, value) {
        this.context.metadata[key] = value;
        this.emit('metadata-updated', { agent: this, key, value });
    }

    // 会話履歴クリア
    clearHistory() {
        this.context.messages = [];
        this.conversationHistory = [];
        this.emit('history-cleared', { agent: this });
    }

    // エージェント設定更新
    updateConfig(config) {
        if (config.systemPrompt) this.systemPrompt = config.systemPrompt;
        if (config.temperature !== undefined) this.temperature = config.temperature;
        if (config.maxTokens) this.maxTokens = config.maxTokens;
        if (config.model) this.model = config.model;
        
        this.emit('config-updated', { agent: this, config });
    }

    // コンテキスト要約（長い会話の場合）
    async summarizeContext() {
        if (this.context.messages.length < 20) {
            return;
        }

        try {
            const messages = [
                {
                    role: 'system',
                    content: '以下の会話履歴を簡潔に要約してください。重要なポイントと結論を含めてください。'
                },
                {
                    role: 'user',
                    content: JSON.stringify(this.context.messages.slice(0, -10))
                }
            ];

            const response = await apiClient.sendChat(messages, {
                agentId: 'summarizer',
                temperature: 0.3,
                max_tokens: 500
            });

            if (response.success) {
                // 要約をメタデータに保存
                this.updateMetadata('summary', response.response);
                
                // 古いメッセージを削除（要約で置き換え）
                this.context.messages = [
                    {
                        role: 'system',
                        content: `Previous conversation summary: ${response.response}`
                    },
                    ...this.context.messages.slice(-10)
                ];
            }
        } catch (error) {
            console.warn('Failed to summarize context:', error);
        }
    }

    // イベント発火
    emit(event, data) {
        window.dispatchEvent(new CustomEvent(`mcp-agent-${event}`, {
            detail: data
        }));
    }

    // JSON出力
    toJSON() {
        return {
            id: this.id,
            name: this.name,
            description: this.description,
            avatar: this.avatar,
            capabilities: this.capabilities,
            isActive: this.isActive,
            conversationHistory: this.conversationHistory,
            context: this.context,
            systemPrompt: this.systemPrompt,
            temperature: this.temperature,
            maxTokens: this.maxTokens,
            model: this.model
        };
    }

    // JSON復元
    static fromJSON(data) {
        const agent = new MCPAgent(data);
        agent.isActive = data.isActive;
        agent.conversationHistory = data.conversationHistory || [];
        agent.context = data.context || { messages: [], metadata: {}, tools: [], resources: [] };
        return agent;
    }
}

// MCPエージェントマネージャー
class MCPAgentManager {
    constructor() {
        this.agents = new Map();
        this.activeAgents = new Set();
        this.currentConversation = [];
    }

    // エージェント追加
    addAgent(config) {
        const agent = new MCPAgent(config);
        this.agents.set(agent.id, agent);
        
        // イベントリスナー設定
        this.setupAgentEventListeners(agent);
        
        return agent;
    }

    // エージェント削除
    removeAgent(agentId) {
        const agent = this.agents.get(agentId);
        if (agent) {
            agent.deactivate();
            this.agents.delete(agentId);
            this.activeAgents.delete(agentId);
        }
    }

    // エージェント取得
    getAgent(agentId) {
        return this.agents.get(agentId);
    }

    // 全エージェント取得
    getAllAgents() {
        return Array.from(this.agents.values());
    }

    // アクティブエージェント取得
    getActiveAgents() {
        return Array.from(this.activeAgents).map(id => this.agents.get(id));
    }

    // エージェント有効化
    activateAgent(agentId) {
        const agent = this.agents.get(agentId);
        if (agent) {
            agent.activate();
            this.activeAgents.add(agentId);
        }
    }

    // エージェント無効化
    deactivateAgent(agentId) {
        const agent = this.agents.get(agentId);
        if (agent) {
            agent.deactivate();
            this.activeAgents.delete(agentId);
        }
    }

    // 複数エージェントに同時送信
    async broadcastMessage(content, options = {}) {
        const activeAgents = this.getActiveAgents();
        const promises = activeAgents.map(agent => 
            agent.sendMessage(content, options).catch(error => ({
                agent: agent.id,
                error: error.message
            }))
        );

        const results = await Promise.allSettled(promises);
        return results;
    }

    // エージェントイベントリスナー設定
    setupAgentEventListeners(agent) {
        const events = ['activated', 'deactivated', 'response', 'thinking', 'error'];
        
        events.forEach(event => {
            window.addEventListener(`mcp-agent-${event}`, (e) => {
                if (e.detail.agent.id === agent.id) {
                    this.handleAgentEvent(event, e.detail);
                }
            });
        });
    }

    // エージェントイベントハンドリング
    handleAgentEvent(event, data) {
        switch (event) {
            case 'response':
                this.currentConversation.push({
                    agentId: data.agent.id,
                    message: data.message,
                    timestamp: new Date().toISOString()
                });
                break;
                
            case 'error':
                console.error(`Agent ${data.agent.id} error:`, data.error);
                break;
        }

        // カスタムイベントを再発火
        window.dispatchEvent(new CustomEvent(`agent-manager-${event}`, {
            detail: data
        }));
    }

    // 会話履歴保存
    saveConversation() {
        const data = {
            conversation: this.currentConversation,
            agents: Object.fromEntries(
                Array.from(this.agents.entries()).map(([id, agent]) => [id, agent.toJSON()])
            ),
            timestamp: new Date().toISOString()
        };

        localStorage.setItem('mcp-conversation', JSON.stringify(data));
        return data;
    }

    // 会話履歴読み込み
    loadConversation() {
        const data = localStorage.getItem('mcp-conversation');
        if (data) {
            const parsed = JSON.parse(data);
            this.currentConversation = parsed.conversation || [];
            
            // エージェント復元
            for (const [id, agentData] of Object.entries(parsed.agents || {})) {
                const agent = MCPAgent.fromJSON(agentData);
                this.agents.set(id, agent);
                this.setupAgentEventListeners(agent);
                
                if (agent.isActive) {
                    this.activeAgents.add(id);
                }
            }
            
            return parsed;
        }
        return null;
    }
}

// エクスポート
window.MCPAgent = MCPAgent;
window.MCPAgentManager = MCPAgentManager;