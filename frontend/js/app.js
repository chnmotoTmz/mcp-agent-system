// メインアプリケーション - UIとロジックの統合
class MCPAgentApp {
    constructor() {
        this.agentManager = new MCPAgentManager();
        this.settings = this.loadSettings();
        this.isInitialized = false;
        this.typingIndicators = new Map();
        
        // DOM要素参照
        this.elements = {};
        
        // 初期化
        this.init();
    }

    // アプリケーション初期化
    async init() {
        try {
            // DOM要素取得
            this.initElements();
            
            // イベントリスナー設定
            this.setupEventListeners();
            
            // 設定適用
            this.applySettings();
            
            // エージェント読み込み
            await this.loadAgents();
            
            // 会話履歴復元
            this.loadConversationHistory();
            
            // APIヘルスチェック
            await this.checkAPIHealth();
            
            this.isInitialized = true;
            console.log('MCP Agent App initialized successfully');
            
        } catch (error) {
            console.error('Failed to initialize app:', error);
            this.showNotification('アプリケーションの初期化に失敗しました', 'error');
        }
    }

    // DOM要素初期化
    initElements() {
        this.elements = {
            // サイドバー
            agentsGrid: document.getElementById('agentsGrid'),
            activeAgentsList: document.getElementById('activeAgentsList'),
            newChatBtn: document.getElementById('newChatBtn'),
            
            // メインエリア
            chatContainer: document.getElementById('chatContainer'),
            chatTitle: document.getElementById('chatTitle'),
            chatStatus: document.getElementById('chatStatus'),
            
            // 入力エリア
            messageInput: document.getElementById('messageInput'),
            sendBtn: document.getElementById('sendBtn'),
            selectedAgents: document.getElementById('selectedAgents'),
            temperatureSlider: document.getElementById('temperatureSlider'),
            temperatureValue: document.getElementById('temperatureValue'),
            
            // アクションボタン
            exportBtn: document.getElementById('exportBtn'),
            clearBtn: document.getElementById('clearBtn'),
            settingsBtn: document.getElementById('settingsBtn'),
            
            // 設定モーダル
            settingsModal: document.getElementById('settingsModal'),
            closeSettingsBtn: document.getElementById('closeSettingsBtn'),
            saveSettingsBtn: document.getElementById('saveSettingsBtn'),
            cancelSettingsBtn: document.getElementById('cancelSettingsBtn'),
            
            // 設定フィールド
            apiEndpoint: document.getElementById('apiEndpoint'),
            apiKey: document.getElementById('apiKey'),
            modelSelect: document.getElementById('modelSelect'),
            maxTokens: document.getElementById('maxTokens'),
            darkMode: document.getElementById('darkMode'),
            showTimestamps: document.getElementById('showTimestamps')
        };
    }

