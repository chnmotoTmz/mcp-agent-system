#Requires -Version 7.0
# MCP対応AIエージェント会話システム - PowerShell REST APIサーバー

using namespace System.Net
using namespace System.Net.Sockets
using namespace System.Text
using namespace System.Threading
using namespace System.Collections.Generic

# 設定
$script:Config = @{
    Port = 8080
    MaxConcurrentRequests = 100
    OpenAIEndpoint = "https://api.openai.com/v1/chat/completions"
    AllowedOrigins = @("http://localhost:*", "https://*.github.io", "https://*.azurewebsites.net")
    RateLimitPerMinute = 60
    LogPath = "./logs"
}

# レート制限用辞書
$script:RateLimitDict = [System.Collections.Concurrent.ConcurrentDictionary[string, System.Collections.Generic.List[datetime]]]::new()

# 初期化
function Initialize-APIServer {
    # ログディレクトリ作成
    if (-not (Test-Path $Config.LogPath)) {
        New-Item -ItemType Directory -Path $Config.LogPath -Force | Out-Null
    }
    
    # 環境変数からAPIキー取得
    $script:OpenAIKey = $env:OPENAI_API_KEY
    if (-not $OpenAIKey) {
        throw "環境変数 OPENAI_API_KEY が設定されていません"
    }
    
    # JWT署名キー
    $script:JWTSecret = $env:JWT_SECRET ?? (New-Guid).ToString()
    
    Write-Log "APIサーバー初期化完了" -Level Info
}

# ログ出力
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    
    # コンソール出力
    switch ($Level) {
        "Error" { Write-Host $logEntry -ForegroundColor Red }
        "Warning" { Write-Host $logEntry -ForegroundColor Yellow }
        default { Write-Host $logEntry -ForegroundColor Green }
    }
    
    # ファイル出力
    $logFile = Join-Path $Config.LogPath "api-$(Get-Date -Format 'yyyy-MM-dd').log"
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
}

# CORS検証
function Test-CORSOrigin {
    param([string]$Origin)
    
    foreach ($pattern in $Config.AllowedOrigins) {
        if ($Origin -like $pattern) {
            return $true
        }
    }
    return $false
}

# レート制限チェック
function Test-RateLimit {
    param([string]$ClientIP)
    
    $now = Get-Date
    $windowStart = $now.AddMinutes(-1)
    
    # 既存のエントリを取得または新規作成
    $requests = $RateLimitDict.GetOrAdd($ClientIP, [System.Collections.Generic.List[datetime]]::new())
    
    # 古いエントリを削除
    $requests.RemoveAll({ param($d) $d -lt $windowStart }) | Out-Null
    
    # 制限チェック
    if ($requests.Count -ge $Config.RateLimitPerMinute) {
        return $false
    }
    
    # 新しいリクエストを記録
    $requests.Add($now)
    return $true
}

# JWT生成
function New-JWTToken {
    param([string]$UserId)
    
    $header = @{
        alg = "HS256"
        typ = "JWT"
    } | ConvertTo-Json -Compress
    
    $payload = @{
        sub = $UserId
        iat = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        exp = [DateTimeOffset]::UtcNow.AddHours(24).ToUnixTimeSeconds()
    } | ConvertTo-Json -Compress
    
    $headerBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($header))
    $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    
    $signature = Get-HMACSignature -Data "$headerBase64.$payloadBase64" -Key $JWTSecret
    
    return "$headerBase64.$payloadBase64.$signature"
}

# HMAC署名
function Get-HMACSignature {
    param(
        [string]$Data,
        [string]$Key
    )
    
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Key))
    $hash = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Data))
    return [Convert]::ToBase64String($hash)
}

