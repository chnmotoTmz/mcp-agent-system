#!/bin/bash

# AWS環境セットアップスクリプト
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
AWS_REGION="${2:-us-east-1}"
STACK_NAME="$APP_NAME-stack"

print_color "green" "🚀 AWS環境セットアップを開始します..."

# AWS CLI の確認
if ! command -v aws &> /dev/null; then
    print_color "red" "❌ AWS CLI がインストールされていません"
    print_color "yellow" "インストール手順: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# AWS CLI 設定確認
print_color "yellow" "📋 AWS CLI の設定を確認中..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_color "red" "❌ AWS CLI が設定されていません"
    print_color "yellow" "aws configure を実行してください"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
CURRENT_USER=$(aws sts get-caller-identity --query "Arn" --output text)
print_color "green" "✅ AWS CLI設定確認: $CURRENT_USER"
print_color "cyan" "📊 アカウントID: $ACCOUNT_ID"

# CloudFormation テンプレート作成
print_color "yellow" "📄 CloudFormation テンプレートを作成中..."

cat > /tmp/mcp-agent-cloudformation.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'MCP Agent System - AWS Infrastructure'

Parameters:
  AppName:
    Type: String
    Default: mcp-agent-system
    Description: Application name
  
  Environment:
    Type: String
    Default: prod
    AllowedValues: [dev, staging, prod]
    Description: Environment name

Resources:
  # S3 Bucket for Frontend
  FrontendBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${AppName}-frontend-${AWS::AccountId}'
      WebsiteConfiguration:
        IndexDocument: index.html
        ErrorDocument: index.html
      PublicAccessBlockConfiguration:
        BlockPublicAcls: false
        BlockPublicPolicy: false
        IgnorePublicAcls: false
        RestrictPublicBuckets: false
      CorsConfiguration:
        CorsRules:
          - AllowedHeaders: ['*']
            AllowedMethods: [GET, HEAD]
            AllowedOrigins: ['*']
            MaxAge: 3600

  # S3 Bucket Policy
  FrontendBucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref FrontendBucket
      PolicyDocument:
        Statement:
          - Sid: PublicReadGetObject
            Effect: Allow
            Principal: '*'
            Action: s3:GetObject
            Resource: !Sub '${FrontendBucket}/*'

  # CloudFront Distribution
  CloudFrontDistribution:
    Type: AWS::CloudFront::Distribution
    Properties:
      DistributionConfig:
        Origins:
          - Id: S3Origin
            DomainName: !GetAtt FrontendBucket.DomainName
            S3OriginConfig:
              OriginAccessIdentity: ''
        DefaultCacheBehavior:
          TargetOriginId: S3Origin
          ViewerProtocolPolicy: redirect-to-https
          Compress: true
          ForwardedValues:
            QueryString: false
            Cookies:
              Forward: none
        Enabled: true
        DefaultRootObject: index.html
        CustomErrorResponses:
          - ErrorCode: 404
            ResponseCode: 200
            ResponsePagePath: /index.html
          - ErrorCode: 403
            ResponseCode: 200
            ResponsePagePath: /index.html
        PriceClass: PriceClass_100

  # Lambda Execution Role
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${AppName}-lambda-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        - arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
      Policies:
        - PolicyName: SecretsManagerAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - secretsmanager:GetSecretValue
                Resource: !Ref OpenAISecrets

  # Lambda Function for Backend
  BackendLambda:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${AppName}-backend'
      Runtime: provided.al2
      Handler: lambda-handler.ps1
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          # Placeholder - actual code will be deployed via CI/CD
          Write-Host "Lambda function placeholder"
      Environment:
        Variables:
          OPENAI_SECRET_ARN: !Ref OpenAISecrets
          ENVIRONMENT: !Ref Environment
      TracingConfig:
        Mode: Active
      Timeout: 30
      MemorySize: 512

  # API Gateway
  ApiGateway:
    Type: AWS::ApiGatewayV2::Api
    Properties:
      Name: !Sub '${AppName}-api'
      ProtocolType: HTTP
      CorsConfiguration:
        AllowOrigins:
          - '*'
        AllowMethods:
          - GET
          - POST
          - OPTIONS
        AllowHeaders:
          - Content-Type
          - Authorization
        MaxAge: 86400

  # API Gateway Integration
  ApiIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref ApiGateway
      IntegrationType: AWS_PROXY
      IntegrationUri: !Sub 'arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${BackendLambda.Arn}/invocations'
      PayloadFormatVersion: '2.0'

  # API Gateway Routes
  ApiRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref ApiGateway
      RouteKey: 'ANY /api/{proxy+}'
      Target: !Sub 'integrations/${ApiIntegration}'

  # API Gateway Stage
  ApiStage:
    Type: AWS::ApiGatewayV2::Stage
    Properties:
      ApiId: !Ref ApiGateway
      StageName: prod
      AutoDeploy: true

  # Lambda Permission for API Gateway
  LambdaPermission:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref BackendLambda
      Action: lambda:InvokeFunction
      Principal: apigateway.amazonaws.com
      SourceArn: !Sub '${ApiGateway}/*/*'

  # Secrets Manager for OpenAI API Key
  OpenAISecrets:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub '${AppName}/openai'
      Description: 'OpenAI API Key and other secrets'
      SecretString: !Sub |
        {
          "OPENAI_API_KEY": "your_openai_api_key_here",
          "JWT_SECRET": "your_jwt_secret_here"
        }

  # CloudWatch Log Group
  LambdaLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/aws/lambda/${AppName}-backend'
      RetentionInDays: 14

