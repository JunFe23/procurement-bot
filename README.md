# 🤖 Procurement Bot (조달청 데이터 자동 수집기)

## 📌 프로젝트 소개

대한민국 조달청 [조달데이터허브](https://data.g2b.go.kr/)의 '물품 계약 상세내역' 리포트를 자동으로 조회하고 CSV로 다운로드하는 Python 자동화 봇입니다.

공공기관 웹사이트의 복잡한 보안 및 프레임워크(WebSquare, MicroStrategy) 환경을 극복하고, 완전 자동화된 데이터 파이프라인을 구축하기 위해 개발하였습니다.

## 🚀 핵심 기능 (Key Features)

1.  **WebSquare UI 완벽 제어:**
    - 투명 로딩 레이어(`___processbar2`) 자동 감지 및 대기
    - `ActionChains`를 활용한 마우스 오버(Hover) 메뉴 조작
    - Javascript Executor를 이용한 강제 클릭(Force Click) 구현
2.  **MSTR 리포트 팝업 자동화:**
    - 동적으로 생성되는 팝업창(New Window) 감지 및 핸들링
    - '검색' 및 '내보내기' 버튼의 동적 ID/속성 변화 대응 (3중 탐색 로직)
3.  **스마트 다운로드 감지:**
    - 네트워크 속도와 무관하게 파일 다운로드가 완료될 때까지 대기 (`.crdownload` 감시)
    - 다운로드 완료 즉시 데이터 무결성 검증
4.  **일괄 데이터 처리:**
    - `downloads` 폴더의 모든 CSV 파일을 자동으로 스캔하여 데이터베이스에 저장
    - 처리 완료된 파일은 `completed` 폴더로 자동 이동 (아카이빙)
    - 대용량 데이터를 청크 단위로 분할 처리하여 안정성 확보

## 🛠 기술 스택 (Tech Stack)

- **Language:** Python 3.12
- **Browser Automation:** Selenium WebDriver
- **Data Processing:** Pandas
- **Environment:** macOS (Apple Silicon M1)

## 📁 폴더 구조 (데이터 적재용)

| 소스 폴더 (CSV 넣는 곳) | 완료 이동 폴더 | 스크립트 | 대상 테이블 |
|-------------------------|----------------|----------|-------------|
| `downloads/` | `completed/` | `manual_upload.py` | `procurement_raw` (물품 계약 상세) |
| `downloads_specific_item/` | `completed_specific_item/` | `specific_item_upload.py` | `procurement_specific_item_raw` (특정품목 조달 내역) |
| **`downloads_construction/`** | **`completed_construction/`** | **`construction_upload.py`** | **`construction_contract_raw`** (공사 계약 내역) |
| **`downloads_service/`** | **`completed_service/`** | **`service_upload.py`** | **`service_contract_raw`** (용역 계약 업체 내역) |

- **공사 계약 내역(2017~2025 등)**: CSV를 **`downloads_construction/`** 에 넣고 **`construction_upload.py`** 로 적재. 성공한 파일은 **`completed_construction/`** 로 이동하며, **`construction_contract_raw`** 테이블에 저장됩니다.
- **용역 계약 업체 내역**: CSV를 **`downloads_service/`** 에 넣고 **`service_upload.py`** 로 적재. 성공한 파일은 **`completed_service/`** 로 이동하며, **`service_contract_raw`** 테이블에 저장됩니다. PK는 (계약납품통합번호, 계약납품통합변경차수, 계약업체사업자등록번호)입니다.

---

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

**다운로드 폴더의 모든 데이터 일괄 처리 (물품 계약 상세):**

```bash
python manual_upload.py --downloads-dir ./downloads --completed-dir ./completed
```

- `./downloads`의 CSV/XLSX/XLS 파일을 MySQL `procurement_raw`에 적재
- 적재 성공 파일은 `./completed`로 자동 이동
- 파일 단위 트랜잭션 및 적재 로그(`procurement_ingestion_log`) 기록

**공사 계약 내역(2017~2025 등) 일괄 처리:**

```bash
python construction_upload.py --downloads-dir ./downloads_construction --completed-dir ./completed_construction
```

- **테이블 자동 생성**: `construction_contract_raw`가 없으면 스크립트 실행 시 생성 (물품 적재처럼 Python만 실행하면 됨)
- CSV는 **`downloads_construction/`** 에 넣어 두고 실행
- 적재 성공 파일은 **`completed_construction/`** 로 자동 이동
- 로그 테이블: `construction_ingestion_log`
- 옵션: `--dry-run`, `--dedupe-in-file`, `--no-stop-on-fail` 지원

**공사 테이블 설계 (raw → flat + grouped, history 선택):**

- **raw** (`construction_contract_raw`): CSV 원본. PK `(contract_no, contract_change_seq)`. **`construction_upload.py`는 raw 적재까지만 담당.** 적재 후 ETL은 수동/스케줄/스프링에서 프로시저 호출.
- **flat** (`construction_contract_flat`): **펼쳐서 보기**·단건 조회용. 시설공사만, **contract_no당 최종 1건**. 기간 필터: **contract_date**. 화면 컬럼 + saved, is_active, last_seen_date, etl_loaded_at. DATE/BIGINT.
- **grouped** (`construction_contract_grouped`): **합쳐서 보기**용. 시설공사 **전체**(장기+비장기). 장기=group_key당 1행(금액 합계), 비장기=단건 1행 같은 양식. 토글 ON이면 이 테이블만 조회. 기간 필터: **initial_contract_date**.
- **history** (`construction_contract_change_history`): 변경 이력(선택). 화면 구현 핵심은 flat + grouped. history는 디버깅/이력용으로 유지 가능.
- **갱신 방식**: **TRUNCATE 없이** **`sp_etl_construction_contracts()`** 한 번으로 **flat UPSERT → grouped UPSERT → flat/grouped is_active 정리**. raw에 없어진 계약/그룹은 각각 `is_active='N'`.
- **실행 순서 (최초 1회)**: raw 테이블 → flat DDL → `create_table_construction_contract_grouped.sql` → `create_procedure_etl_construction_contracts.sql` 적용. 이후 `CALL sp_etl_construction_contracts();` 수동 또는 스케줄/스프링 호출.
- 상세: `docs/공사_construction_작업정리.md`, `docs/CONSTR_raw_columns_mapping.md` 참고.

**용역 계약 업체 내역 일괄 처리:**

```bash
python service_upload.py --downloads-dir ./downloads_service --completed-dir ./completed_service
```

- **테이블 자동 생성**: `service_contract_raw`가 없으면 스크립트 실행 시 생성
- CSV는 **`downloads_service/`** 에 넣어 두고 실행 (용역 리포트는 UTF-16 탭 구분, 헤더 72번째 줄)
- 적재 성공 파일은 **`completed_service/`** 로 자동 이동
- 로그 테이블: `service_ingestion_log`
- PK: (계약납품통합번호, 계약납품통합변경차수, 계약업체사업자등록번호) — 공동수급 시 업체별 1행

**옵션 예시:**

```bash
# 중복 제거 옵션 + 실패 시 계속 진행
python manual_upload.py --dedupe-in-file --no-stop-on-fail

# 정규화/검증만 수행 (DB insert 없음)
python manual_upload.py --dry-run
```

> XLSX/XLS 처리를 위해 `openpyxl`/`xlrd` 설치가 필요할 수 있습니다.

**특정품목 조달 내역 CSV 적재:**

```bash
python specific_item_upload.py --downloads-dir ./downloads_specific_item
```

- `./downloads_specific_item` 내 `*특정품목조달내역*.csv` 파일만 대상으로 적재
- 대상 테이블: `procurement_specific_item_raw`
- 적재 로그: `procurement_specific_item_ingestion_log`
- 완료 파일은 `./completed_specific_item`로 이동

**데이터베이스 테이블 조인 정보:**

- **종합쇼핑몰계약 엑셀 파일**의 `납품요구번호` 컬럼은 `procurement_specific_item_raw` 테이블의 `delivery_contract_no` (계약납품통합번호) 컬럼과 동일한 값을 가집니다.
- 두 데이터 소스를 조인할 때 이 컬럼을 기준으로 연결할 수 있습니다.

**집계용 테이블·프로시저·이벤트 (조회 API용):**

- `procurement_raw`를 입찰공고번호 단위로 집계한 결과를 **집계용 테이블**에 넣고, 조회 페이지/API는 이 테이블만 조회하는 흐름을 권장합니다.
- **실행 순서 (MySQL):**
    1. `create_index_long_term.sql` — 인덱스 생성
    2. `create_table_procurement_contract_summary.sql` — 집계용 테이블 생성
    3. `create_procedure_refresh_contract_summary.sql` — TRUNCATE 후 INSERT 프로시저 생성
    4. `create_event_daily_refresh_summary.sql` — 매일 새벽 2시 자동 갱신 이벤트 생성
- 이벤트 스케줄러 활성화: `SET GLOBAL event_scheduler = ON;`
- 수동 갱신: `CALL sp_refresh_procurement_contract_summary();`
- 조회 대상 테이블: `procurement_contract_summary`

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

- ✅ Headless 모드 자동 활성화
- ✅ EC2/Linux 환경을 위한 Chrome 옵션 추가
- ✅ 자동 설치 스크립트 제공 (`setup-ec2.sh`)
- ✅ 상세한 EC2 설정 가이드 제공 (`setup-ec2.md`)