    // イベントリスナー設定
    setupEventListeners() {
        // メッセージ送信
        this.elements.sendBtn.addEventListener('click', () => this.sendMessage());
        
        // Enter キー送信
        this.elements.messageInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                this.sendMessage();
            }
        });

        // 入力フィールドの変化を監視
        this.elements.messageInput.addEventListener('input', () => {
            this.updateSendButton();
            this.autoResize();
        });

        // 温度スライダー
        this.elements.temperatureSlider.addEventListener('input', (e) => {
            this.elements.temperatureValue.textContent = e.target.value;
        });

        // ボタンイベント
        this.elements.newChatBtn.addEventListener('click', () => this.startNewChat());
        this.elements.exportBtn.addEventListener('click', () => this.exportConversation());
        this.elements.clearBtn.addEventListener('click', () => this.clearConversation());
        this.elements.settingsBtn.addEventListener('click', () => this.openSettings());

        // 設定モーダル
        this.elements.closeSettingsBtn.addEventListener('click', () => this.closeSettings());
        this.elements.saveSettingsBtn.addEventListener('click', () => this.saveSettings());
        this.elements.cancelSettingsBtn.addEventListener('click', () => this.closeSettings());

        // エージェントマネージャーイベント
        this.setupAgentManagerEvents();

        // API エラーイベント
        window.addEventListener('api-error', (e) => {
            this.showNotification(`API Error: ${e.detail.message}`, 'error');
        });

        // ウィンドウリサイズ
        window.addEventListener('resize', () => this.handleResize());
    }

    // エージェントマネージャーイベント設定
    setupAgentManagerEvents() {
        // エージェント応答
        window.addEventListener('agent-manager-response', (e) => {
            this.handleAgentResponse(e.detail);
        });

        // エージェント思考中
        window.addEventListener('agent-manager-thinking', (e) => {
            this.showTypingIndicator(e.detail.agent);
        });

        // エージェントエラー
        window.addEventListener('agent-manager-error', (e) => {
            this.hideTypingIndicator(e.detail.agent);
            this.showNotification(`${e.detail.agent.name}: ${e.detail.error}`, 'error');
        });
    }

    // エージェント読み込み
    async loadAgents() {
        try {
            const response = await apiClient.getAgents();
            
            if (response.agents) {
                // エージェントカード生成
                this.renderAgents(response.agents);
                
                // エージェントマネージャーに追加
                response.agents.forEach(agentData => {
                    this.agentManager.addAgent(agentData);
                });
            }
        } catch (error) {
            console.error('Failed to load agents:', error);
            this.showNotification('エージェントの読み込みに失敗しました', 'error');
        }
    }

    // エージェント表示
    renderAgents(agents) {
        this.elements.agentsGrid.innerHTML = '';
        
        agents.forEach(agent => {
            const card = this.createAgentCard(agent);
            this.elements.agentsGrid.appendChild(card);
        });
    }

    // エージェントカード作成
    createAgentCard(agent) {
        const card = document.createElement('div');
        card.className = 'agent-card';
        card.dataset.agentId = agent.id;
        
        card.innerHTML = `
            <div class="agent-avatar">${this.getAgentEmoji(agent.id)}</div>
            <div class="agent-name">${agent.name}</div>
            <div class="agent-description">${agent.description}</div>
        `;
        
        card.addEventListener('click', () => this.toggleAgent(agent.id));
        
        return card;
    }

    // エージェント絵文字取得
    getAgentEmoji(agentId) {
        const emojis = {
            'default': '🤖',
            'technical': '👨‍💻',
            'creative': '🎨',
            'analytical': '📊'
        };
        return emojis[agentId] || '🤖';
    }

    // エージェント切り替え
    toggleAgent(agentId) {
        const card = document.querySelector(`[data-agent-id="${agentId}"]`);
        const agent = this.agentManager.getAgent(agentId);
        
        if (!agent) return;
        
        if (agent.isActive) {
            this.agentManager.deactivateAgent(agentId);
            card.classList.remove('selected');
        } else {
            this.agentManager.activateAgent(agentId);
            card.classList.add('selected');
        }
        
        this.updateActiveAgentsList();
        this.updateSelectedAgentsDisplay();
    }

    // アクティブエージェントリスト更新
    updateActiveAgentsList() {
        const activeAgents = this.agentManager.getActiveAgents();
        
        this.elements.activeAgentsList.innerHTML = '';
        
        activeAgents.forEach(agent => {
            const item = document.createElement('div');
            item.className = 'active-agent-item';
            item.innerHTML = `
                <span class="status-dot"></span>
                <span>${agent.name}</span>
            `;
            this.elements.activeAgentsList.appendChild(item);
        });
        
        // チャット状態更新
        if (activeAgents.length > 0) {
            this.elements.chatStatus.textContent = `${activeAgents.length}体のエージェントがアクティブ`;
        } else {
            this.elements.chatStatus.textContent = 'エージェントを選択してください';
        }
    }

    // 選択エージェント表示更新
    updateSelectedAgentsDisplay() {
        const activeAgents = this.agentManager.getActiveAgents();
        
        this.elements.selectedAgents.innerHTML = '';
        
        activeAgents.forEach(agent => {
            const chip = document.createElement('div');
            chip.className = 'selected-agent-chip';
            chip.innerHTML = `
                <span>${this.getAgentEmoji(agent.id)}</span>
                <span>${agent.name}</span>
            `;
            this.elements.selectedAgents.appendChild(chip);
        });
    }

    // メッセージ送信
    async sendMessage() {
        const message = this.elements.messageInput.value.trim();
        if (!message) return;
        
        const activeAgents = this.agentManager.getActiveAgents();
        if (activeAgents.length === 0) {
            this.showNotification('エージェントを選択してください', 'warning');
            return;
        }
        
        // ユーザーメッセージ表示
        this.addMessageToChat({
            role: 'user',
            content: message,
            timestamp: new Date().toISOString()
        });
        
        // 入力フィールドクリア
        this.elements.messageInput.value = '';
        this.updateSendButton();
        this.autoResize();
        
        // ウェルカムメッセージ非表示
        this.hideWelcomeMessage();
        
        // エージェントに送信
        const temperature = parseFloat(this.elements.temperatureSlider.value);
        
        try {
            await this.agentManager.broadcastMessage(message, {
                temperature: temperature,
                metadata: {
                    userInput: true,
                    timestamp: new Date().toISOString()
                }
            });
        } catch (error) {
            console.error('Failed to send message:', error);
            this.showNotification('メッセージの送信に失敗しました', 'error');
        }
    }

    // エージェント応答処理
    handleAgentResponse(data) {
        this.hideTypingIndicator(data.agent);
        this.addMessageToChat({
            role: 'assistant',
            content: data.message.content,
            timestamp: data.message.timestamp,
            agentId: data.agent.id,
            agentName: data.agent.name
        });
    }

    // チャットにメッセージ追加
    addMessageToChat(message) {
        const messageElement = this.createMessageElement(message);
        
        // ウェルカムメッセージがある場合は削除
        this.hideWelcomeMessage();
        
        this.elements.chatContainer.appendChild(messageElement);
        this.scrollToBottom();
    }

    // メッセージ要素作成
    createMessageElement(message) {
        const messageDiv = document.createElement('div');
        messageDiv.className = 'message';
        
        const isUser = message.role === 'user';
        const agentInfo = isUser ? 
            { name: 'あなた', emoji: '👤' } : 
            { 
                name: message.agentName || 'AI', 
                emoji: this.getAgentEmoji(message.agentId || 'default') 
            };
        
        const timestamp = this.settings.showTimestamps ? 
            this.formatTimestamp(message.timestamp) : '';
        
        messageDiv.innerHTML = `
            <div class="message-avatar">${agentInfo.emoji}</div>
            <div class="message-content">
                <div class="message-header">
                    <span class="message-author">${agentInfo.name}</span>
                    ${timestamp ? `<span class="message-time">${timestamp}</span>` : ''}
                </div>
                <div class="message-text">${this.formatMessageContent(message.content)}</div>
            </div>
        `;
        
        return messageDiv;
    }

    // メッセージ内容フォーマット
    formatMessageContent(content) {
        // マークダウン風の簡単なフォーマッティング
        return content
            .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
            .replace(/\*(.*?)\*/g, '<em>$1</em>')
            .replace(/`(.*?)`/g, '<code>$1</code>')
            .replace(/\n/g, '<br>');
    }

    // タイムスタンプフォーマット
    formatTimestamp(timestamp) {
        const date = new Date(timestamp);
        return date.toLocaleTimeString('ja-JP', {
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    // タイピングインジケーター表示
    showTypingIndicator(agent) {
        if (this.typingIndicators.has(agent.id)) return;
        
        const indicator = document.createElement('div');
        indicator.className = 'message typing-message';
        indicator.id = `typing-${agent.id}`;
        
        indicator.innerHTML = `
            <div class="message-avatar">${this.getAgentEmoji(agent.id)}</div>
            <div class="message-content">
                <div class="message-header">
                    <span class="message-author">${agent.name}</span>
                </div>
                <div class="typing-indicator">
                    <span></span>
                    <span></span>
                    <span></span>
                </div>
            </div>
        `;
        
        this.elements.chatContainer.appendChild(indicator);
        this.typingIndicators.set(agent.id, indicator);
        this.scrollToBottom();
    }

    // タイピングインジケーター非表示
    hideTypingIndicator(agent) {
        const indicator = this.typingIndicators.get(agent.id);
        if (indicator) {
            indicator.remove();
            this.typingIndicators.delete(agent.id);
        }
    }

    // ウェルカムメッセージ非表示
    hideWelcomeMessage() {
        const welcomeMsg = this.elements.chatContainer.querySelector('.welcome-message');
        if (welcomeMsg) {
            welcomeMsg.style.display = 'none';
        }
    }

    // 送信ボタン状態更新
    updateSendButton() {
        const hasMessage = this.elements.messageInput.value.trim().length > 0;
        const hasActiveAgents = this.agentManager.getActiveAgents().length > 0;
        
        this.elements.sendBtn.disabled = !hasMessage || !hasActiveAgents;
    }

    // テキストエリア自動リサイズ
    autoResize() {
        const textarea = this.elements.messageInput;
        textarea.style.height = 'auto';
        textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
    }

    // チャット最下部スクロール
    scrollToBottom() {
        this.elements.chatContainer.scrollTop = this.elements.chatContainer.scrollHeight;
    }

    // 新規チャット開始
    startNewChat() {
        // 確認ダイアログ
        if (this.elements.chatContainer.children.length > 1) {
            if (!confirm('現在の会話をクリアして新しいチャットを開始しますか？')) {
                return;
            }
        }
        
        this.clearConversation();
    }

    // 会話クリア
    clearConversation() {
        // チャットコンテナクリア
        this.elements.chatContainer.innerHTML = `
            <div class="welcome-message">
                <h3>AIエージェント会話システムへようこそ</h3>
                <p>左側のパネルからエージェントを選択して会話を開始してください。</p>
            </div>
        `;
        
        // エージェント履歴クリア
        this.agentManager.getAllAgents().forEach(agent => {
            agent.clearHistory();
        });
        
        // 現在の会話クリア
        this.agentManager.currentConversation = [];
        
        this.showNotification('会話をクリアしました', 'success');
    }

    // 会話エクスポート
    exportConversation() {
        const data = this.agentManager.saveConversation();
        
        const blob = new Blob([JSON.stringify(data, null, 2)], {
            type: 'application/json'
        });
        
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `conversation-${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        
        this.showNotification('会話をエクスポートしました', 'success');
    }

    // 設定モーダル開く
    openSettings() {
        this.elements.settingsModal.classList.add('active');
        
        // 現在の設定を表示
        this.elements.apiEndpoint.value = apiClient.baseURL;
        this.elements.modelSelect.value = this.settings.model;
        this.elements.maxTokens.value = this.settings.maxTokens;
        this.elements.darkMode.checked = this.settings.darkMode;
        this.elements.showTimestamps.checked = this.settings.showTimestamps;
    }

    // 設定モーダル閉じる
    closeSettings() {
        this.elements.settingsModal.classList.remove('active');
    }

    // 設定保存
    saveSettings() {
        this.settings = {
            ...this.settings,
            apiEndpoint: this.elements.apiEndpoint.value,
            apiKey: this.elements.apiKey.value,
            model: this.elements.modelSelect.value,
            maxTokens: parseInt(this.elements.maxTokens.value),
            darkMode: this.elements.darkMode.checked,
            showTimestamps: this.elements.showTimestamps.checked
        };
        
        // ローカルストレージに保存
        localStorage.setItem('mcp-settings', JSON.stringify(this.settings));
        
        // 設定適用
        this.applySettings();
        
        // APIクライアント設定更新
        apiClient.baseURL = this.settings.apiEndpoint;
        if (this.settings.apiKey) {
            apiClient.setAuthToken(this.settings.apiKey);
        }
        
        this.closeSettings();
        this.showNotification('設定を保存しました', 'success');
    }

    // 設定読み込み
    loadSettings() {
        const defaultSettings = {
            apiEndpoint: 'http://localhost:8080/api',
            apiKey: '',
            model: 'gpt-4',
            maxTokens: 2000,
            darkMode: true,
            showTimestamps: true
        };
        
        const saved = localStorage.getItem('mcp-settings');
        return saved ? { ...defaultSettings, ...JSON.parse(saved) } : defaultSettings;
    }

    // 設定適用
    applySettings() {
        // ダークモード切り替え
        if (this.settings.darkMode) {
            document.body.classList.remove('light-mode');
        } else {
            document.body.classList.add('light-mode');
        }
    }

    // 会話履歴読み込み
    loadConversationHistory() {
        const saved = this.agentManager.loadConversation();
        if (saved && saved.conversation.length > 0) {
            // UIに履歴を復元
            this.hideWelcomeMessage();
            
            saved.conversation.forEach(item => {
                this.addMessageToChat(item.message);
            });
            
            // アクティブエージェント表示更新
            this.updateActiveAgentsList();
            this.updateSelectedAgentsDisplay();
            
            // カード状態更新
            this.agentManager.getActiveAgents().forEach(agent => {
                const card = document.querySelector(`[data-agent-id="${agent.id}"]`);
                if (card) {
                    card.classList.add('selected');
                }
            });
        }
    }

    // APIヘルスチェック
    async checkAPIHealth() {
        try {
            await apiClient.healthCheck();
            this.elements.chatStatus.textContent = '接続済み';
        } catch (error) {
            this.elements.chatStatus.textContent = 'API接続エラー';
            this.showNotification('APIサーバーに接続できません', 'error');
        }
    }

    // 通知表示
    showNotification(message, type = 'info') {
        const notification = document.createElement('div');
        notification.className = `notification notification-${type}`;
        notification.textContent = message;
        
        document.body.appendChild(notification);
        
        // アニメーション
        setTimeout(() => notification.classList.add('show'), 100);
        
        // 自動削除
        setTimeout(() => {
            notification.classList.remove('show');
            setTimeout(() => notification.remove(), 300);
        }, 3000);
    }

    // ウィンドウリサイズハンドリング
    handleResize() {
        // モバイル対応など
        if (window.innerWidth <= 768) {
            // モバイル用調整
        }
    }
}

// アプリケーション開始
document.addEventListener('DOMContentLoaded', () => {
    window.mcpApp = new MCPAgentApp();
});

// 通知スタイル追加
const notificationStyles = `
.notification {
    position: fixed;
    top: 20px;
    right: 20px;
    padding: 12px 24px;
    border-radius: 8px;
    color: white;
    font-weight: 500;
    transform: translateX(100%);
    transition: transform 0.3s ease;
    z-index: 10000;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
}

.notification.show {
    transform: translateX(0);
}

.notification-info {
    background-color: var(--primary-color);
}

.notification-success {
    background-color: var(--success-color);
}

.notification-warning {
    background-color: var(--warning-color);
}

.notification-error {
    background-color: var(--danger-color);
}
`;

// スタイル挿入
const style = document.createElement('style');
style.textContent = notificationStyles;
document.head.appendChild(style);