@echo off
echo MCP Agent System - Gemini対応サーバー起動中...

rem 環境変数設定（実際のAPIキーに置き換えてください）
set GEMINI_API_KEY=your_gemini_api_key_here
set JWT_SECRET=mcp-agent-jwt-secret-gemini-2024

rem Google AI Studio でAPIキーを取得: https://makersuite.google.com/app/apikey

rem PowerShell実行ポリシー設定
powershell.exe -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"

rem APIサーバー起動
echo Gemini対応PowerShell APIサーバーを起動しています...
echo Provider: Google Gemini Pro
powershell.exe -File backend\api.ps1

pause