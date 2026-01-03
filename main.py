import time
import os
import glob
import pandas as pd
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
from sqlalchemy import create_engine

# ==========================================
# [설정] 환경 및 DB 설정
# ==========================================
HOME_URL = "https://data.g2b.go.kr/"
DB_CONNECTION_STR = "mysql+pymysql://root:@localhost:3306/g2b"
TABLE_NAME = "procurement_table"

# ==========================================
# [1] 브라우저 및 경로 설정
# ==========================================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DOWNLOAD_DIR = os.path.join(BASE_DIR, "downloads")

if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

# [옵션] EC2/Headless 환경 맞춤 설정 (팝업 허용 강화)
options = Options()

# 1. 팝업 및 다운로드 관련 강력한 허용 설정
prefs = {
    "download.default_directory": DOWNLOAD_DIR,
    "download.prompt_for_download": False,
    "download.directory_upgrade": True,
    "safebrowsing.enabled": True,
    "profile.default_content_settings.popups": 0,  # 팝업 차단 해제 (0: 허용)
    "profile.default_content_setting_values.automatic_downloads": 1, # 자동 다운로드 허용
    "profile.content_settings.exceptions.automatic_downloads.*.setting": 1
}
options.add_experimental_option("prefs", prefs)

# 2. Headless 및 User-Agent 설정
options.add_argument("--headless")  
options.add_argument("--no-sandbox") 
options.add_argument("--disable-dev-shm-usage")
options.add_argument("--window-size=1920,1080")
options.add_argument("--disable-gpu")
# [중요] 사람인 척 속이기 (User-Agent 설정)
options.add_argument("user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
options.add_argument("--disable-blink-features=AutomationControlled") 

print("🚀 Headless 브라우저를 실행합니다... (팝업 허용 모드)")
service = Service(ChromeDriverManager().install())
driver = webdriver.Chrome(service=service, options=options)
wait = WebDriverWait(driver, 20) 

def js_click(element):
    driver.execute_script("arguments[0].click();", element)

# [디버깅용] 스크린샷 함수
def save_screenshot(filename):
    path = os.path.join(BASE_DIR, filename)
    driver.save_screenshot(path)
    print(f"📸 화면 저장: {filename}")

def wait_for_download_complete(dir_path, timeout=300):
    print(f"⏳ 다운로드 완료 감시 시작 (최대 {timeout}초 대기)...")
    start_time = time.time()
    while time.time() - start_time < timeout:
        files = glob.glob(os.path.join(dir_path, "*"))
        temp_files = [f for f in files if f.endswith('.crdownload') or f.endswith('.tmp')]
        if files and not temp_files:
            latest_file = max(files, key=os.path.getctime)
            if os.path.getsize(latest_file) > 0:
                return latest_file
        time.sleep(1) 
    return None

try:
    # Step 1
    driver.get(HOME_URL)
    print("🏠 메인 페이지 접속 완료. (10초 대기)")
    time.sleep(10)

    try:
        wait.until(EC.invisibility_of_element_located((By.ID, "___processbar2")))
    except:
        pass

    print("🖱️ '데이터제공' 메뉴 이동...")
    data_menu = wait.until(EC.presence_of_element_located((By.XPATH, "//*[contains(text(), '데이터제공')]")))
    ActionChains(driver).move_to_element(data_menu).perform()
    time.sleep(2) 

    print("🖱️ '보고서목록' 클릭...")
    report_list_menu = wait.until(EC.presence_of_element_located((By.XPATH, "//span[contains(text(), '보고서 목록')]")))
    js_click(report_list_menu)
    time.sleep(5) 

    print("🔍 보고서 검색...")
    search_input = wait.until(EC.presence_of_element_located((By.XPATH, "//input[contains(@id, 'ibxSrchReptNm')]")))
    search_input.clear()
    search_input.send_keys("물품 계약 상세내역")
    search_input.send_keys(Keys.RETURN) 
    time.sleep(3) 

    target_report = wait.until(EC.element_to_be_clickable((By.XPATH, "//*[text()='물품 계약 상세내역']")))
    handles_before_click = driver.window_handles
    js_click(target_report)
    print("🖱️ 보고서 클릭! (상세 페이지 이동)")
    time.sleep(5) 

    new_handles = driver.window_handles
    if len(new_handles) > len(handles_before_click):
        for handle in new_handles:
            if handle not in handles_before_click:
                driver.switch_to.window(handle)
                break
    
    print("📊 상세 페이지 진입. 데이터 조회 시작...")
    detail_search_btn = wait.until(EC.presence_of_element_located((By.XPATH, "//input[@value='검색']")))
    js_click(detail_search_btn)
    
    print("⏳ 조회 중... (10초 대기)")
    time.sleep(10) 
    save_screenshot("step3_search_complete.png")

    print("🔍 CSV 다운로드 버튼 클릭...")
    csv_down_btn = wait.until(EC.presence_of_element_located((By.ID, "mf_popupCnts_btnCsvDown")))
    
    # [중요] 팝업 뜨기 전 핸들 저장
    handles_before_popup = driver.window_handles
    
    # 버튼이 화면에 확실히 보이도록 스크롤 (Headless 안전장치)
    driver.execute_script("arguments[0].scrollIntoView(true);", csv_down_btn)
    time.sleep(1)
    js_click(csv_down_btn)
    print("🖱️ CSV 버튼 클릭함! 팝업 대기중...")

    # [수정] 팝업 감지 로직 강화
    popup_window = None
    for i in range(15): # 대기 시간 15초로 연장
        current_handles = driver.window_handles
        new_popups = [h for h in current_handles if h not in handles_before_popup]
        if new_popups:
            popup_window = new_popups[0]
            print(f"✨ 팝업 발견! (시도 {i+1}회)")
            break
        time.sleep(1)
        
    if not popup_window:
        # 실패 시 현재 화면 저장
        save_screenshot("error_no_popup.png")
        raise Exception("팝업창 미발견")
        
    driver.switch_to.window(popup_window)
    time.sleep(3) 
    save_screenshot("step4_popup_opened.png")

    print("⬇️ 내보내기 버튼 클릭...")
    export_btn = None
    try: export_btn = WebDriverWait(driver, 5).until(EC.presence_of_element_located((By.XPATH, "//input[@value='내보내기']")))
    except: export_btn = driver.find_element(By.ID, "3131")

    if export_btn:
        js_click(export_btn)
        time.sleep(5)
    else:
        save_screenshot("error_no_export_btn.png")
        raise Exception("내보내기 버튼 없음")

    downloaded_file = wait_for_download_complete(DOWNLOAD_DIR, timeout=300)

    # ==========================================
    # [Step 5] DB 저장
    # ==========================================
    if downloaded_file:
        print(f"✅ 다운로드 완료: {downloaded_file}")
        
        print("📖 데이터 파일 읽는 중...")
        try:
            df = pd.read_csv(
                downloaded_file, 
                encoding='utf-16', 
                sep='\t', 
                skiprows=28, 
                low_memory=False,
                thousands=','
            )
            print(f"📋 데이터 로드 성공: 총 {len(df)}건")
            
            print(f"💾 g2b 데이터베이스에 저장 시작...")
            engine = create_engine(DB_CONNECTION_STR)
            conn = engine.connect()
            
            df.to_sql(name=TABLE_NAME, con=engine, if_exists='replace', index=False, chunksize=1000)
            
            print(f"🎉 대성공! {len(df)}건 저장 완료!")
            conn.close()
            
        except Exception as e:
            print(f"❌ 데이터 처리 실패: {e}")

    else:
        print("❌ 타임아웃: 파일이 다운로드되지 않았습니다.")

except Exception as e:
    print(f"❌ 에러 발생: {e}")
    save_screenshot("final_error.png")

finally:
    print("👋 작업 완료. 5초 후 종료합니다.")
    time.sleep(5)
    driver.quit()