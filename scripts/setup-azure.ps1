# Azure環境セットアップスクリプト - MCP Agent System (Gemini対応)
# このスクリプトはAzure環境にGemini対応のMCPエージェントシステムをデプロイします

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$AppServiceName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "Japan East",
    
    [Parameter(Mandatory=$false)]
    [string]$SKU = "F1",
    
    [Parameter(Mandatory=$true)]
    [string]$GeminiApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$JWTSecret = (New-Guid).ToString()
)

Write-Host "🚀 MCP Agent System (Gemini Edition) Azure セットアップ開始" -ForegroundColor Green
Write-Host "Provider: Google Gemini Pro" -ForegroundColor Cyan

# 必要なモジュールの確認
Write-Host "📦 Azure PowerShellモジュール確認中..." -ForegroundColor Yellow
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Azure PowerShellモジュールをインストール中..." -ForegroundColor Yellow
    Install-Module -Name Az -Force -AllowClobber
}

# Azureログイン
Write-Host "🔐 Azure認証中..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount
    }
    Write-Host "✅ Azure認証成功" -ForegroundColor Green
} catch {
    Write-Error "❌ Azure認証失敗: $_"
    exit 1
}

# リソースグループ作成
Write-Host "📁 リソースグループ作成中: $ResourceGroupName" -ForegroundColor Yellow
try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
        Write-Host "✅ リソースグループ作成成功" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ リソースグループは既に存在します" -ForegroundColor Cyan
    }
} catch {
    Write-Error "❌ リソースグループ作成失敗: $_"
    exit 1
}

# App Service Plan作成
$appServicePlanName = "$AppServiceName-plan"
Write-Host "⚙️ App Service Plan作成中: $appServicePlanName" -ForegroundColor Yellow
try {
    $plan = Get-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $appServicePlanName -ErrorAction SilentlyContinue
    if (-not $plan) {
        New-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $appServicePlanName -Location $Location -Tier $SKU | Out-Null
        Write-Host "✅ App Service Plan作成成功" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ App Service Planは既に存在します" -ForegroundColor Cyan
    }
} catch {
    Write-Error "❌ App Service Plan作成失敗: $_"
    exit 1
}

# Web App作成
Write-Host "🌐 Web App作成中: $AppServiceName" -ForegroundColor Yellow
try {
    $webapp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppServiceName -ErrorAction SilentlyContinue
    if (-not $webapp) {
        New-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppServiceName -AppServicePlan $appServicePlanName | Out-Null
        Write-Host "✅ Web App作成成功" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ Web Appは既に存在します" -ForegroundColor Cyan
    }
} catch {
    Write-Error "❌ Web App作成失敗: $_"
    exit 1
}

# アプリケーション設定
Write-Host "⚙️ アプリケーション設定構成中..." -ForegroundColor Yellow
$appSettings = @{
    "GEMINI_API_KEY" = $GeminiApiKey
    "JWT_SECRET" = $JWTSecret
    "ENVIRONMENT" = "production"
    "PORT" = "8080"
    "PROVIDER" = "Google Gemini"
    "MODEL" = "gemini-pro"
    "WEBSITE_NODE_DEFAULT_VERSION" = "18.x"
    "WEBSITE_POWERSHELL_VERSION" = "7.4"
}

try {
    Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppServiceName -AppSettings $appSettings | Out-Null
    Write-Host "✅ アプリケーション設定完了" -ForegroundColor Green
} catch {
    Write-Error "❌ アプリケーション設定失敗: $_"
    exit 1
}

# CORS設定
Write-Host "🔒 CORS設定中..." -ForegroundColor Yellow
try {
    $corsSettings = @(
        "https://$AppServiceName.azurewebsites.net",
        "http://localhost:*",
        "https://*.github.io"
    )
    
    # Note: PowerShellでのCORS設定は制限があるため、手動設定を推奨
    Write-Host "⚠️ CORS設定はAzure Portalで手動設定してください:" -ForegroundColor Yellow
    Write-Host "   - Azure Portal > App Service > CORS" -ForegroundColor Yellow
    Write-Host "   - 許可するオリジン: $($corsSettings -join ', ')" -ForegroundColor Yellow
} catch {
    Write-Warning "CORS設定をスキップしました。Azure Portalで手動設定してください。"
}

