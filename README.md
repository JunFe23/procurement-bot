# 🤖 Procurement Bot (조달청 데이터 자동 수집기)

## 📌 프로젝트 소개

대한민국 조달청 [조달데이터허브](https://data.g2b.go.kr/)의 계약 데이터를 자동으로 수집·적재하고, 조회 API를 위한 집계 테이블을 관리하는 Python 데이터 파이프라인입니다.

공공기관 웹사이트의 복잡한 보안 및 프레임워크(WebSquare, MicroStrategy) 환경을 극복하고, 완전 자동화된 데이터 파이프라인을 구축하기 위해 개발하였습니다.

**조달데이터허브 CSV 보고서 통합(2026-03-18 공지 기준):** 과거 별도로 제공되던 여러 리포트가 새 보고서·파일 형식으로 통합되었습니다.

- **물품:** 「물품 계약 상세내역」과 「특정품목 조달 내역」CSV가 **「특정품목 조달 내역」** 하나로 통합되었으며, 헤더·컬럼 구성과 적재 규칙이 이전 각 CSV와 동일하지 않을 수 있습니다.
- **공사·용역:** 「공사 계약 내역」, 「용역 계약 업체 내역」 등이 **「업무별 구성원별 계약내역」** 형태로 통합되었으며, 구성원·지분 단위 등 **행 단위(그레인)** 변경이 있습니다.

이 레포지토리의 `manual_upload.py` 등 기존 스크립트·테이블 정의는 **통합 전 CSV**를 전제로 합니다. 통합 후 데이터는 **허브에서 받은 새 CSV/Excel을 기준**으로 매핑·적재 로직을 갱신해야 합니다.

**지원 데이터 종류:**

| 데이터 | 업로드 스크립트 | 대상 테이블 |
|--------|----------------|-------------|
| 물품 계약 상세내역 | `manual_upload.py` | `procurement_raw` |
| 특정품목 조달 내역 | `specific_item_upload.py` | `procurement_specific_item_raw` |
| 공사 계약 내역 | `construction_upload.py` | `construction_contract_raw` |
| 용역 계약 업체 내역 | `service_upload.py` | `service_contract_raw` |

---

## 🚀 핵심 기능 (Key Features)

1. **WebSquare UI 완벽 제어:**
   - 투명 로딩 레이어(`___processbar2`) 자동 감지 및 대기
   - `ActionChains`를 활용한 마우스 오버(Hover) 메뉴 조작
   - Javascript Executor를 이용한 강제 클릭(Force Click) 구현
2. **MSTR 리포트 팝업 자동화:**
   - 동적으로 생성되는 팝업창(New Window) 감지 및 핸들링
   - '검색' 및 '내보내기' 버튼의 동적 ID/속성 변화 대응 (3중 탐색 로직)
3. **스마트 다운로드 감지:**
   - 네트워크 속도와 무관하게 파일 다운로드가 완료될 때까지 대기 (`.crdownload` 감시)
   - 다운로드 완료 즉시 데이터 무결성 검증
4. **일괄 데이터 처리:**
   - 다운로드 폴더의 모든 CSV 파일을 자동으로 스캔하여 데이터베이스에 저장
   - 처리 완료된 파일은 완료 폴더로 자동 이동 (아카이빙)
   - 대용량 데이터를 청크 단위로 분할 처리하여 안정성 확보
5. **공사 계약 ETL 파이프라인:**
   - raw → flat / grouped 테이블 UPSERT (TRUNCATE 없음, `is_active` 소프트 삭제)
   - `sp_etl_construction_contracts()` 한 번 호출로 flat·grouped 동시 갱신
   - 시설공사 필터(전기공사·정보통신공사·기계설비공사 등) 자동 적용
6. **물품 계약 ETL 파이프라인 (시장 조사용):**
   - 탑인더스트리·탑정보통신 취급 품목(물품분류번호+세부품명번호 쌍) 기준 시장 전체 계약 적재
   - raw → flat `(contract_no, item_seq)` / grouped `(bid_notice_no, vendor, contract_no)` UPSERT
   - `sp_etl_procurement_contracts()` 한 번 호출로 flat·grouped 동시 갱신
7. **용역 계약 ETL 파이프라인 (시장 조사용):**
   - 탑인더스트리·탑정보통신 취급 공공조달분류 기준 시장 전체 용역 계약 적재
   - raw → flat `(contract_delivery_integrated_no)` / grouped `(group_key)` UPSERT
   - 공동수급이어도 계약별 1건 처리 (max change_seq, 공사와 동일 방식)
   - `sp_etl_service_contracts()` 한 번 호출로 flat·grouped 동시 갱신
8. **쇼핑몰(3자단가) ETL 파이프라인:**
   - `procurement_specific_item_raw`에서 `contract_type = '제3자단가계약'`만 필터하여 적재
   - raw → `shopping_mall_flat` (조회 화면용) → `shopping_mall_summary` (대시보드 집계용)
   - 대시보드에서 물품 계약과 UNION ALL로 통합 조회 가능 (`dataSource=all/procurement/shopping_mall`)

---

## 🛠 기술 스택 (Tech Stack)

- **Language:** Python 3.12
- **Browser Automation:** Selenium 4 + webdriver-manager
- **Data Processing:** Pandas 2, SQLAlchemy 2
- **Database:** MySQL (PyMySQL)
- **Environment:** macOS (Apple Silicon M1) / Ubuntu 22.04 (EC2)

---

## 📁 폴더 구조

| 소스 폴더 (CSV 넣는 곳) | 완료 이동 폴더 | 스크립트 | 대상 테이블 |
|-------------------------|----------------|----------|-------------|
| `downloads/` | `completed/` | `manual_upload.py` | `procurement_raw` |
| `downloads_specific_item/` | `completed_specific_item/` | `specific_item_upload.py` | `procurement_specific_item_raw` |
| `downloads_construction/` | `completed_construction/` | `construction_upload.py` | `construction_contract_raw` |
| `downloads_service/` | `completed_service/` | `service_upload.py` | `service_contract_raw` |

---

## ⚙️ 실행 방법 (Usage)

### 환경 설정

```bash
pip install -r requirements.txt
```

> XLSX/XLS 처리를 위해 `openpyxl` / `xlrd` 추가 설치가 필요할 수 있습니다.

---

### 물품 계약 상세내역

```bash
# 자동 다운로드 및 DB 저장
python main.py

# downloads/ 내 CSV/XLSX/XLS 일괄 적재
python manual_upload.py --downloads-dir ./downloads --completed-dir ./completed
```

- 대상 테이블: `procurement_raw`
- 로그 테이블: `procurement_ingestion_log`
- 옵션: `--dry-run`, `--dedupe-in-file`, `--no-stop-on-fail`

---

### 공사 계약 내역

```bash
python construction_upload.py --downloads-dir ./downloads_construction --completed-dir ./completed_construction
```

- **테이블 자동 생성**: `construction_contract_raw` 없으면 스크립트 실행 시 생성
- 로그 테이블: `construction_ingestion_log`
- 옵션: `--dry-run`, `--dedupe-in-file`, `--no-stop-on-fail`

#### 공사 테이블 구조 (raw → ETL → 조회용)

```
CSV (downloads_construction/)
    → construction_upload.py
    → construction_contract_raw (원본)

construction_contract_raw (시설공사 필터)
    → sp_etl_construction_contracts()
    ├── construction_contract_flat       (펼쳐서 보기 / 단건 조회)
    └── construction_contract_grouped    (합쳐서 보기: 장기=그룹 1행·비장기=단건 1행)
```

| 테이블 | 역할 | PK / 기간 필터 |
|--------|------|----------------|
| `construction_contract_raw` | CSV 원본 | `(contract_no, contract_change_seq)` |
| `construction_contract_flat` | **펼쳐서 보기** (단건) | `contract_no` / `contract_date` |
| `construction_contract_grouped` | **합쳐서 보기** (장기=그룹·비장기=단건) | `group_key` / `initial_contract_date` |
| `construction_contract_summary` | (deprecated) 기존 요약 | `contract_no` |
| `construction_contract_change_history` | (선택) 변경 이력 | `(contract_no, change_seq)` |

**화면 토글별 조회:**

| 토글 | 조회 테이블 | 기간 필터 컬럼 |
|------|-------------|----------------|
| 합쳐서 보기 ON | `construction_contract_grouped` | `initial_contract_date` |
| 펼쳐서 보기 OFF | `construction_contract_flat` | `contract_date` |

**갱신 방식:** TRUNCATE 없이 `sp_etl_construction_contracts()` 한 번으로 flat UPSERT → grouped UPSERT → `is_active` 정리. raw에 없어진 계약/그룹은 `is_active='N'` 처리.

#### 공사 ETL 최초 실행 순서 (1회)

1. `create_table_construction_contract_raw.sql` (또는 `construction_upload.py` 자동 생성)
2. `create_table_construction_contract_flat.sql`
3. `create_table_construction_contract_grouped.sql`
4. `create_procedure_etl_construction_contracts.sql`

#### ETL 실행 (수동 또는 스케줄/스프링)

```sql
START TRANSACTION;
CALL sp_etl_construction_contracts();
COMMIT;
```

**시설공사 필터 (ETL 적용 대상):**
- `public_procurement_category_major = '시설공사'`
- `public_procurement_category_mid IN ('개별법령', '시설물유지관리공사')`
- `public_procurement_category_name IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사')`

---

### 용역 계약 업체 내역

```bash
python service_upload.py --downloads-dir ./downloads_service --completed-dir ./completed_service
```

- **테이블 자동 생성**: `service_contract_raw` 없으면 스크립트 실행 시 생성
- 파일 인코딩: UTF-16 탭 구분, 헤더 72번째 줄
- 로그 테이블: `service_ingestion_log`
- PK: `(계약납품통합번호, 계약납품통합변경차수, 계약업체사업자등록번호, 업종)` — 공동수급 시 업체·업종별 1행

#### 용역 테이블 구조 (raw → ETL → 조회용)

```
CSV (downloads_service/)
    → service_upload.py
    → service_contract_raw (원본)

service_contract_raw (탑인더스트리·탑정보통신 취급 공공조달분류 기준)
    → sp_etl_service_contracts()
    ├── service_contract_flat       (펼쳐서 보기 / 단건 조회)
    └── service_contract_grouped    (합쳐서 보기: 장기=그룹 1행·비장기=단건 1행)
```

| 테이블 | 역할 | PK / 기간 필터 |
|--------|------|----------------|
| `service_contract_raw` | CSV 원본 | `(contract_delivery_integrated_no, change_seq, vendor_biz_reg_no, business_type)` |
| `service_contract_flat` | **펼쳐서 보기** (단건) | `contract_delivery_integrated_no` / `contract_date` |
| `service_contract_grouped` | **합쳐서 보기** (장기=그룹·비장기=단건) | `group_key` / `initial_contract_date` |

**화면 토글별 조회:**

| 토글 | 조회 테이블 | 기간 필터 컬럼 |
|------|-------------|----------------|
| 합쳐서 보기 ON | `service_contract_grouped` | `initial_contract_date` |
| 펼쳐서 보기 OFF | `service_contract_flat` | `contract_date` |

**갱신 방식:** TRUNCATE 없이 `sp_etl_service_contracts()` 한 번으로 flat UPSERT → grouped UPSERT → `is_active` 정리. 공동수급이어도 `contract_delivery_integrated_no`당 max change_seq 1행으로 저장 (공사와 동일 방식).

**대상 범위:** 탑인더스트리(1188117437)·탑정보통신(1188119624)이 체결한 `public_procurement_category`와 동일한 분류를 가진 시장 전체 용역 계약 (두 회사 계약 포함).

#### 용역 ETL 최초 실행 순서 (1회)

1. `create_table_service_contract_flat.sql`
2. `create_table_service_contract_grouped.sql`
3. `create_procedure_etl_service_contracts.sql`

#### ETL 실행 (수동 또는 스케줄/스프링)

```sql
CALL sp_etl_service_contracts();
```

---

### 특정품목 조달 내역

```bash
python specific_item_upload.py --downloads-dir ./downloads_specific_item
```

- 대상 파일: `*특정품목조달내역*.csv`
- 대상 테이블: `procurement_specific_item_raw`
- 로그 테이블: `procurement_specific_item_ingestion_log`
- 완료 파일: `./completed_specific_item`로 이동

**데이터 조인 정보:**
- 종합쇼핑몰계약 엑셀의 `납품요구번호` = `procurement_specific_item_raw.delivery_contract_no` (계약납품통합번호)

---

### 물품 계약 시장 조사용 ETL (flat + grouped)

탑인더스트리·탑정보통신이 취급하는 품목(물품분류번호+세부품명번호 쌍)과 동일한 품목을 가진 **시장 전체 계약**을 flat/grouped 테이블로 관리합니다.

**테이블 구조:**

| 테이블 | 역할 | PK / 기간 필터 |
|--------|------|----------------|
| `procurement_contract_flat` | **펼쳐서 보기** (아이템 단위) | `(contract_no, item_seq)` / `contract_date` |
| `procurement_contract_grouped` | **합쳐서 보기** (공고+업체 단위) | `(bid_notice_no, vendor_biz_reg_no, contract_no)` / `initial_contract_date` |

**ETL 최초 실행 순서 (1회):**

1. `create_table_procurement_contract_flat.sql`
2. `create_table_procurement_contract_grouped.sql`
3. 권장 인덱스 추가:
   ```sql
   CREATE INDEX idx_vendor_final ON procurement_raw (vendor_biz_reg_no, is_final_contract, item_category_no, detail_item_no);
   CREATE INDEX idx_final_type_item ON procurement_raw (is_final_contract, contract_type, item_category_no, detail_item_no);
   ```
4. `create_procedure_etl_procurement_contracts.sql`

**ETL 실행 (수동 또는 스케줄/스프링):**

```sql
START TRANSACTION;
CALL sp_etl_procurement_contracts();
COMMIT;
```

**필터 조건:**
- `is_final_contract = 'Y'`, `contract_type <> '제3자단가계약'`
- `(item_category_no, detail_item_no)` 쌍이 탑인더스트리(1188117437) 또는 탑정보통신(1188119624) 계약에 존재하는 것

---

### 물품 계약 집계 테이블 (조회 API용, 기존)

`procurement_raw`를 입찰공고번호 단위로 집계한 결과를 `procurement_contract_summary`에 저장하고, 조회 API는 이 테이블만 조회합니다.

**실행 순서 (MySQL):**

1. `create_index_long_term.sql` — 인덱스 생성
2. `create_table_procurement_contract_summary.sql` — 집계 테이블 생성
3. `create_procedure_refresh_contract_summary.sql` — TRUNCATE 후 INSERT 프로시저 생성
4. `create_event_daily_refresh_summary.sql` — 매일 새벽 2시 자동 갱신 이벤트 생성

```sql
-- 이벤트 스케줄러 활성화
SET GLOBAL event_scheduler = ON;

-- 수동 갱신
CALL sp_refresh_procurement_contract_summary();
```

---

## 📂 SQL 파일 목록

### 물품 계약 (procurement_raw)
| 파일 | 설명 |
|------|------|
| `create_table_procurement_contract_flat.sql` | flat 테이블 DDL (펼쳐서 보기, 아이템 단위) |
| `create_table_procurement_contract_grouped.sql` | grouped 테이블 DDL (합쳐서 보기, 공고+업체 단위) |
| `create_procedure_etl_procurement_contracts.sql` | ETL 프로시저 (flat + grouped UPSERT, 시장 조사용) |
| `create_table_procurement_contract_summary.sql` | 집계 테이블 DDL (기존, deprecated for screen) |
| `create_procedure_refresh_contract_summary.sql` | 집계 갱신 프로시저 (기존) |
| `create_event_daily_refresh_summary.sql` | 매일 자동 갱신 이벤트 |
| `create_index_long_term.sql` | 장기계약 조회 인덱스 |
| `add_column_comments_procurement_raw.sql` | raw 테이블 컬럼 코멘트 |

### 공사 계약 (construction_contract_*)
| 파일 | 설명 |
|------|------|
| `create_table_construction_contract_raw.sql` | raw 테이블 DDL |
| `create_table_construction_contract_flat.sql` | flat 테이블 DDL (펼쳐서 보기) |
| `create_table_construction_contract_grouped.sql` | grouped 테이블 DDL (합쳐서 보기) |
| `create_procedure_etl_construction_contracts.sql` | ETL 프로시저 (flat + grouped UPSERT) |
| `create_table_construction_contract_summary.sql` | summary 테이블 DDL (deprecated) |
| `create_table_construction_contract_change_history.sql` | 변경 이력 테이블 DDL (선택) |
| `create_procedure_refresh_construction_summary.sql` | 구 TRUNCATE 방식 프로시저 (deprecated) |
| `create_event_daily_refresh_construction_summary.sql` | 공사 일일 갱신 이벤트 |
| `create_index_construction_vendor.sql` | raw 사업자번호 인덱스 |
| `create_index_long_term_construction.sql` | 장기계약 조회 인덱스 |
| `alter_table_construction_contract_raw_amounts_to_decimal.sql` | 금액 DECIMAL 변경 (선택) |
| `alter_table_construction_contract_summary_*.sql` | summary ALTER DDL |
| `alter_table_construction_contract_grouped_add_is_long_term.sql` | grouped 장기계약 컬럼 추가 |

### 용역 계약 (service_contract_*)
| 파일 | 설명 |
|------|------|
| `create_table_service_contract_flat.sql` | flat 테이블 DDL (펼쳐서 보기, 계약 단위) |
| `create_table_service_contract_grouped.sql` | grouped 테이블 DDL (합쳐서 보기, 장기=그룹 1행) |
| `create_procedure_etl_service_contracts.sql` | ETL 프로시저 (flat + grouped UPSERT, 시장 조사용) |
| `alter_table_service_contract_raw_add_comments.sql` | raw 테이블 컬럼 코멘트 |
| `alter_table_service_contract_raw_split_code_name.sql` | raw 코드/명칭 컬럼 분리 |
| `alter_table_service_contract_flat_split_code_name.sql` | flat 코드/명칭 컬럼 분리 |
| `alter_table_service_contract_grouped_split_code_name.sql` | grouped 코드/명칭 컬럼 분리 |

### 쇼핑몰(3자단가) (shopping_mall_*)
| 파일 | 설명 |
|------|------|
| `create_table_shopping_mall_flat.sql` | flat 테이블 DDL (납품요구 조회용) |
| `create_table_shopping_mall_summary.sql` | summary 테이블 DDL (대시보드 집계용) |
| `create_procedure_etl_shopping_mall.sql` | ETL 프로시저 (specific_item_raw → flat, 제3자단가 필터) |
| `create_procedure_refresh_shopping_mall_summary.sql` | summary 갱신 프로시저 (flat → summary) |

### 특정품목
| 파일 | 설명 |
|------|------|
| `add_column_comments_specific_item.sql` | 특정품목 raw 컬럼 코멘트 |
| `alter_table_procurement_contract_summary_*.sql` | summary ALTER DDL |

### 조회·디버깅용 쿼리
| 파일 | 설명 |
|------|------|
| `query_long_term_contracts.sql` | 장기계약 조회 |
| `query_long_term_by_vendor_bid.sql` | 사업자·입찰공고 기준 장기계약 조회 |

---

## 📄 문서 (docs/)

| 파일 | 설명 |
|------|------|
| `docs/공사_construction_작업정리.md` | 공사 ETL 전체 설계 (테이블 구조·갱신 규칙·실행 순서) |
| `docs/CONSTR_raw_columns_mapping.md` | raw 컬럼 매핑표·ETL 실행 가이드·주의사항 |
| `docs/Spring_공사_조회_연동_프롬프트.md` | 공사 Spring Boot 조회 API 연동용 설계 프롬프트 |
| `docs/Spring_물품_조회_연동_프롬프트.md` | 물품 Spring Boot 조회 API 연동용 설계 프롬프트 (시장 조사) |
| `docs/Spring_용역_조회_연동_프롬프트.md` | 용역 Spring Boot 조회 API 연동용 설계 프롬프트 |
| `docs/service_contract_classification.tsv` | 용역 공공조달분류 대/중/소분류별 계약 건수 분류표 |
| `docs/Spring_쇼핑몰_조회_대시보드_연동_프롬프트.md` | 쇼핑몰 Spring Boot 조회 API + 대시보드 연동 설계 프롬프트 |
| `setup-ec2.md` | EC2 서버 수동 설정 가이드 |

---

## ☁️ EC2에서 실행하기

### 빠른 설정 (자동 스크립트)

```bash
chmod +x setup-ec2.sh
./setup-ec2.sh
```

### 수동 설정

자세한 가이드는 [`setup-ec2.md`](setup-ec2.md)를 참고하세요.

**주요 단계:**

1. Ubuntu 22.04 LTS 인스턴스 생성
2. Chrome 및 ChromeDriver 설치
3. MySQL 설치 및 데이터베이스 생성
4. 프로젝트 파일 업로드
5. Python 가상환경 설정 및 패키지 설치

### EC2 자동 실행 (Cron)

```bash
crontab -e
# 매일 새벽 2시 실행 예시
0 2 * * * cd /home/ubuntu/procurement-bot && /home/ubuntu/procurement-bot/venv/bin/python main.py >> /home/ubuntu/procurement-bot/logs/cron.log 2>&1
```

---

## 📝 주요 변경사항

- ✅ 물품 ETL 신규: `sp_etl_procurement_contracts()` — 탑인더스트리·탑정보통신 취급 품목 기준 시장 전체 flat + grouped UPSERT
- ✅ `procurement_contract_flat` 테이블 추가 — 펼쳐서 보기용 (contract_no+item_seq 아이템 단위)
- ✅ `procurement_contract_grouped` 테이블 추가 — 합쳐서 보기용 (bid_notice_no+vendor 공고·업체 단위)
- ✅ 공사 ETL v2: `sp_etl_construction_contracts()` — TRUNCATE 없이 flat + grouped UPSERT, `is_active` 소프트 삭제
- ✅ `construction_contract_grouped` 테이블 추가 — 합쳐서 보기용 (장기=그룹 1행·비장기=단건 1행)
- ✅ `construction_contract_flat` 테이블 추가 — 펼쳐서 보기용 (contract_no당 최종 1건)
- ✅ 용역 ETL 신규: `sp_etl_service_contracts()` — 탑인더스트리·탑정보통신 취급 공공조달분류 기준 시장 전체 flat + grouped UPSERT
- ✅ `service_contract_flat` 테이블 추가 — 펼쳐서 보기용 (계약별 1건, max change_seq 기준, 공사와 동일 방식)
- ✅ `service_contract_grouped` 테이블 추가 — 합쳐서 보기용 (장기=그룹 1행·비장기=단건 1행)
- ✅ `docs/Spring_용역_조회_연동_프롬프트.md` 추가 — Spring Boot 용역 조회 API 연동 설계
- ✅ `docs/service_contract_classification.tsv` 추가 — 용역 분류별 계약 건수 분류표
- ✅ 용역 계약(`service_upload.py`, `service_contract_raw`) 데이터 파이프라인 추가
- ✅ 쇼핑몰(3자단가) ETL 신규: `sp_etl_shopping_mall()` — procurement_specific_item_raw 제3자단가계약 필터 → shopping_mall_flat UPSERT
- ✅ `shopping_mall_flat` 테이블 추가 — 쇼핑몰 납품요구 조회용 (delivery_contract_no+change_seq+item_seq 단위)
- ✅ `shopping_mall_summary` 테이블 추가 — 대시보드 집계용 (업체+물품분류+세부품명+연월 단위)
- ✅ `sp_refresh_shopping_mall_summary()` 추가 — flat → summary 갱신 프로시저
- ✅ `docs/Spring_쇼핑몰_조회_대시보드_연동_프롬프트.md` 추가 — 쇼핑몰 조회 API + 대시보드 dataSource 통합 설계
- ✅ Headless 모드 자동 활성화 (EC2/Linux 환경 지원)
- ✅ 자동 설치 스크립트 제공 (`setup-ec2.sh`) 및 상세 EC2 설정 가이드 (`setup-ec2.md`)
