#!/bin/bash

# Google Cloud Platform環境セットアップスクリプト
set -e

# カラー出力関数
print_color() {
    local color=$1
    local message=$2
    case $color in
        "red") echo -e "\033[31m$message\033[0m" ;;
        "green") echo -e "\033[32m$message\033[0m" ;;
        "yellow") echo -e "\033[33m$message\033[0m" ;;
        "blue") echo -e "\033[34m$message\033[0m" ;;
        "cyan") echo -e "\033[36m$message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

# 設定
APP_NAME="${1:-mcp-agent-system}"
GCP_REGION="${2:-us-central1}"
PROJECT_ID="${3}"

if [ -z "$PROJECT_ID" ]; then
    print_color "red" "❌ プロジェクトIDが指定されていません"
    print_color "yellow" "使用方法: $0 [APP_NAME] [REGION] [PROJECT_ID]"
    exit 1
fi

print_color "green" "🚀 Google Cloud Platform環境セットアップを開始します..."

# Google Cloud CLI の確認
if ! command -v gcloud &> /dev/null; then
    print_color "red" "❌ Google Cloud CLI がインストールされていません"
    print_color "yellow" "インストール手順: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# 認証確認
print_color "yellow" "📋 Google Cloud CLI の認証を確認中..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
    print_color "yellow" "🔐 Google Cloud CLI へのログインが必要です..."
    gcloud auth login
fi

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
print_color "green" "✅ 認証確認: $ACTIVE_ACCOUNT"

# プロジェクト設定
print_color "yellow" "📊 プロジェクトを設定中..."
gcloud config set project "$PROJECT_ID"
print_color "green" "✅ プロジェクト設定: $PROJECT_ID"

# 必要なAPI有効化
print_color "yellow" "🔌 必要なAPIを有効化中..."

APIS=(
    "cloudfunctions.googleapis.com"
    "storage-api.googleapis.com"
    "cloudbuild.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "run.googleapis.com"
    "secretmanager.googleapis.com"
    "logging.googleapis.com"
    "monitoring.googleapis.com"
    "iam.googleapis.com"
)

for api in "${APIS[@]}"; do
    print_color "yellow" "  - $api を有効化中..."
    gcloud services enable "$api" --project="$PROJECT_ID"
done

print_color "green" "✅ 必要なAPIを有効化しました"

# Cloud Storage バケット作成（フロントエンド用）
print_color "yellow" "🪣 Cloud Storage バケットを作成中..."

FRONTEND_BUCKET="$APP_NAME-frontend-$PROJECT_ID"

if gsutil ls -b "gs://$FRONTEND_BUCKET" &> /dev/null; then
    print_color "yellow" "⚠️  バケット '$FRONTEND_BUCKET' は既に存在します"
else
    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$GCP_REGION" "gs://$FRONTEND_BUCKET"
    print_color "green" "✅ バケット '$FRONTEND_BUCKET' を作成しました"
fi

# バケットをWebホスティング用に設定
gsutil web set -m index.html -e index.html "gs://$FRONTEND_BUCKET"

# パブリックアクセス設定
gsutil iam ch allUsers:objectViewer "gs://$FRONTEND_BUCKET"

print_color "green" "✅ フロントエンド用ストレージを設定しました"

# Cloud Run サービス作成（バックエンド用）
print_color "yellow" "🏃 Cloud Run サービスを作成中..."

SERVICE_NAME="$APP_NAME-backend"

# Dockerfile 作成（PowerShell対応）
mkdir -p /tmp/cloudrun-backend
cat > /tmp/cloudrun-backend/Dockerfile << 'EOF'
FROM mcr.microsoft.com/powershell:7.3-ubuntu-20.04

WORKDIR /app

# 必要なパッケージインストール
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# PowerShell モジュールインストール
RUN pwsh -Command "Install-Module -Name Microsoft.PowerShell.SecretManagement -Force -Scope AllUsers"
RUN pwsh -Command "Install-Module -Name Google.Cloud.SecretManager -Force -Scope AllUsers"

# アプリケーションファイルコピー
COPY . .

# ポート設定
ENV PORT=8080
EXPOSE 8080

