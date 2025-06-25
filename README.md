# MCP対応AIエージェント会話システム

PowerShell REST APIサーバー + JavaScript フロントエンドで構築された、MCP（Model Context Protocol）対応のマルチエージェント会話システムです。

## 🏗️ アーキテクチャ

### バックエンド (PowerShell)
- **PowerShell 7.0+** REST APIサーバー
- **JWT認証** とレート制限
- **CORS対応** で安全なクロスオリジン通信
- **OpenAI API** 統合
- **マルチエージェント** サポート

### フロントエンド (JavaScript)
- **バニラJavaScript** + HTML/CSS
- **MCP準拠** のエージェント通信
- **リアルタイム会話** インターface
- **レスポンシブデザイン**

### CI/CD & デプロイメント
- **GitHub Actions** による自動デプロイ
- **Multi-Cloud対応** (Azure, AWS, GCP)
- **Docker化** 対応

## 🚀 クイックスタート

### 前提条件
- PowerShell 7.0以上
- OpenAI API キー
- モダンなWebブラウザ

### 環境変数設定
```powershell
$env:OPENAI_API_KEY = "your-openai-api-key"
$env:JWT_SECRET = "your-jwt-secret"
```

### サーバー起動
```powershell
cd backend
.\api.ps1
```

### フロントエンド
ブラウザで `frontend/index.html` を開く、またはWebサーバーでホスト

## 📁 プロジェクト構造

```
mcp-agent-system/
├── backend/                   # PowerShell REST APIサーバー
│   └── api.ps1               # メインAPIサーバー
├── frontend/                  # JavaScript フロントエンド
│   ├── index.html            # メインUI
│   ├── css/                  # スタイルシート
│   └── js/                   # JavaScript モジュール
├── .github/workflows/         # CI/CDパイプライン
├── scripts/                   # デプロイスクリプト
└── docs/                     # ドキュメント
```

## 🔧 機能

### エージェント種類
- **汎用アシスタント**: 一般的な質問対応
- **技術エキスパート**: プログラミング・技術問題
- **クリエイティブ・ディレクター**: 創造的コンテンツ生成
- **データアナリスト**: 分析・研究支援

### API エンドポイント
- `GET /api/agents` - 利用可能エージェント一覧
- `POST /api/chat` - チャット会話
- `POST /api/auth/login` - JWT認証
- `GET /api/health` - ヘルスチェック

## 🛡️ セキュリティ

- JWT トークン認証
- レート制限 (60req/min)
- CORS 保護
- 入力検証とサニタイズ
- セキュアなAPIキー管理

## 🌐 デプロイメント

### Azure Functions
```powershell
.\scripts\setup-azure.ps1
```

### AWS Lambda
```bash
./scripts/setup-aws.sh
```

### Google Cloud Run
```bash
./scripts/setup-gcp.sh
```

## 📝 ライセンス

MIT License

## 🤝 コントリビューション

Issues、Pull Requests歓迎です！

## 📞 サポート

問題や質問がある場合は、GitHubのIssuesをご利用ください。
