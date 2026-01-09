import pandas as pd
from sqlalchemy import create_engine, text
import os
import time
import glob
import shutil  # 파일을 이동시키기 위한 도구

# =========================================================
# [설정]
# =========================================================
# 1. 경로 설정
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DOWNLOAD_DIR = os.path.join(BASE_DIR, "downloads")     # 작업할 파일이 있는 곳
COMPLETED_DIR = os.path.join(BASE_DIR, "completed")    # 처리가 끝난 파일을 옮겨둘 곳

# 2. DB 접속 정보
DB_CONNECTION_STR = "mysql+pymysql://root:@localhost:3306/g2b"
TABLE_NAME = "procurement_table"

# 3. 조달청 CSV 포맷 설정
ENCODING = 'utf-16' 
SEPARATOR = '\t'    
SKIP_ROWS = 28      
CHUNK_SIZE = 10000 
# =========================================================

def upload_and_archive_files():
    # 0. 완료 폴더가 없으면 생성
    if not os.path.exists(COMPLETED_DIR):
        os.makedirs(COMPLETED_DIR)
        print(f"📁 '{COMPLETED_DIR}' 폴더를 생성했습니다.")

    # 1. 다운로드 폴더의 모든 CSV 파일 탐색
    files = glob.glob(os.path.join(DOWNLOAD_DIR, "*.csv"))
    files.sort() # 연도순(이름순) 처리

    if not files:
        print(f"📭 '{DOWNLOAD_DIR}' 폴더에 처리할 CSV 파일이 없습니다.")
        return

    print(f"🚀 총 {len(files)}개의 신규 파일을 발견했습니다.")
    print(f"   (처리 완료된 파일은 '{COMPLETED_DIR}'로 자동 이동됩니다)")
    
    engine = create_engine(DB_CONNECTION_STR)
    conn = engine.connect()

    # [안전장치] DB 컬럼 타입 변경 (VARCHAR로 확보)
    try:
        conn.execute(text(f"ALTER TABLE {TABLE_NAME} MODIFY COLUMN 업체사업자등록번호 VARCHAR(50)"))
        conn.execute(text(f"ALTER TABLE {TABLE_NAME} MODIFY COLUMN 입찰공고번호 VARCHAR(50)"))
    except:
        pass # 이미 되어있으면 패스

    # 2. 파일 반복 처리
    for idx, file_path in enumerate(files):
        file_name = os.path.basename(file_path)
        print(f"\n==================================================")
        print(f"[{idx+1}/{len(files)}] 처리 시작: {file_name}")
        print(f"==================================================")
        
        start_time = time.time()
        file_rows = 0
        is_success = False # 성공 여부 플래그
        
        try:
            # [핵심] dtype 설정으로 데이터 타입 에러 방지
            chunk_iterator = pd.read_csv(
                file_path,
                encoding=ENCODING,
                sep=SEPARATOR,
                skiprows=SKIP_ROWS,
                low_memory=False,
                thousands=',',
                chunksize=CHUNK_SIZE,
                dtype={
                    '업체사업자등록번호': str, # F가 섞인 번호 처리
                    '입찰공고번호': str,     # 2017-01 형태 처리
                    '계약번호': str,
                    '수요기관코드': str,
                    '물품분류번호': str,
                    '세부품명번호': str,
                    '물품식별번호': str,
                    '참조번호': str
                }
            )

            for chunk in chunk_iterator:
                if chunk.empty: continue
                
                # DB에 데이터 추가 (append)
                chunk.to_sql(name=TABLE_NAME, con=engine, if_exists='append', index=False)
                file_rows += len(chunk)
                print(f"   ↳ {len(chunk)}건 저장... (누적 {file_rows}건)")
            
            duration = time.time() - start_time
            print(f"✅ DB 적재 완료 ({duration:.1f}초, {file_rows}건)")
            is_success = True

        except Exception as e:
            print(f"❌ 처리 실패: {e}")
            is_success = False

        # 3. 성공 시 파일 이동 (Archive)
        if is_success:
            try:
                destination = os.path.join(COMPLETED_DIR, file_name)
                # 혹시 완료 폴더에 이미 같은 이름이 있으면 덮어쓰기 위해 삭제 후 이동
                if os.path.exists(destination):
                    os.remove(destination)
                
                shutil.move(file_path, destination)
                print(f"📦 파일 이동 완료: downloads -> completed/{file_name}")
            except Exception as move_error:
                print(f"⚠️ DB 저장은 성공했으나 파일 이동 실패: {move_error}")

    conn.close()
    print("\n🎉 모든 작업 종료!")

if __name__ == "__main__":
    upload_and_archive_files()