import time
import os
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.chrome.options import Options

# 1. 파일이 저장될 경로 설정 (현재 폴더/downloads)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DOWNLOAD_DIR = os.path.join(BASE_DIR, "downloads")

if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

# 2. 크롬 옵션 설정
options = Options()
# 다운로드 경로를 위에서 만든 폴더로 강제 지정
prefs = {"download.default_directory": DOWNLOAD_DIR}
options.add_experimental_option("prefs", prefs)
# 브라우저가 자동으로 꺼지지 않게 설정 (테스트용)
options.add_experimental_option("detach", True)

# 3. 브라우저 실행 (M1도 알아서 드라이버 설치해줌)
print("브라우저를 시작합니다...")
service = Service(ChromeDriverManager().install())
driver = webdriver.Chrome(service=service, options=options)

try:
    # 4. 테스트: 구글 접속해보기
    driver.get("https://www.google.com")
    print("구글 접속 성공! 5초 뒤에 종료됩니다.")
    
    # 여기에 나중에 조달청 로그인/다운로드 로직을 넣으면 됩니다.
    
    time.sleep(5) 

except Exception as e:
    print(f"에러 발생: {e}")

finally:
    # 5. 브라우저 종료
    driver.quit()
    print("브라우저가 종료되었습니다.")