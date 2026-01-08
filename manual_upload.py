import pandas as pd
from sqlalchemy import create_engine
import os
import time

# =========================================================
# [설정] 파일 경로와 DB 정보만 수정하세요
# =========================================================
# 1. 수동으로 넣을 CSV 파일 경로 (절대 경로 추천)
TARGET_FILE = "/Users/junfe/Desktop/G2B/procurement-bot/downloads/2017년_물품계약.csv" 

# 2. DB 접속 정보 (비밀번호 없으면 root:@localhost)
DB_CONNECTION_STR = "mysql+pymysql://root:@localhost:3306/g2b"
TABLE_NAME = "procurement_table"

# 3. 조달청 파일 포맷 설정 (2017년도 동일하다고 가정)
ENCODING = 'utf-16' # 안 되면 'cp949' 또는 'euc-kr' 시도
SEPARATOR = '\t'    # 탭 구분
SKIP_ROWS = 28      # 상단 불필요한 행 개수
CHUNK_SIZE = 10000  # 한 번에 처리할 행 개수 (메모리 보호용)

# =========================================================

def upload_large_csv():
    if not os.path.exists(TARGET_FILE):
        print(f"❌ 파일을 찾을 수 없습니다: {TARGET_FILE}")
        return

    print(f"🚀 대용량 CSV 적재 시작: {TARGET_FILE}")
    print(f"💾 대상 테이블: {TABLE_NAME}")
    
    engine = create_engine(DB_CONNECTION_STR)
    conn = engine.connect()

    total_rows = 0
    start_time = time.time()

    try:
        # chunksize 옵션을 쓰면 파일 전체를 읽지 않고 조금씩 읽어옵니다.
        chunk_iterator = pd.read_csv(
            TARGET_FILE,
            encoding=ENCODING,
            sep=SEPARATOR,
            skiprows=SKIP_ROWS,
            low_memory=False,
            thousands=',',
            chunksize=CHUNK_SIZE # 핵심!
        )

        for i, df_chunk in enumerate(chunk_iterator):
            # 데이터가 비어있으면 패스
            if df_chunk.empty:
                continue

            # DB에 추가 (append)
            df_chunk.to_sql(
                name=TABLE_NAME,
                con=engine,
                if_exists='append', # 기존 데이터 뒤에 붙이기
                index=False
            )
            
            rows = len(df_chunk)
            total_rows += rows
            print(f"✅ Chunk {i+1} 완료: {rows}건 저장 (누적 {total_rows}건)")

        duration = time.time() - start_time
        print(f"\n🎉 모든 작업 완료!")
        print(f"총 소요 시간: {duration:.2f}초")
        print(f"총 저장된 데이터: {total_rows}건")

    except Exception as e:
        print(f"\n❌ 에러 발생: {e}")
        print("팁: 인코딩 문제라면 encoding 옵션을 'cp949'로 바꿔보세요.")
        print("팁: 데이터가 29번째 줄부터 시작하지 않는다면 skiprows 숫자를 조절하세요.")

    finally:
        conn.close()

if __name__ == "__main__":
    upload_large_csv()