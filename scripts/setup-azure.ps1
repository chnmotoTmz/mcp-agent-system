#Requires -Version 7.0
# Azure環境セットアップスクリプト

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory = $false)]
    [string]$AppName = "mcp-agent-system",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipLogin
)

# カラー出力関数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    $originalColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Message
    $Host.UI.RawUI.ForegroundColor = $originalColor
}

# エラーハンドリング
$ErrorActionPreference = "Stop"

try {
    Write-ColorOutput "🚀 Azure環境セットアップを開始します..." "Green"
    
    # Azure CLI ログイン確認
    if (-not $SkipLogin) {
        Write-ColorOutput "📋 Azure CLI へのログインを確認中..." "Yellow"
        
        try {
            $account = az account show --query "user.name" -o tsv 2>$null
            if ($account) {
                Write-ColorOutput "✅ Azure CLI にログイン済み: $account" "Green"
            } else {
                throw "Not logged in"
            }
        } catch {
            Write-ColorOutput "🔐 Azure CLI へのログインが必要です..." "Yellow"
            az login
        }
    }
    
    # サブスクリプション確認
    $subscription = az account show --query "name" -o tsv
    Write-ColorOutput "📊 使用中のサブスクリプション: $subscription" "Cyan"
    
    # リソースグループ作成
    Write-ColorOutput "📁 リソースグループを作成中..." "Yellow"
    
    $existingRg = az group show --name $ResourceGroupName --query "name" -o tsv 2>$null
    if ($existingRg) {
        Write-ColorOutput "⚠️  リソースグループ '$ResourceGroupName' は既に存在します" "Yellow"
    } else {
        az group create --name $ResourceGroupName --location $Location
        Write-ColorOutput "✅ リソースグループ '$ResourceGroupName' を作成しました" "Green"
    }
    
    # App Service Plan 作成
    Write-ColorOutput "🖥️  App Service Plan を作成中..." "Yellow"
    
    $planName = "$AppName-plan"
    $existingPlan = az appservice plan show --name $planName --resource-group $ResourceGroupName --query "name" -o tsv 2>$null
    
    if ($existingPlan) {
        Write-ColorOutput "⚠️  App Service Plan '$planName' は既に存在します" "Yellow"
    } else {
        az appservice plan create `
            --name $planName `
            --resource-group $ResourceGroupName `
            --sku B1 `
            --is-linux
        Write-ColorOutput "✅ App Service Plan '$planName' を作成しました" "Green"
    }
    
    # Function App 作成 (PowerShell バックエンド用)
    Write-ColorOutput "⚡ Function App を作成中..." "Yellow"
    
    $functionAppName = "$AppName-backend"
    $storageAccountName = ($AppName.Replace("-", "") + "storage").ToLower()
    
    # ストレージアカウント作成
    $existingStorage = az storage account show --name $storageAccountName --resource-group $ResourceGroupName --query "name" -o tsv 2>$null
    if (-not $existingStorage) {
        az storage account create `
            --name $storageAccountName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --sku Standard_LRS
        Write-ColorOutput "✅ ストレージアカウント '$storageAccountName' を作成しました" "Green"
    }
    
    # Function App 作成
    $existingFunction = az functionapp show --name $functionAppName --resource-group $ResourceGroupName --query "name" -o tsv 2>$null
    if ($existingFunction) {
        Write-ColorOutput "⚠️  Function App '$functionAppName' は既に存在します" "Yellow"
    } else {
        az functionapp create `
            --name $functionAppName `
            --resource-group $ResourceGroupName `
            --storage-account $storageAccountName `
            --plan $planName `
            --runtime powershell `
            --runtime-version 7.2 `
            --functions-version 4
        Write-ColorOutput "✅ Function App '$functionAppName' を作成しました" "Green"
    }
    
    # Static Web App 作成 (フロントエンド用)
    Write-ColorOutput "🌐 Static Web App を作成中..." "Yellow"
    
    $staticAppName = "$AppName-frontend"
    $existingStatic = az staticwebapp show --name $staticAppName --resource-group $ResourceGroupName --query "name" -o tsv 2>$null
    
    if ($existingStatic) {
        Write-ColorOutput "⚠️  Static Web App '$staticAppName' は既に存在します" "Yellow"
    } else {
        # GitHub リポジトリ情報（ユーザーが設定する必要がある）
        Write-ColorOutput "⚠️  Static Web App作成には GitHub リポジトリが必要です" "Yellow"
        Write-ColorOutput "以下のコマンドを手動で実行してください:" "Cyan"
        Write-ColorOutput "az staticwebapp create --name $staticAppName --resource-group $ResourceGroupName --source https://github.com/YOUR_USERNAME/YOUR_REPO --location $Location --branch main --app-location '/frontend' --login-with-github" "White"
    }
    
    # Application Insights 作成
    Write-ColorOutput "📈 Application Insights を作成中..." "Yellow"
    
    $insightsName = "$AppName-insights"
    $existingInsights = az monitor app-insights component show --app $insightsName --resource-group $ResourceGroupName --query "name" -o tsv 2>$null
    
    if ($existingInsights) {
        Write-ColorOutput "⚠️  Application Insights '$insightsName' は既に存在します" "Yellow"
    } else {
        az monitor app-insights component create `
            --app $insightsName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --kind web
        Write-ColorOutput "✅ Application Insights '$insightsName' を作成しました" "Green"
    }
    
    # Key Vault 作成
    Write-ColorOutput "🔐 Key Vault を作成中..." "Yellow"
    
    $keyVaultName = "$AppName-kv-$(Get-Random -Maximum 9999)"
    $existingKeyVault = az keyvault show --name $keyVaultName --resource-group $ResourceGroupName --query "name" -o tsv 2>$null
    
    if (-not $existingKeyVault) {
        az keyvault create `
            --name $keyVaultName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --sku standard
        Write-ColorOutput "✅ Key Vault '$keyVaultName' を作成しました" "Green"
        
        # 現在のユーザーにアクセス許可を付与
        $currentUser = az account show --query "user.name" -o tsv
        az keyvault set-policy `
            --name $keyVaultName `
            --upn $currentUser `
            --secret-permissions get list set delete
    }
    
    # Function App 設定
    Write-ColorOutput "⚙️  Function App の設定を構成中..." "Yellow"
    
    # Application Insights 接続文字列取得
    $instrumentationKey = az monitor app-insights component show `
        --app $insightsName `
        --resource-group $ResourceGroupName `
        --query "instrumentationKey" -o tsv
    
    # Function App 設定更新
    az functionapp config appsettings set `
        --name $functionAppName `
        --resource-group $ResourceGroupName `
        --settings `
        "APPINSIGHTS_INSTRUMENTATIONKEY=$instrumentationKey" `
        "AzureWebJobsFeatureFlags=EnableWorkerIndexing" `
        "FUNCTIONS_WORKER_RUNTIME=powershell"
    
    # CORS 設定
    az functionapp cors add `
        --name $functionAppName `
        --resource-group $ResourceGroupName `
        --allowed-origins "https://$staticAppName.azurestaticapps.net" "http://localhost:*"
    
    Write-ColorOutput "✅ Function App の設定を完了しました" "Green"
    
    # 環境変数設定ガイド
    Write-ColorOutput "`n📋 環境変数設定ガイド" "Cyan"
    Write-ColorOutput "以下の環境変数を設定してください:" "White"
    Write-ColorOutput "`n🔑 OpenAI API Key:" "Yellow"
    Write-ColorOutput "az functionapp config appsettings set --name $functionAppName --resource-group $ResourceGroupName --settings 'OPENAI_API_KEY=your_openai_api_key_here'" "White"
    
    Write-ColorOutput "`n🔐 JWT Secret:" "Yellow"
    Write-ColorOutput "az functionapp config appsettings set --name $functionAppName --resource-group $ResourceGroupName --settings 'JWT_SECRET=your_jwt_secret_here'" "White"
    
    # Key Vault シークレット設定例
    Write-ColorOutput "`n🗝️  Key Vault にシークレットを保存:" "Yellow"
    Write-ColorOutput "az keyvault secret set --vault-name $keyVaultName --name 'OpenAI-API-Key' --value 'your_openai_api_key_here'" "White"
    Write-ColorOutput "az keyvault secret set --vault-name $keyVaultName --name 'JWT-Secret' --value 'your_jwt_secret_here'" "White"
    
    # GitHub Secrets 設定ガイド
    Write-ColorOutput "`n🚀 GitHub Secrets 設定ガイド" "Cyan"
    Write-ColorOutput "以下のシークレットをGitHubリポジトリに設定してください:" "White"
    
    # サービスプリンシパル作成
    Write-ColorOutput "`n👤 サービスプリンシパルを作成中..." "Yellow"
    
    $subscriptionId = az account show --query "id" -o tsv
    $spName = "$AppName-sp"
    
    $spResult = az ad sp create-for-rbac `
        --name $spName `
        --role Contributor `
        --scopes "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName" `
        --sdk-auth
    
    Write-ColorOutput "`nGitHub Secrets:" "Yellow"
    Write-ColorOutput "AZURE_CREDENTIALS: $spResult" "White"
    Write-ColorOutput "AZURE_FUNCTIONAPP_NAME: $functionAppName" "White"
    Write-ColorOutput "AZURE_RESOURCE_GROUP: $ResourceGroupName" "White"
    
    # Static Web App deployment token
    $staticToken = az staticwebapp secrets list --name $staticAppName --resource-group $ResourceGroupName --query "properties.apiKey" -o tsv 2>$null
    if ($staticToken) {
        Write-ColorOutput "AZURE_STATIC_WEB_APPS_API_TOKEN: $staticToken" "White"
    }
    
    # デプロイメント情報
    Write-ColorOutput "`n🌐 デプロイメント情報" "Cyan"
    Write-ColorOutput "Function App URL: https://$functionAppName.azurewebsites.net" "White"
    Write-ColorOutput "Static Web App URL: https://$staticAppName.azurestaticapps.net" "White"
    Write-ColorOutput "Resource Group: $ResourceGroupName" "White"
    Write-ColorOutput "Key Vault: $keyVaultName" "White"
    
    # 次のステップ
    Write-ColorOutput "`n📝 次のステップ" "Cyan"
    Write-ColorOutput "1. GitHub リポジトリにコードをプッシュ" "White"
    Write-ColorOutput "2. GitHub Secrets を設定" "White"
    Write-ColorOutput "3. 環境変数/Key Vault シークレットを設定" "White"
    Write-ColorOutput "4. GitHub Actions でデプロイメント実行" "White"
    
    Write-ColorOutput "`n🎉 Azure環境セットアップが完了しました!" "Green"
    
} catch {
    Write-ColorOutput "`n❌ エラーが発生しました: $($_.Exception.Message)" "Red"
    Write-ColorOutput "スタックトレース: $($_.ScriptStackTrace)" "Red"
    exit 1
}