# デプロイメント設定
Write-Host "📦 デプロイメント設定中..." -ForegroundColor Yellow
try {
    # GitHub Actionsでのデプロイ用の設定
    $sourceControl = @{
        "RepoUrl" = "https://github.com/chnmotoTmz/mcp-agent-system.git"
        "Branch" = "main"
        "IsManualIntegration" = $true
    }
    
    Write-Host "ℹ️ GitHub Actionsでの自動デプロイを推奨します" -ForegroundColor Cyan
    Write-Host "   リポジトリ: https://github.com/chnmotoTmz/mcp-agent-system" -ForegroundColor Cyan
} catch {
    Write-Warning "デプロイメント設定をスキップしました。"
}

# SSL/TLS設定
Write-Host "🔐 SSL/TLS設定中..." -ForegroundColor Yellow
try {
    Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppServiceName -HttpsOnly $true | Out-Null
    Write-Host "✅ HTTPS強制設定完了" -ForegroundColor Green
} catch {
    Write-Warning "SSL/TLS設定に問題がありました: $_"
}

# 診断ログ設定
Write-Host "📋 診断ログ設定中..." -ForegroundColor Yellow
try {
    # アプリケーションログ有効化
    Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppServiceName -DetailedErrorLoggingEnabled $true -HttpLoggingEnabled $true -RequestTracingEnabled $true | Out-Null
    Write-Host "✅ 診断ログ設定完了" -ForegroundColor Green
} catch {
    Write-Warning "診断ログ設定に問題がありました: $_"
}

# 設定完了メッセージ
Write-Host "
🎉 Azure環境セットアップ完了! 🎉" -ForegroundColor Green
Write-Host "═══════════════════════════════════════" -ForegroundColor Green
Write-Host "📊 設定サマリー:" -ForegroundColor Cyan
Write-Host "   リソースグループ: $ResourceGroupName" -ForegroundColor White
Write-Host "   App Service: $AppServiceName" -ForegroundColor White
Write-Host "   URL: https://$AppServiceName.azurewebsites.net" -ForegroundColor White
Write-Host "   SKU: $SKU" -ForegroundColor White
Write-Host "   場所: $Location" -ForegroundColor White
Write-Host "   Provider: Google Gemini Pro" -ForegroundColor White
Write-Host "
🔧 次のステップ:" -ForegroundColor Yellow
Write-Host "1. GitHub Actionsでの自動デプロイ設定" -ForegroundColor White
Write-Host "2. Azure PortalでCORS設定確認" -ForegroundColor White
Write-Host "3. Gemini APIキーの設定確認" -ForegroundColor White
Write-Host "4. アプリケーションデプロイ" -ForegroundColor White
Write-Host "
🌐 エンドポイント:" -ForegroundColor Yellow
Write-Host "   Health Check: https://$AppServiceName.azurewebsites.net/api/health" -ForegroundColor White
Write-Host "   Chat API: https://$AppServiceName.azurewebsites.net/api/chat" -ForegroundColor White
Write-Host "   Agents: https://$AppServiceName.azurewebsites.net/api/agents" -ForegroundColor White
Write-Host "
📚 ドキュメント:" -ForegroundColor Yellow
Write-Host "   GitHub: https://github.com/chnmotoTmz/mcp-agent-system" -ForegroundColor White
Write-Host "   Gemini API: https://ai.google.dev/" -ForegroundColor White
Write-Host "═══════════════════════════════════════" -ForegroundColor Green

# 設定情報をファイルに保存
$configInfo = @{
    ResourceGroupName = $ResourceGroupName
    AppServiceName = $AppServiceName
    Location = $Location
    SKU = $SKU
    URL = "https://$AppServiceName.azurewebsites.net"
    HealthCheckURL = "https://$AppServiceName.azurewebsites.net/api/health"
    SetupDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Provider = "Google Gemini Pro"
    Model = "gemini-pro"
}

$configPath = "./azure-deployment-config.json"
$configInfo | ConvertTo-Json -Depth 3 | Set-Content -Path $configPath -Encoding UTF8
Write-Host "💾 デプロイ設定を保存しました: $configPath" -ForegroundColor Green

Write-Host "
🚀 セットアップ完了! Gemini対応のMCPエージェントシステムの準備ができました。" -ForegroundColor Green