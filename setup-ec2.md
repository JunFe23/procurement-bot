# 🚀 EC2에서 실행하기 가이드

## 1. EC2 인스턴스 준비

### 권장 사양
- **OS**: Ubuntu 22.04 LTS (또는 Amazon Linux 2023)
- **인스턴스 타입**: t3.small 이상 (최소 2GB RAM)
- **스토리지**: 20GB 이상

### 보안 그룹 설정
- **인바운드 규칙**: SSH (22번 포트)만 열어두면 됩니다.
- MySQL은 로컬에서만 접근하거나, 외부 접근이 필요하면 3306 포트를 추가하세요.

---

## 2. EC2 접속 및 초기 설정

```bash
# EC2 인스턴스에 SSH 접속
ssh -i your-key.pem ubuntu@your-ec2-ip

# 시스템 업데이트
sudo apt update && sudo apt upgrade -y
```

---

## 3. 필수 패키지 설치

### Ubuntu/Debian 계열
```bash
# Python 3 및 pip 설치
sudo apt install -y python3 python3-pip python3-venv

# Chrome 및 ChromeDriver를 위한 의존성
sudo apt install -y wget curl unzip gnupg2

# Chrome 설치
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install -y google-chrome-stable

# ChromeDriver는 webdriver-manager가 자동으로 설치하지만, 수동 설치도 가능:
# CHROMEDRIVER_VERSION=$(curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE)
# wget -O /tmp/chromedriver.zip https://chromedriver.storage.googleapis.com/$CHROMEDRIVER_VERSION/chromedriver_linux64.zip
# sudo unzip /tmp/chromedriver.zip -d /usr/local/bin/
# sudo chmod +x /usr/local/bin/chromedriver
```

### Amazon Linux 2023
```bash
# Python 3 설치
sudo dnf install -y python3 python3-pip

# Chrome 설치
sudo dnf install -y wget curl unzip
wget https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
sudo dnf install -y ./google-chrome-stable_current_x86_64.rpm
```

---

## 4. MySQL 설치 및 설정

```bash
# MySQL 설치 (Ubuntu)
sudo apt install -y mysql-server

# MySQL 시작 및 자동 시작 설정
sudo systemctl start mysql
sudo systemctl enable mysql

# MySQL 보안 설정 (비밀번호 설정)
sudo mysql_secure_installation

# 데이터베이스 및 사용자 생성
sudo mysql -u root -p << EOF
CREATE DATABASE IF NOT EXISTS g2b CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON g2b.* TO 'root'@'localhost';
FLUSH PRIVILEGES;
EOF
```

---

## 5. 프로젝트 배포

```bash
# 프로젝트 디렉토리 생성
mkdir -p ~/procurement-bot
cd ~/procurement-bot

# 프로젝트 파일 업로드 방법 (로컬에서 실행)
# scp -i your-key.pem -r /path/to/procurement-bot/* ubuntu@your-ec2-ip:~/procurement-bot/

# 또는 Git 사용
# git clone your-repo-url .
```

---

## 6. Python 환경 설정

```bash
# 가상환경 생성 및 활성화
python3 -m venv venv
source venv/bin/activate

# 패키지 설치
pip install --upgrade pip
pip install -r requirements.txt
```

---

## 7. 실행 테스트

```bash
# 가상환경 활성화 (매번 실행 전)
source venv/bin/activate

# 스크립트 실행
python main.py
```

---

## 8. 자동 실행 설정 (Cron)

정기적으로 실행하려면 cron을 설정하세요:

```bash
# crontab 편집
crontab -e

# 예시: 매일 새벽 2시에 실행
0 2 * * * cd /home/ubuntu/procurement-bot && /home/ubuntu/procurement-bot/venv/bin/python main.py >> /home/ubuntu/procurement-bot/logs/cron.log 2>&1

# 또는 매주 월요일 오전 9시
0 9 * * 1 cd /home/ubuntu/procurement-bot && /home/ubuntu/procurement-bot/venv/bin/python main.py >> /home/ubuntu/procurement-bot/logs/cron.log 2>&1
```

로그 디렉토리 생성:
```bash
mkdir -p ~/procurement-bot/logs
```

---

## 9. 문제 해결

### Chrome 실행 오류
```bash
# Chrome 버전 확인
google-chrome --version

# ChromeDriver 버전 확인
chromedriver --version
```

### 메모리 부족 오류
- 인스턴스 타입을 더 큰 것으로 업그레이드 (t3.medium 이상)
- 또는 swap 메모리 추가:
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### MySQL 연결 오류
```bash
# MySQL 상태 확인
sudo systemctl status mysql

# MySQL 재시작
sudo systemctl restart mysql
```

---

## 10. 모니터링

실행 로그 확인:
```bash
# 실시간 로그 확인
tail -f ~/procurement-bot/logs/cron.log

# 또는 직접 실행 시 출력 확인
python main.py
```

---

## 📝 참고사항

- **비용 최적화**: EC2 인스턴스를 사용하지 않을 때는 중지(Stop)하세요.
- **보안**: MySQL root 비밀번호를 설정하는 것을 권장합니다.
- **백업**: 정기적으로 데이터베이스를 백업하세요.

