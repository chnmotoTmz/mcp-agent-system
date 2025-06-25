# MCP Agent System - Gemini対応版

## 🚀 概要

MCP (Model Context Protocol) 対応の多機能AIエージェント会話システムです。Google Gemini Pro APIを使用し、PowerShell REST APIサーバーとJavaScript フロントエンドで構成されています。

## ✨ 主な機能

### 🧠 AI機能
- **Google Gemini Pro統合** - 高性能な対話AI
- **マルチエージェント対応** - 用途別の専門エージェント
- **MCP準拠** - Model Context Protocol対応
- **リアルタイム会話** - 即座のレスポンス

### 🔧 技術仕様
- **Backend**: PowerShell 7.0+ REST API
- **Frontend**: バニラJavaScript + モダンCSS
- **API**: Google Gemini Pro API
- **認証**: JWT トークン認証
- **セキュリティ**: CORS、レート制限、入力検証

### 🤖 利用可能エージェント

1. **汎用アシスタント** - 一般的な質問対応
2. **技術エキスパート** - プログラミング・システム設計
3. **クリエイティブ・ディレクター** - 創造的なアイデア生成
4. **データアナリスト** - 論理的分析・データ処理
5. **日本語スペシャリスト** - 日本語特化対話

## 🛠️ セットアップ

### 1. 必要な環境
- Windows 10/11
- PowerShell 7.0+
- モダンWebブラウザ
- Google AI Studio APIキー

### 2. APIキー取得
1. [Google AI Studio](https://makersuite.google.com/app/apikey) にアクセス
2. 「Create API Key」でAPIキーを生成
3. APIキーをコピー

### 3. 起動手順

#### 簡単起動
```bash
# 1. APIキー設定
start-server.bat を編集して GEMINI_API_KEY を設定

# 2. サーバー起動
start-server.bat をダブルクリック

# 3. フロントエンド起動
frontend/index.html をブラウザで開く
```

#### 手動起動
```powershell
# 環境変数設定
$env:GEMINI_API_KEY = "your_api_key_here"
$env:JWT_SECRET = "your_jwt_secret"

# サーバー起動
powershell.exe -File backend/api.ps1
```

## 📡 API エンドポイント

### `/api/chat` - 会話エンドポイント
```json
POST /api/chat
{
  "messages": [
    {"role": "user", "content": "こんにちは"}
  ],
  "agentId": "default",
  "temperature": 0.7,
  "max_tokens": 2048
}
```

### `/api/agents` - エージェント一覧
```json
GET /api/agents
{
  "agents": [...],
  "provider": "Google Gemini",
  "model": "gemini-pro"
}
```

### `/api/health` - システム状態
```json
GET /api/health
{
  "status": "healthy",
  "provider": "Google Gemini",
  "model": "gemini-pro"
}
```

## 🔐 認証

### JWT認証
```json
POST /api/auth/login
{
  "username": "user",
  "password": "pass"
}
```

## 🌐 デプロイメント

### Azure App Service
```powershell
# Azure環境構築
./scripts/setup-azure.ps1
```

### GitHub Actions
- 自動デプロイパイプライン設定済み
- CI/CDワークフロー対応

## 🎯 使用例

### 基本的な会話
```javascript
const response = await fetch('/api/chat', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    messages: [{role: 'user', content: '日本の首都は？'}],
    agentId: 'japanese'
  })
});
```

### 技術的な質問
```javascript
const response = await fetch('/api/chat', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    messages: [{role: 'user', content: 'JavaScriptの非同期処理について教えて'}],
    agentId: 'technical'
  })
});
```

## 🔧 設定

### 環境変数
```bash
GEMINI_API_KEY=your_gemini_api_key_here
JWT_SECRET=your_jwt_secret_here
```

### サーバー設定
```powershell
$Config = @{
    Port = 8080
    MaxConcurrentRequests = 100
    RateLimitPerMinute = 60
    GeminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
}
```

## 📊 監視・ログ

### ヘルスチェック
```bash
curl http://localhost:8080/api/health
```

### ログファイル
- 場所: `./logs/api-YYYY-MM-DD.log`
- 形式: タイムスタンプ + レベル + メッセージ

## 🔄 アップデート履歴

### v1.1.0 (2024-12-XX)
- **Google Gemini Pro API統合** - OpenAIからGeminiに移行
- **新エージェント追加** - 日本語スペシャリスト
- **改善されたエラーハンドリング** - Gemini特有のレスポンス処理
- **パフォーマンス向上** - レスポンス時間短縮

### v1.0.0 (2024-12-XX)
- 初回リリース
- MCP準拠実装
- PowerShell REST API
- JavaScript フロントエンド

## 🤝 貢献

### 開発環境
```bash
git clone https://github.com/chnmotoTmz/mcp-agent-system.git
cd mcp-agent-system
# 環境設定
```

### Issue・Pull Request
- バグレポート歓迎
- 機能要望歓迎
- コードレビュー歓迎

## 📄 ライセンス

MIT License - 詳細は LICENSE ファイルを参照

## 🙋‍♂️ サポート

### ドキュメント
- [Google AI Studio](https://makersuite.google.com/)
- [Gemini API Documentation](https://ai.google.dev/)
- [MCP Specification](https://spec.modelcontextprotocol.io/)

### トラブルシューティング

#### APIキーエラー
```
環境変数 GEMINI_API_KEY が設定されていません
```
→ Google AI Studio でAPIキーを取得し、環境変数に設定

#### PowerShell実行エラー
```
実行ポリシーエラー
```
→ `Set-ExecutionPolicy RemoteSigned` を実行

#### CORS エラー
```
Access to fetch blocked by CORS policy
```
→ 許可されたオリジンを確認

## 🎉 Special Thanks

- Google AI Team (Gemini API)
- PowerShell Community
- JavaScript Community
- MCP Protocol Contributors

---

**🚀 Let's build amazing AI experiences with Gemini!**