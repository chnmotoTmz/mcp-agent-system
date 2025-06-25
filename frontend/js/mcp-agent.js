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
            this.emit('error', {
                agent: this,
                error: error.message
            });
            throw error;
        }
    }

    // コンテキストにメッセージ追加
    addToContext(message) {
        this.context.messages.push(message);
        this.conversationHistory.push(message);
        
        // コンテキストサイズ制限
        if (this.context.messages.length > 50) {
            this.context.messages = this.context.messages.slice(-25);
        }
    }

    // メッセージ履歴構築
    buildMessageHistory() {
        const messages = [
            {
                role: 'system',
                content: this.systemPrompt
            },
            ...this.context.messages
        ];
        
        return messages;
    }

    // イベント発火
    emit(eventName, data) {
        window.dispatchEvent(new CustomEvent(`agent-${eventName}`, {
            detail: data
        }));
    }

    // 履歴クリア
    clearHistory() {
        this.context.messages = [];
        this.conversationHistory = [];
    }

    // エージェント状態取得
    getState() {
        return {
            id: this.id,
            name: this.name,
            isActive: this.isActive,
            contextSize: this.context.messages.length,
            historySize: this.conversationHistory.length
        };
    }

    // コンテキスト保存
    saveContext() {
        return {
            agent: {
                id: this.id,
                name: this.name,
                config: {
                    temperature: this.temperature,
                    maxTokens: this.maxTokens,
                    model: this.model
                }
            },
            context: this.context,
            conversationHistory: this.conversationHistory,
            timestamp: new Date().toISOString()
        };
    }

    // コンテキスト復元
    loadContext(savedContext) {
        if (savedContext.context) {
            this.context = savedContext.context;
        }
        
        if (savedContext.conversationHistory) {
            this.conversationHistory = savedContext.conversationHistory;
        }
        
        if (savedContext.agent && savedContext.agent.config) {
            this.temperature = savedContext.agent.config.temperature || this.temperature;
            this.maxTokens = savedContext.agent.config.maxTokens || this.maxTokens;
            this.model = savedContext.agent.config.model || this.model;
        }
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
    addAgent(agentData) {
        const agent = new MCPAgent(agentData);
        this.agents.set(agent.id, agent);
        
        // イベントリスナー設定
        this.setupAgentEvents(agent);
        
        return agent;
    }

    // エージェントイベント設定
    setupAgentEvents(agent) {
        window.addEventListener(`agent-response`, (e) => {
            if (e.detail.agent.id === agent.id) {
                window.dispatchEvent(new CustomEvent('agent-manager-response', {
                    detail: e.detail
                }));
            }
        });

        window.addEventListener(`agent-thinking`, (e) => {
            if (e.detail.agent.id === agent.id) {
                window.dispatchEvent(new CustomEvent('agent-manager-thinking', {
                    detail: e.detail
                }));
            }
        });

        window.addEventListener(`agent-error`, (e) => {
            if (e.detail.agent.id === agent.id) {
                window.dispatchEvent(new CustomEvent('agent-manager-error', {
                    detail: e.detail
                }));
            }
        });
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

    // ブロードキャストメッセージ
    async broadcastMessage(content, options = {}) {
        const activeAgents = this.getActiveAgents();
        const promises = [];
        
        for (const agent of activeAgents) {
            promises.push(agent.sendMessage(content, options));
        }
        
        try {
            const results = await Promise.allSettled(promises);
            return results;
        } catch (error) {
            console.error('Broadcast message failed:', error);
            throw error;
        }
    }

    // 会話保存
    saveConversation() {
        const data = {
            timestamp: new Date().toISOString(),
            activeAgents: Array.from(this.activeAgents),
            conversation: this.currentConversation,
            agents: {}
        };
        
        // エージェントコンテキスト保存
        for (const agent of this.agents.values()) {
            data.agents[agent.id] = agent.saveContext();
        }
        
        // ローカルストレージに保存
        localStorage.setItem('mcp-conversation', JSON.stringify(data));
        
        return data;
    }

    // 会話復元
    loadConversation() {
        try {
            const saved = localStorage.getItem('mcp-conversation');
            if (!saved) return null;
            
            const data = JSON.parse(saved);
            
            // アクティブエージェント復元
            if (data.activeAgents) {
                this.activeAgents = new Set(data.activeAgents);
                data.activeAgents.forEach(agentId => {
                    const agent = this.agents.get(agentId);
                    if (agent) {
                        agent.isActive = true;
                    }
                });
            }
            
            // エージェントコンテキスト復元
            if (data.agents) {
                for (const [agentId, context] of Object.entries(data.agents)) {
                    const agent = this.agents.get(agentId);
                    if (agent) {
                        agent.loadContext(context);
                    }
                }
            }
            
            // 会話復元
            if (data.conversation) {
                this.currentConversation = data.conversation;
            }
            
            return data;
        } catch (error) {
            console.error('Failed to load conversation:', error);
            return null;
        }
    }
}

// エクスポート
window.MCPAgent = MCPAgent;
window.MCPAgentManager = MCPAgentManager;