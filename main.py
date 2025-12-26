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

# ==========================================
# [설정] 환경 설정
# ==========================================
HOME_URL = "https://data.g2b.go.kr/"

# ==========================================
# [1] 브라우저 및 경로 설정
# ==========================================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DOWNLOAD_DIR = os.path.join(BASE_DIR, "downloads")

if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

# 기존 파일 정리
for f in glob.glob(os.path.join(DOWNLOAD_DIR, "*")):
    try: os.remove(f)
    except: pass

options = Options()
prefs = {"download.default_directory": DOWNLOAD_DIR}
options.add_experimental_option("prefs", prefs)
# options.add_argument("--headless") 

print("🚀 브라우저를 실행합니다...")
service = Service(ChromeDriverManager().install())
driver = webdriver.Chrome(service=service, options=options)
wait = WebDriverWait(driver, 20) 

def js_click(element):
    driver.execute_script("arguments[0].click();", element)

# [NEW] 스마트 다운로드 대기 함수
def wait_for_download_complete(dir_path, timeout=300):
    print(f"⏳ 다운로드 완료 감시 시작 (최대 {timeout}초 대기)...")
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        files = glob.glob(os.path.join(dir_path, "*"))
        # 크롬 임시 파일(.crdownload)이 있는지 확인
        temp_files = [f for f in files if f.endswith('.crdownload') or f.endswith('.tmp')]
        
        # 파일이 존재하고 + 임시 파일이 없으면 + 파일 크기가 0보다 크면 -> 완료!
        if files and not temp_files:
            latest_file = max(files, key=os.path.getctime)
            if os.path.getsize(latest_file) > 0:
                return latest_file
        
        time.sleep(1) # 1초 간격으로 확인
        
    return None

try:
    # ==========================================
    # [Step 1] 메인 페이지 -> 보고서 목록 이동
    # ==========================================
    driver.get(HOME_URL)
    print("🏠 메인 페이지 접속 완료. (10초 대기)")
    time.sleep(10)

    try:
        wait.until(EC.invisibility_of_element_located((By.ID, "___processbar2")))
    except:
        pass

    # 1. '데이터제공' 메뉴
    print("🖱️ '데이터제공' 메뉴 찾는 중...")
    data_menu = wait.until(EC.presence_of_element_located((By.XPATH, "//*[contains(text(), '데이터제공')]")))
    
    actions = ActionChains(driver)
    actions.move_to_element(data_menu).perform()
    print("🖱️ '데이터제공' Hover 완료. (2초 대기)")
    time.sleep(2) 

    # 2. '보고서목록' 클릭
    print("🖱️ '보고서목록' 메뉴 찾는 중...")
    report_list_menu = wait.until(EC.presence_of_element_located((By.XPATH, "//span[contains(text(), '보고서 목록')]")))
    js_click(report_list_menu)
    print("🖱️ '보고서목록' 강제 클릭 실행!")
    time.sleep(5) 

    # ==========================================
    # [Step 2] 원하는 보고서 검색
    # ==========================================
    print("🔍 검색창 찾는 중...")
    search_input = wait.until(EC.presence_of_element_located((By.XPATH, "//input[contains(@id, 'ibxSrchReptNm')]")))
    search_input.clear()
    search_input.send_keys("물품 계약 상세내역")
    search_input.send_keys(Keys.RETURN) 
    print("⌨️ 보고서명 입력 및 엔터 완료")
    time.sleep(3) 

    # 검색 결과 클릭 전 현재 창 핸들 저장
    main_window = driver.current_window_handle
    old_handles = driver.window_handles 
    
    # 보고서 클릭
    target_report = wait.until(EC.element_to_be_clickable((By.XPATH, "//*[text()='물품 계약 상세내역']")))
    js_click(target_report)
    print("🖱️ 보고서 클릭! (상세 페이지 이동)")
    time.sleep(5) 

    # 상세페이지 창 전환
    new_handles = driver.window_handles
    if len(new_handles) > len(old_handles):
        for handle in new_handles:
            if handle not in old_handles:
                driver.switch_to.window(handle)
                print("🔄 상세페이지(새 탭)로 포커스 전환 완료")
                break
    
    # ==========================================
    # [Step 3] 상세 조회 및 CSV 다운로드 버튼 클릭
    # ==========================================
    print("📊 상세 페이지 진입.")
    
    # [검색] 버튼 클릭
    print("🔍 상세 페이지 '검색' 버튼 찾는 중...")
    detail_search_btn = wait.until(EC.presence_of_element_located((By.XPATH, "//input[@value='검색']")))
    js_click(detail_search_btn)
    print("🖱️ 상세 페이지 '검색' 버튼 클릭 성공!")
    
    print("⏳ 데이터 조회 중... (10초 대기)")
    time.sleep(10) 

    # [CSV다운로드] 버튼 클릭
    print("🔍 CSV 다운로드 버튼 찾는 중...")
    csv_down_btn = wait.until(EC.presence_of_element_located((By.ID, "mf_popupCnts_btnCsvDown")))
    
    handles_before_popup = driver.window_handles
    js_click(csv_down_btn)
    print("🖱️ CSV 다운로드 버튼 클릭 성공! (팝업 대기)")

    # ==========================================
    # [Step 4] 팝업창 제어 및 파일 내보내기
    # ==========================================
    print("⏳ 팝업창 생성 감지 중...")
    popup_window = None
    for i in range(10):
        current_handles = driver.window_handles
        new_popups = [h for h in current_handles if h not in handles_before_popup]
        if new_popups:
            popup_window = new_popups[0]
            break
        time.sleep(1)
        
    if not popup_window:
        raise Exception("팝업창이 뜨지 않았습니다.")
        
    driver.switch_to.window(popup_window)
    print(f"✨ 팝업창으로 이동 완료!")
    time.sleep(3) 

    # '내보내기' 버튼 찾기 (3중 안전장치 유지)
    print("🖱️ '내보내기' 버튼 찾는 중...")
    export_btn = None
    try:
        export_btn = WebDriverWait(driver, 5).until(EC.presence_of_element_located((By.XPATH, "//input[@value='내보내기']")))
    except:
        try:
            export_btn = driver.find_element(By.CLASS_NAME, "mstrButton")
        except:
            export_btn = driver.find_element(By.ID, "3131")

    if export_btn:
        js_click(export_btn)
        print("⬇️ 내보내기 버튼 클릭 성공! 다운로드 시작...")
    else:
        raise Exception("내보내기 버튼을 찾을 수 없습니다.")

    # [수정됨] 스마트 다운로드 대기 (최대 5분)
    downloaded_file = wait_for_download_complete(DOWNLOAD_DIR, timeout=300)

    # ==========================================
    # [Step 5] 결과 확인
    # ==========================================
    if downloaded_file:
        print(f"✅ 다운로드 최종 완료: {downloaded_file}")
        
        try:
            df = pd.read_csv(downloaded_file, encoding='cp949')
        except:
            df = pd.read_csv(downloaded_file, encoding='utf-8')
            
        print(f"📋 데이터 로드 성공: 총 {len(df)}건")
        print(df.head()) 
    else:
        print("❌ 타임아웃: 파일 다운로드가 300초 내에 완료되지 않았습니다.")

except Exception as e:
    print(f"❌ 에러 발생: {e}")
    try:
        # 에러 시 디버깅용 화면 출력
        print("--- 현재 화면 정보 ---")
        print(driver.title)
    except: pass

finally:
    print("👋 작업 완료. 5초 후 종료합니다.")
    time.sleep(5)
    driver.quit()