Outputs:
  FrontendBucketName:
    Description: 'S3 Bucket for frontend'
    Value: !Ref FrontendBucket
    Export:
      Name: !Sub '${AWS::StackName}-FrontendBucket'

  CloudFrontURL:
    Description: 'CloudFront Distribution URL'
    Value: !Sub 'https://${CloudFrontDistribution.DomainName}'
    Export:
      Name: !Sub '${AWS::StackName}-CloudFrontURL'

  ApiGatewayURL:
    Description: 'API Gateway URL'
    Value: !Sub 'https://${ApiGateway}.execute-api.${AWS::Region}.amazonaws.com/prod'
    Export:
      Name: !Sub '${AWS::StackName}-ApiURL'

  LambdaFunctionName:
    Description: 'Lambda Function Name'
    Value: !Ref BackendLambda
    Export:
      Name: !Sub '${AWS::StackName}-LambdaFunction'

  SecretsManagerArn:
    Description: 'Secrets Manager ARN'
    Value: !Ref OpenAISecrets
    Export:
      Name: !Sub '${AWS::StackName}-SecretsArn'
EOF

# CloudFormation スタックをデプロイ
print_color "yellow" "☁️  CloudFormation スタックをデプロイ中..."

if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
    print_color "yellow" "⚠️  スタック '$STACK_NAME' は既に存在します。更新します..."
    aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --template-body file:///tmp/mcp-agent-cloudformation.yaml \
        --parameters ParameterKey=AppName,ParameterValue="$APP_NAME" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION"
else
    print_color "yellow" "📦 新しいスタック '$STACK_NAME' を作成中..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body file:///tmp/mcp-agent-cloudformation.yaml \
        --parameters ParameterKey=AppName,ParameterValue="$APP_NAME" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION"
fi

# スタック作成完了待機
print_color "yellow" "⏳ スタックの作成/更新完了を待機中..."
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" 2>/dev/null || \
aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" 2>/dev/null

# 出力値取得
print_color "green" "✅ スタックが正常に作成/更新されました"

FRONTEND_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='FrontendBucketName'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CloudFrontURL'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

API_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayURL'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='LambdaFunctionName'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

SECRETS_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='SecretsManagerArn'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

# Lambda Layer for PowerShell作成
print_color "yellow" "⚡ PowerShell Lambda Layer を作成中..."

mkdir -p /tmp/lambda-layer/pwsh
cd /tmp/lambda-layer

# PowerShell Core をダウンロード
curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.3.0/powershell-7.3.0-linux-x64.tar.gz -o powershell.tar.gz
tar -xzf powershell.tar.gz -C pwsh/

# Layer ZIP作成
zip -r powershell-layer.zip pwsh/

# Layer 公開
LAYER_ARN=$(aws lambda publish-layer-version \
    --layer-name "$APP_NAME-powershell" \
    --zip-file fileb://powershell-layer.zip \
    --compatible-runtimes provided.al2 \
    --query "LayerArn" \
    --output text \
    --region "$AWS_REGION")

