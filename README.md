# 🤖 Procurement Bot (조달청 데이터 자동 수집기)

## 📌 프로젝트 소개

대한민국 조달청 [조달데이터허브](https://data.g2b.go.kr/)의 '물품 계약 상세내역' 리포트를 자동으로 조회하고 CSV로 다운로드하는 Python 자동화 봇입니다.

공공기관 웹사이트의 복잡한 보안 및 프레임워크(WebSquare, MicroStrategy) 환경을 극복하고, 완전 자동화된 데이터 파이프라인을 구축하기 위해 개발되었습니다.

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

## 🛠 기술 스택 (Tech Stack)

-   **Language:** Python 3.12
-   **Browser Automation:** Selenium WebDriver
-   **Data Processing:** Pandas
-   **Environment:** macOS (Apple Silicon M1)

## ⚙️ 실행 방법 (Usage)

### 1. 환경 설정

```bash
# 필수 라이브러리 설치
pip install -r requirements.txt
```