# OpenAI API呼び出し
function Invoke-OpenAIChat {
    param(
        [array]$Messages,
        [string]$Model = "gpt-4",
        [float]$Temperature = 0.7,
        [int]$MaxTokens = 2000
    )
    
    $body = @{
        model = $Model
        messages = $Messages
        temperature = $Temperature
        max_tokens = $MaxTokens
        stream = $false
    } | ConvertTo-Json -Depth 10
    
    $headers = @{
        "Authorization" = "Bearer $OpenAIKey"
        "Content-Type" = "application/json"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $Config.OpenAIEndpoint -Method Post -Headers $headers -Body $body
        return @{
            Success = $true
            Content = $response.choices[0].message.content
            Usage = $response.usage
        }
    }
    catch {
        Write-Log "OpenAI API Error: $_" -Level Error
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# HTTPレスポンス送信
function Send-HTTPResponse {
    param(
        [HttpListenerContext]$Context,
        [int]$StatusCode,
        [object]$Body,
        [hashtable]$Headers = @{}
    )
    
    $response = $Context.Response
    $response.StatusCode = $StatusCode
    
    # 共通ヘッダー
    $response.Headers.Add("Content-Type", "application/json; charset=utf-8")
    $response.Headers.Add("X-Content-Type-Options", "nosniff")
    $response.Headers.Add("X-Frame-Options", "DENY")
    
    # CORS対応
    $origin = $Context.Request.Headers["Origin"]
    if ($origin -and (Test-CORSOrigin -Origin $origin)) {
        $response.Headers.Add("Access-Control-Allow-Origin", $origin)
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization")
        $response.Headers.Add("Access-Control-Max-Age", "86400")
    }
    
    # カスタムヘッダー
    foreach ($key in $Headers.Keys) {
        $response.Headers.Add($key, $Headers[$key])
    }
    
    # ボディ送信
    if ($Body) {
        $json = $Body | ConvertTo-Json -Depth 10 -Compress
        $buffer = [Text.Encoding]::UTF8.GetBytes($json)
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
    }
    
    $response.Close()
}

# エンドポイント: /api/chat
function Handle-ChatEndpoint {
    param([HttpListenerContext]$Context)
    
    # POSTのみ許可
    if ($Context.Request.HttpMethod -ne "POST") {
        Send-HTTPResponse -Context $Context -StatusCode 405 -Body @{
            error = "Method not allowed"
        }
        return
    }
    
    # リクエストボディ読み取り
    $reader = [System.IO.StreamReader]::new($Context.Request.InputStream)
    $requestBody = $reader.ReadToEnd()
    $reader.Close()
    
    try {
        $data = $requestBody | ConvertFrom-Json
        
        # 入力検証
        if (-not $data.messages -or $data.messages.Count -eq 0) {
            throw "messages フィールドが必要です"
        }
        
        # エージェント情報抽出
        $agentId = $data.agentId ?? "default"
        $agentPrompt = switch ($agentId) {
            "technical" { "あなたは技術的な質問に詳しく答える専門家です。" }
            "creative" { "あなたは創造的で独創的なアイデアを提供するクリエイターです。" }
            "analytical" { "あなたは論理的で分析的な思考を行うアナリストです。" }
            default { "あなたは親切で役立つAIアシスタントです。" }
        }
        
        # システムプロンプト追加
        $messages = @(
            @{
                role = "system"
                content = $agentPrompt
            }
        ) + $data.messages
        
        # OpenAI API呼び出し
        $result = Invoke-OpenAIChat -Messages $messages -Model ($data.model ?? "gpt-4") -Temperature ($data.temperature ?? 0.7)
        
        if ($result.Success) {
            Send-HTTPResponse -Context $Context -StatusCode 200 -Body @{
                success = $true
                agentId = $agentId
                response = $result.Content
                usage = $result.Usage
                timestamp = (Get-Date).ToUniversalTime().ToString("o")
            }
        }
        else {
            Send-HTTPResponse -Context $Context -StatusCode 500 -Body @{
                success = $false
                error = $result.Error
            }
        }
    }
    catch {
        Write-Log "Chat endpoint error: $_" -Level Error
        Send-HTTPResponse -Context $Context -StatusCode 400 -Body @{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# エンドポイント: /api/agents
function Handle-AgentsEndpoint {
    param([HttpListenerContext]$Context)
    
    # GETのみ許可
    if ($Context.Request.HttpMethod -ne "GET") {
        Send-HTTPResponse -Context $Context -StatusCode 405 -Body @{
            error = "Method not allowed"
        }
        return
    }
    
    $agents = @(
        @{
            id = "default"
            name = "汎用アシスタント"
            description = "一般的な質問に答える標準的なAIアシスタント"
            avatar = "/assets/agents/default.png"
            capabilities = @("general", "conversation")
        }
        @{
            id = "technical"
            name = "技術エキスパート"
            description = "プログラミングや技術的な問題に特化"
            avatar = "/assets/agents/technical.png"
            capabilities = @("programming", "debugging", "architecture")
        }
        @{
            id = "creative"
            name = "クリエイティブ・ディレクター"
            description = "創造的なアイデアとコンテンツ生成"
            avatar = "/assets/agents/creative.png"
            capabilities = @("writing", "brainstorming", "design")
        }
        @{
            id = "analytical"
            name = "データアナリスト"
            description = "データ分析と論理的思考"
            avatar = "/assets/agents/analytical.png"
            capabilities = @("analysis", "research", "planning")
        }
    )
    
    Send-HTTPResponse -Context $Context -StatusCode 200 -Body @{
        agents = $agents
        count = $agents.Count
    }
}

# エンドポイント: /api/health
function Handle-HealthEndpoint {
    param([HttpListenerContext]$Context)
    
    $health = @{
        status = "healthy"
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        version = "1.0.0"
        uptime = ((Get-Date) - $script:ServerStartTime).ToString()
        endpoints = @(
            "/api/chat",
            "/api/agents",
            "/api/health",
            "/api/auth/login"
        )
    }
    
    Send-HTTPResponse -Context $Context -StatusCode 200 -Body $health
}

# エンドポイント: /api/auth/login
function Handle-AuthEndpoint {
    param([HttpListenerContext]$Context)
    
    if ($Context.Request.HttpMethod -ne "POST") {
        Send-HTTPResponse -Context $Context -StatusCode 405 -Body @{
            error = "Method not allowed"
        }
        return
    }
    
    $reader = [System.IO.StreamReader]::new($Context.Request.InputStream)
    $requestBody = $reader.ReadToEnd()
    $reader.Close()
    
    try {
        $data = $requestBody | ConvertFrom-Json
        
        # 簡易認証（本番環境では適切な認証実装が必要）
        if ($data.username -and $data.password) {
            $token = New-JWTToken -UserId $data.username
            
            Send-HTTPResponse -Context $Context -StatusCode 200 -Body @{
                success = $true
                token = $token
                expiresIn = 86400
            }
        }
        else {
            throw "ユーザー名とパスワードが必要です"
        }
    }
    catch {
        Send-HTTPResponse -Context $Context -StatusCode 401 -Body @{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# メインリクエストハンドラー
function Handle-Request {
    param([HttpListenerContext]$Context)
    
    $path = $Context.Request.Url.AbsolutePath
    $clientIP = $Context.Request.RemoteEndPoint.Address.ToString()
    
    Write-Log "Request: $($Context.Request.HttpMethod) $path from $clientIP" -Level Info
    
    # レート制限チェック
    if (-not (Test-RateLimit -ClientIP $clientIP)) {
        Send-HTTPResponse -Context $Context -StatusCode 429 -Body @{
            error = "Rate limit exceeded"
        } -Headers @{
            "Retry-After" = "60"
        }
        return
    }
    
    # プリフライトリクエスト処理
    if ($Context.Request.HttpMethod -eq "OPTIONS") {
        Send-HTTPResponse -Context $Context -StatusCode 204 -Body $null
        return
    }
    
    # ルーティング
    switch -Regex ($path) {
        "^/api/chat$" { Handle-ChatEndpoint -Context $Context }
        "^/api/agents$" { Handle-AgentsEndpoint -Context $Context }
        "^/api/health$" { Handle-HealthEndpoint -Context $Context }
        "^/api/auth/login$" { Handle-AuthEndpoint -Context $Context }
        default {
            Send-HTTPResponse -Context $Context -StatusCode 404 -Body @{
                error = "Endpoint not found"
            }
        }
    }
}

# サーバー起動
function Start-APIServer {
    Initialize-APIServer
    
    $script:ServerStartTime = Get-Date
    $listener = [HttpListener]::new()
    $listener.Prefixes.Add("http://+:$($Config.Port)/")
    
    try {
        $listener.Start()
        Write-Log "APIサーバーがポート $($Config.Port) で起動しました" -Level Info
        
        # Ctrl+C でシャットダウン
        [Console]::CancelKeyPress.Add({
            param($sender, $e)
            Write-Log "シャットダウン信号を受信しました" -Level Warning
            $listener.Stop()
            $e.Cancel = $true
        })
        
        # リクエスト処理ループ
        while ($listener.IsListening) {
            try {
                $context = $listener.GetContext()
                
                # 非同期処理
                [System.Threading.ThreadPool]::QueueUserWorkItem({
                    param($ctx)
                    try {
                        Handle-Request -Context $ctx
                    }
                    catch {
                        Write-Log "Request handling error: $_" -Level Error
                    }
                }, $context) | Out-Null
            }
            catch {
                if ($listener.IsListening) {
                    Write-Log "Listener error: $_" -Level Error
                }
            }
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
        Write-Log "APIサーバーが停止しました" -Level Info
    }
}

# エントリーポイント
if ($MyInvocation.InvocationName -ne '.') {
    Start-APIServer
}