print_color "green" "✅ PowerShell Layer作成完了: $LAYER_ARN"

# Lambda関数にLayer追加
aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION" \
    --layers "$LAYER_ARN" \
    --region "$AWS_REGION"

# IAMユーザー作成（CI/CD用）
print_color "yellow" "👤 CI/CD用IAMユーザーを作成中..."

USER_NAME="$APP_NAME-ci-user"

if aws iam get-user --user-name "$USER_NAME" &> /dev/null; then
    print_color "yellow" "⚠️  IAMユーザー '$USER_NAME' は既に存在します"
else
    aws iam create-user --user-name "$USER_NAME"
    print_color "green" "✅ IAMユーザー '$USER_NAME' を作成しました"
fi

# CI/CD用ポリシー作成
cat > /tmp/ci-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:UpdateFunctionCode",
                "lambda:UpdateFunctionConfiguration",
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:DeleteObject",
                "s3:ListBucket",
                "cloudfront:CreateInvalidation"
            ],
            "Resource": [
                "arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:$LAMBDA_FUNCTION",
                "arn:aws:s3:::$FRONTEND_BUCKET",
                "arn:aws:s3:::$FRONTEND_BUCKET/*",
                "arn:aws:cloudfront::$ACCOUNT_ID:distribution/*"
            ]
        }
    ]
}
EOF

POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$APP_NAME-ci-policy"

if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document file:///tmp/ci-policy.json \
        --set-as-default
else
    aws iam create-policy \
        --policy-name "$APP_NAME-ci-policy" \
        --policy-document file:///tmp/ci-policy.json
fi

# ポリシーをユーザーにアタッチ
aws iam attach-user-policy \
    --user-name "$USER_NAME" \
    --policy-arn "$POLICY_ARN"

# アクセスキー作成
if ! aws iam list-access-keys --user-name "$USER_NAME" --query "AccessKeyMetadata[0].AccessKeyId" --output text | grep -q "AKIA"; then
    ACCESS_KEY_RESULT=$(aws iam create-access-key --user-name "$USER_NAME")
    ACCESS_KEY_ID=$(echo "$ACCESS_KEY_RESULT" | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_RESULT" | jq -r '.AccessKey.SecretAccessKey')
    
    print_color "green" "✅ アクセスキーを作成しました"
    print_color "yellow" "🔑 GitHub Secrets 設定情報:"
    echo "AWS_ACCESS_KEY_ID: $ACCESS_KEY_ID"
    echo "AWS_SECRET_ACCESS_KEY: $SECRET_ACCESS_KEY"
else
    print_color "yellow" "⚠️  アクセスキーは既に存在します"
fi

# 結果表示
print_color "cyan" "🌐 デプロイメント情報"
echo "Frontend Bucket: $FRONTEND_BUCKET"
echo "CloudFront URL: $CLOUDFRONT_URL"
echo "API Gateway URL: $API_URL"
echo "Lambda Function: $LAMBDA_FUNCTION"
echo "Secrets Manager: $SECRETS_ARN"

print_color "cyan" "📋 GitHub Secrets 設定"
echo "AWS_REGION: $AWS_REGION"
echo "AWS_S3_BUCKET: $FRONTEND_BUCKET"
echo "AWS_LAMBDA_FUNCTION_NAME: $LAMBDA_FUNCTION"

# CloudFront Distribution ID取得
DISTRIBUTION_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment==''].Id" \
    --output text)

if [ -n "$DISTRIBUTION_ID" ]; then
    echo "AWS_CLOUDFRONT_DISTRIBUTION_ID: $DISTRIBUTION_ID"
fi

print_color "cyan" "📝 次のステップ"
echo "1. Secrets Manager でOpenAI API Keyを設定:"
echo "   aws secretsmanager update-secret --secret-id $SECRETS_ARN --secret-string '{\"OPENAI_API_KEY\":\"your_key_here\",\"JWT_SECRET\":\"your_secret_here\"}'"
echo "2. GitHub Secrets を設定"
echo "3. GitHub Actions でデプロイメント実行"

print_color "green" "🎉 AWS環境セットアップが完了しました!"

# 一時ファイル削除
rm -f /tmp/mcp-agent-cloudformation.yaml /tmp/ci-policy.json
rm -rf /tmp/lambda-layer