# 🤖 Procurement Bot (조달청 데이터 자동 수집기)

## 📌 프로젝트 소개

대한민국 조달청 [조달데이터허브](https://data.g2b.go.kr/)의 '물품 계약 상세내역' 리포트를 자동으로 조회하고 CSV로 다운로드하는 Python 자동화 봇입니다.

공공기관 웹사이트의 복잡한 보안 및 프레임워크(WebSquare, MicroStrategy) 환경을 극복하고, 완전 자동화된 데이터 파이프라인을 구축하기 위해 개발하였습니다.

## 🚀 핵심 기능 (Key Features)

1.  **WebSquare UI 완벽 제어:**
    -   투명 로딩 레이어(`___processbar2`) 자동 감지 및 대기
    -   `ActionChains`를 활용한 마우스 오버(Hover) 메뉴 조작
    -   Javascript Executor를 이용한 강제 클릭(Force Click) 구현
2.  **MSTR 리포트 팝업 자동화:**
    -   동적으로 생성되는 팝업창(New Window) 감지 및 핸들링
    -   '검색' 및 '내보내기' 버튼의 동적 ID/속성 변화 대응 (3중 탐색 로직)
3.  **스마트 다운로드 감지:**
    -   네트워크 속도와 무관하게 파일 다운로드가 완료될 때까지 대기 (`.crdownload` 감시)
    -   다운로드 완료 즉시 데이터 무결성 검증
4.  **일괄 데이터 처리:**
    -   `downloads` 폴더의 모든 CSV 파일을 자동으로 스캔하여 데이터베이스에 저장
    -   처리 완료된 파일은 `completed` 폴더로 자동 이동 (아카이빙)
    -   대용량 데이터를 청크 단위로 분할 처리하여 안정성 확보

## 🛠 기술 스택 (Tech Stack)

-   **Language:** Python 3.12
-   **Browser Automation:** Selenium WebDriver
-   **Data Processing:** Pandas
-   **Environment:** macOS (Apple Silicon M1)

## ⚙️ 실행 방법 (Usage)

### 로컬 환경 (macOS/Windows)

#### 1. 환경 설정

```bash
# 필수 라이브러리 설치
pip install -r requirements.txt
```

#### 2. 실행

**자동 다운로드 및 DB 저장:**

```bash
python main.py
```

**다운로드 폴더의 모든 데이터 일괄 처리:**

```bash
python manual_upload.py --downloads-dir ./downloads --completed-dir ./completed
```

-   `./downloads`의 CSV/XLSX/XLS 파일을 MySQL `procurement_raw`에 적재
-   적재 성공 파일은 `./completed`로 자동 이동
-   파일 단위 트랜잭션 및 적재 로그(`procurement_ingestion_log`) 기록

**옵션 예시:**

```bash
# 중복 제거 옵션 + 실패 시 계속 진행
python manual_upload.py --dedupe-in-file --no-stop-on-fail

# 정규화/검증만 수행 (DB insert 없음)
python manual_upload.py --dry-run
```

> XLSX/XLS 처리를 위해 `openpyxl`/`xlrd` 설치가 필요할 수 있습니다.

---

### ☁️ EC2에서 실행하기

#### 빠른 설정 (자동 스크립트)

```bash
# EC2 인스턴스에 접속 후
chmod +x setup-ec2.sh
./setup-ec2.sh
```

#### 수동 설정

자세한 가이드는 [`setup-ec2.md`](setup-ec2.md) 파일을 참고하세요.

**주요 단계:**

1. Ubuntu 22.04 LTS 인스턴스 생성
2. Chrome 및 ChromeDriver 설치
3. MySQL 설치 및 데이터베이스 생성
4. 프로젝트 파일 업로드
5. Python 가상환경 설정 및 패키지 설치
6. 스크립트 실행

**EC2에서 자동 실행 (Cron):**

```bash
crontab -e
# 매일 새벽 2시 실행 예시
0 2 * * * cd /home/ubuntu/procurement-bot && /home/ubuntu/procurement-bot/venv/bin/python main.py >> /home/ubuntu/procurement-bot/logs/cron.log 2>&1
```

---

## 📝 주요 변경사항 (EC2 지원)

-   ✅ Headless 모드 자동 활성화
-   ✅ EC2/Linux 환경을 위한 Chrome 옵션 추가
-   ✅ 자동 설치 스크립트 제공 (`setup-ec2.sh`)
-   ✅ 상세한 EC2 설정 가이드 제공 (`setup-ec2.md`)