# エントリーポイント
CMD ["pwsh", "-File", "api.ps1"]
EOF

# 一時的なapi.ps1作成
cat > /tmp/cloudrun-backend/api.ps1 << 'EOF'
# Cloud Run用 PowerShell API サーバー
param(
    [string]$Port = $env:PORT ?? "8080"
)

# HTTP リスナー起動
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://*:$Port/")
$listener.Start()

Write-Host "PowerShell API Server started on port $Port"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $response = $context.Response
    
    # CORS ヘッダー
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    
    # レスポンス
    $responseString = '{"status": "healthy", "message": "PowerShell API Server on Cloud Run"}'
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.Close()
}
EOF

# Cloud Build でイメージ作成
cd /tmp/cloudrun-backend
gcloud builds submit --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" .

# Cloud Run サービスデプロイ
if gcloud run services describe "$SERVICE_NAME" --region="$GCP_REGION" &> /dev/null; then
    print_color "yellow" "⚠️  Cloud Run サービス '$SERVICE_NAME' は既に存在します。更新します..."
    gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/$PROJECT_ID/$SERVICE_NAME" \
        --platform managed \
        --region "$GCP_REGION" \
        --allow-unauthenticated \
        --memory 512Mi \
        --cpu 1 \
        --concurrency 100 \
        --max-instances 10
else
    print_color "yellow" "🚀 Cloud Run サービスをデプロイ中..."
    gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/$PROJECT_ID/$SERVICE_NAME" \
        --platform managed \
        --region "$GCP_REGION" \
        --allow-unauthenticated \
        --memory 512Mi \
        --cpu 1 \
        --concurrency 100 \
        --max-instances 10
fi

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$GCP_REGION" --format="value(status.url)")
print_color "green" "✅ Cloud Run サービスをデプロイしました: $SERVICE_URL"

# Secret Manager でシークレット管理
print_color "yellow" "🔐 Secret Manager でシークレットを設定中..."

# OpenAI API Key シークレット
SECRET_NAME="openai-api-key"
if gcloud secrets describe "$SECRET_NAME" &> /dev/null; then
    print_color "yellow" "⚠️  シークレット '$SECRET_NAME' は既に存在します"
else
    echo "your_openai_api_key_here" | gcloud secrets create "$SECRET_NAME" --data-file=-
    print_color "green" "✅ シークレット '$SECRET_NAME' を作成しました"
fi

# JWT Secret
JWT_SECRET_NAME="jwt-secret"
if gcloud secrets describe "$JWT_SECRET_NAME" &> /dev/null; then
    print_color "yellow" "⚠️  シークレット '$JWT_SECRET_NAME' は既に存在します"
else
    openssl rand -base64 32 | gcloud secrets create "$JWT_SECRET_NAME" --data-file=-
    print_color "green" "✅ シークレット '$JWT_SECRET_NAME' を作成しました"
fi

# Cloud Run サービスにシークレットアクセス権限付与
SERVICE_ACCOUNT=$(gcloud run services describe "$SERVICE_NAME" --region="$GCP_REGION" --format="value(spec.template.spec.serviceAccountName)")

if [ -z "$SERVICE_ACCOUNT" ]; then
    SERVICE_ACCOUNT="$PROJECT_ID@appspot.gserviceaccount.com"
fi

gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding "$JWT_SECRET_NAME" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/secretmanager.secretAccessor"

# Cloud CDN 設定（オプション）
print_color "yellow" "🌐 Cloud CDN を設定中..."

BACKEND_SERVICE_NAME="$APP_NAME-backend-service"
URL_MAP_NAME="$APP_NAME-url-map"

# バックエンドサービス作成
if ! gcloud compute backend-services describe "$BACKEND_SERVICE_NAME" --global &> /dev/null; then
    gcloud compute backend-services create "$BACKEND_SERVICE_NAME" \
        --protocol=HTTP \
        --port-name=http \
        --health-checks=default \
        --global
fi

# URL マップ作成
if ! gcloud compute url-maps describe "$URL_MAP_NAME" &> /dev/null; then
    gcloud compute url-maps create "$URL_MAP_NAME" \
        --default-backend-bucket="$FRONTEND_BUCKET"
fi

