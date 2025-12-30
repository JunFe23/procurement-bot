#!/bin/bash

# EC2 자동 설정 스크립트
# Ubuntu 22.04 LTS 기준

set -e  # 에러 발생 시 스크립트 중단

echo "🚀 EC2 자동 설정을 시작합니다..."

# 1. 시스템 업데이트
echo "📦 시스템 패키지 업데이트 중..."
sudo apt update && sudo apt upgrade -y

# 2. Python 3 및 pip 설치
echo "🐍 Python 3 설치 중..."
sudo apt install -y python3 python3-pip python3-venv

# 3. 필수 유틸리티 설치
echo "🔧 필수 유틸리티 설치 중..."
sudo apt install -y wget curl unzip gnupg2 git

# 4. Chrome 설치
echo "🌐 Google Chrome 설치 중..."
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install -y google-chrome-stable

# Chrome 버전 확인
echo "✅ Chrome 설치 완료: $(google-chrome --version)"

# 5. MySQL 설치
echo "🗄️ MySQL 설치 중..."
sudo apt install -y mysql-server

# MySQL 시작 및 자동 시작 설정
sudo systemctl start mysql
sudo systemctl enable mysql

# MySQL 초기 설정 (비밀번호 없이 root 계정 사용)
echo "📝 MySQL 데이터베이스 설정 중..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS g2b CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || true
sudo mysql -e "CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '';" || true
sudo mysql -e "GRANT ALL PRIVILEGES ON g2b.* TO 'root'@'localhost';" || true
sudo mysql -e "FLUSH PRIVILEGES;" || true

# 6. 프로젝트 디렉토리 확인
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

echo "📁 프로젝트 디렉토리: $PROJECT_DIR"
cd "$PROJECT_DIR"

# 7. Python 가상환경 생성
echo "🔨 Python 가상환경 생성 중..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✅ 가상환경 생성 완료"
else
    echo "ℹ️ 가상환경이 이미 존재합니다"
fi

# 8. 가상환경 활성화 및 패키지 설치
echo "📚 Python 패키지 설치 중..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 9. 다운로드 디렉토리 생성
echo "📂 다운로드 디렉토리 생성 중..."
mkdir -p downloads
mkdir -p logs

# 10. 권한 설정
echo "🔐 파일 권한 설정 중..."
chmod +x main.py

# 11. 설정 완료
echo ""
echo "✅ =========================================="
echo "✅ EC2 설정이 완료되었습니다!"
echo "✅ =========================================="
echo ""
echo "📋 다음 단계:"
echo "   1. 가상환경 활성화: source venv/bin/activate"
echo "   2. 스크립트 실행: python main.py"
echo ""
echo "💡 자동 실행 설정 (cron):"
echo "   crontab -e"
echo "   # 매일 새벽 2시 실행 예시:"
echo "   0 2 * * * cd $PROJECT_DIR && $PROJECT_DIR/venv/bin/python main.py >> $PROJECT_DIR/logs/cron.log 2>&1"
echo ""