# サービスアカウント作成（CI/CD用）
print_color "yellow" "👤 CI/CD用サービスアカウントを作成中..."

SA_NAME="$APP_NAME-ci"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SA_EMAIL" &> /dev/null; then
    print_color "yellow" "⚠️  サービスアカウント '$SA_EMAIL' は既に存在します"
else
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name="$APP_NAME CI/CD Service Account" \
        --description="Service account for CI/CD pipeline"
    print_color "green" "✅ サービスアカウント '$SA_EMAIL' を作成しました"
fi

# 必要な権限付与
ROLES=(
    "roles/storage.admin"
    "roles/run.admin"
    "roles/cloudbuild.builds.builder"
    "roles/secretmanager.secretAccessor"
)

for role in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role"
done

# サービスアカウントキー作成
KEY_FILE="/tmp/$SA_NAME-key.json"
if [ ! -f "$KEY_FILE" ]; then
    gcloud iam service-accounts keys create "$KEY_FILE" \
        --iam-account="$SA_EMAIL"
    print_color "green" "✅ サービスアカウントキーを作成しました"
fi

# Deployment Manager テンプレート作成（将来のアップデート用）
print_color "yellow" "📄 Deployment Manager テンプレートを作成中..."

mkdir -p /tmp/deployment-manager
cat > /tmp/deployment-manager/deployment.yaml << EOF
resources:
- name: $APP_NAME-storage
  type: storage.v1.bucket
  properties:
    name: $FRONTEND_BUCKET
    location: $GCP_REGION
    website:
      mainPageSuffix: index.html
      notFoundPage: index.html
    cors:
    - origin: ['*']
      method: ['GET', 'HEAD']
      maxAgeSeconds: 3600

- name: $APP_NAME-cloudrun
  type: gcp-types/run-v1:namespaces.services
  properties:
    parent: namespaces/$PROJECT_ID
    location: $GCP_REGION
    apiVersion: serving.knative.dev/v1
    kind: Service
    spec:
      template:
        spec:
          containers:
          - image: gcr.io/$PROJECT_ID/$SERVICE_NAME
            env:
            - name: OPENAI_SECRET_NAME
              value: $SECRET_NAME
            - name: JWT_SECRET_NAME  
              value: $JWT_SECRET_NAME
EOF

# 結果表示
print_color "cyan" "🌐 デプロイメント情報"
echo "Frontend Bucket: gs://$FRONTEND_BUCKET"
echo "Frontend URL: https://storage.googleapis.com/$FRONTEND_BUCKET/index.html"
echo "Backend Service: $SERVICE_URL"
echo "Project ID: $PROJECT_ID"
echo "Region: $GCP_REGION"

print_color "cyan" "📋 GitHub Secrets 設定"
echo "GCP_PROJECT_ID: $PROJECT_ID"
echo "GCP_SA_KEY: $(cat $KEY_FILE | base64 -w 0)"
echo "GCP_STORAGE_BUCKET: $FRONTEND_BUCKET"
echo "GCP_REGION: $GCP_REGION"

print_color "cyan" "🔐 Secret Manager"
echo "OpenAI API Key Secret: $SECRET_NAME"
echo "JWT Secret: $JWT_SECRET_NAME"

print_color "cyan" "📝 シークレット更新コマンド"
echo "OpenAI API Key更新:"
echo "echo 'your_actual_openai_key' | gcloud secrets versions add $SECRET_NAME --data-file=-"
echo ""
echo "JWT Secret更新:"
echo "openssl rand -base64 32 | gcloud secrets versions add $JWT_SECRET_NAME --data-file=-"

print_color "cyan" "📝 次のステップ"
echo "1. Secret Manager でOpenAI API Keyを実際の値に更新"
echo "2. GitHub Secrets を設定"
echo "3. フロントエンドファイルをバケットにアップロード:"
echo "   gsutil -m cp -r frontend/* gs://$FRONTEND_BUCKET/"
echo "4. GitHub Actions でデプロイメント実行"

print_color "green" "🎉 Google Cloud Platform環境セットアップが完了しました!"

# 一時ファイル削除
rm -rf /tmp/cloudrun-backend /tmp/deployment-manager
rm -f "$KEY_FILE"