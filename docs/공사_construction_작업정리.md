# 공사(Construction) 데이터 파이프라인 작업 정리

## 1. 전체 구조

```
CSV (downloads_construction/)
    → construction_upload.py
    → construction_contract_raw (원본)

construction_contract_raw (시설공사 필터)
    → sp_etl_construction_contracts_v2()
    ├── construction_contract_flat       (펼쳐서 보기 / 단건 조회)
    └── construction_contract_longterm_group (합쳐서 보기 / 장기계약 그룹)

(선택) construction_contract_summary / construction_contract_change_history
    → 기존 sp_etl_construction_contracts() 로 유지. 화면 구현 핵심은 flat + longterm_group.
```

- **raw**: CSV 그대로 적재. PK `(contract_no, contract_change_seq)`. **construction_upload.py는 raw 적재까지만 담당.** ETL 프로시저 호출은 수동/스케줄/스프링에서 수행.
- **flat**: 시설공사만, **contract_no당 최종 1건**. **펼쳐서 보기(OFF)**·단건 조회·엑셀 다운로드용. 기간 필터: **contract_date**.
- **longterm_group**: 시설공사만, **group_key**(= COALESCE(initial_year_contract_no, contract_no))당 1건. **합쳐서 보기(ON)**·장기계약 그룹·엑셀 다운로드용. 최종계약금액 = 그룹 **contract_amount 합계**. 기간 필터: **initial_contract_date**.
- **summary / history**: (deprecated for this UI) 기존 설계 유지. history는 디버깅/변경이력용으로 선택 사용. **화면·다운로드 구현 시에는 flat과 longterm_group만 사용.**

---

## 2. 테이블 (조회용 2종)

| 테이블 | 역할 | PK / 기간 필터 |
|--------|------|----------------|
| `construction_contract_raw` | 공사 계약 CSV 원본 | (contract_no, contract_change_seq) |
| **`construction_contract_flat`** | **펼쳐서 보기** (단건) | contract_no / **contract_date** |
| **`construction_contract_longterm_group`** | **합쳐서 보기** (장기 그룹) | group_key / **initial_contract_date** |
| `construction_contract_summary` | (deprecated for screen) 기존 요약 | contract_no |
| `construction_contract_change_history` | (optional) 변경 이력 | (contract_no, change_seq), FK→summary |

- **flat**: DATE/BIGINT, saved, is_active, last_seen_date, etl_loaded_at. 기간 조회는 `contract_date BETWEEN ? AND ?`.
- **longterm_group**: initial_contract_date, initial_contract_amount, final_contract_date, **final_contract_amount_sum**(합계), final_change_seq, contract_count. 문자열 컬럼은 **초기 계약 기준**. 기간 조회는 `initial_contract_date BETWEEN ? AND ?`.

---

## 3. 화면 토글별 조회 테이블

| 토글 | 조회 테이블 | 기간 필터 컬럼 |
|------|-------------|----------------|
| **합쳐서 보기 ON** | `construction_contract_longterm_group` | `initial_contract_date` BETWEEN from~to |
| **펼쳐서 보기 OFF** | `construction_contract_flat` | `contract_date` BETWEEN from~to |

- 엑셀/구글시트 다운로드도 동일 규칙: 토글 ON → longterm_group 조회, OFF → flat 조회. raw에서 매번 집계하지 않도록 **조회용 테이블 2종**으로 안정화.

---

## 4. 시설공사 필터 (ETL 적용 대상)

raw에서 아래 조건을 만족하는 행만 flat / longterm_group으로 적재한다.

- `public_procurement_category_major = '시설공사'`
- `public_procurement_category_mid IN ('개별법령', '시설물유지관리공사')`
- `public_procurement_category_name IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사')`

longterm_group에는 위 시설공사 필터 + **장기계약만** (`long_term_continuation_seq` 비어있지 않거나 `is_initial_long_term_contract = 'Y'`) 적용.

---

## 5. flat 최종행 선택 규칙

같은 `contract_no` 안에서 **1건**만 선택할 때:

1. `is_final_contract = 'Y'` 인 행이 있으면 그 중 하나 (동률이면 아래 기준)
2. 없으면 `contract_change_seq`가 **가장 큰** 행
3. 그래도 동률이면 `contract_date`가 **가장 최신**인 행

구현: `ROW_NUMBER() OVER (PARTITION BY contract_no ORDER BY is_final_contract='Y' DESC, contract_change_seq DESC, contract_date DESC)` 후 `rn = 1`.

---

## 6. longterm_group 집계 규칙

- **group_key** = `COALESCE(initial_year_contract_no, contract_no)`.
- **초기 계약**: 그룹 내 `contract_change_seq` **최소**인 행. 이 행 기준으로 업체명·계약건명·수요기관명·지역·품명·입찰계약방법·입찰공고번호, **initial_contract_date**, **initial_contract_amount** 채움.
- **final_contract_date** = 그룹 내 MAX(contract_date).
- **final_contract_amount_sum** = 그룹 내 SUM(contract_amount) (화면의 최종계약금액).
- **final_change_seq** = 그룹 내 MAX(contract_change_seq).
- **contract_count** = 그룹 내 건수.

---

## 7. 장기계약(is_long_term_contract) Y/N

- **Y**: `long_term_continuation_seq`가 빈값·0이 **아니거나**, `is_initial_long_term_contract = 'Y'`
- 그 외: **N**

---

## 8. 날짜·금액 처리

- **날짜**: raw가 `YYYYMMDD` 또는 `20150522.0` 같은 문자열이면 `SUBSTRING_INDEX(..., '.', 1)` 등으로 정리 후 `STR_TO_DATE(..., '%Y%m%d')`로 DATE 저장. flat/longterm_group은 **DATE** 타입.
- **금액**: 원 단위 **BIGINT** 통일 (contract_amount, first_contract_amount, final_contract_amount_sum 등).

---

## 9. 파일 목록 (공사 관련)

### Raw 적재
- `create_table_construction_contract_raw.sql` — raw 테이블 DDL
- `construction_upload.py` — CSV → raw 적재 (downloads_construction → completed_construction). **ETL 호출은 이 스크립트 밖에서(수동/스케줄/스프링).**
- `create_index_construction_vendor.sql` — raw 사업자번호 인덱스 (선택)
- `alter_table_construction_contract_raw_amounts_to_decimal.sql` — 금액 DECIMAL 변경 (선택)

### 조회용 테이블 (화면·다운로드)
- `create_table_construction_contract_flat.sql` — **flat** DDL (펼쳐서 보기)
- `create_table_construction_contract_longterm_group.sql` — **longterm_group** DDL (합쳐서 보기)

### ETL v2 (권장)
- `create_procedure_etl_construction_contracts_v2.sql` — **sp_etl_construction_contracts_v2()**  
  - Step1: raw(시설공사) → **flat** UPSERT (최종행 1건)  
  - Step2: raw(시설공사, 장기) → **longterm_group** UPSERT  
  - Step3: raw에 없는 contract_no → flat `is_active='N'`  
  - Step4: raw에 없는 group_key → longterm_group `is_active='N'`  
  - TRUNCATE 없음. 대용량 시 전체 배치 1회/일 후, 필요 시 batch_id/ingested_at 기반 증분 갱신 확장 가능(주석 가이드).

### Summary / History (deprecated for screen, optional)
- `create_table_construction_contract_summary.sql` — 기존 요약 DDL
- `alter_table_construction_contract_summary_dates_and_soft_delete.sql` — summary DATE, is_active 등
- `create_table_construction_contract_change_history.sql` — history DDL (FK → summary)
- `create_procedure_etl_construction_contracts.sql` — sp_etl_construction_contracts() (summary/history용). 화면은 **v2 + flat/longterm_group** 사용.

### 인덱스·스케줄 (선택)
- `create_index_long_term_construction.sql` — raw/flat 조회용 인덱스
- `create_procedure_refresh_construction_summary.sql` — 예전 TRUNCATE 방식 (v2 사용 권장)
- `create_event_daily_refresh_construction_summary.sql` — 이벤트에서 **sp_etl_construction_contracts_v2** 호출로 변경 가능

### 문서
- `docs/CONSTR_raw_columns_mapping.md` — raw 컬럼 매핑, 실행 순서, 예외/주의사항

---

## 10. 실행 순서 (최초 1회 + 이후 갱신)

### 최초 1회 (flat + longterm_group + v2 기준)
1. `create_table_construction_contract_raw.sql` (또는 construction_upload.py로 자동 생성)
2. `create_table_construction_contract_flat.sql`
3. `create_table_construction_contract_longterm_group.sql`
4. `create_procedure_etl_construction_contracts_v2.sql`
5. (선택) 기존 summary/history 유지 시: summary DDL → ALTER → history DDL → `create_procedure_etl_construction_contracts.sql`

### raw에 데이터 넣기
- CSV를 `downloads_construction/`에 두고  
  `python construction_upload.py --downloads-dir ./downloads_construction --completed-dir ./completed_construction`

### flat / longterm_group 채우기 (수동 1회 또는 스케줄/스프링)
```sql
CALL sp_etl_construction_contracts_v2();
```

- 대용량(2017~2025 등)이면 실행 시간이 길 수 있음. 우선 전체 배치 1회/일로 운영 후, 필요 시 증분 갱신 확장.
- raw 날짜가 `20150522.0` 형태여도 프로시저에서 `.0` 제거 후 DATE로 변환.

---

## 11. 정리

- **raw**: CSV 원본 보관. construction_upload.py는 raw 적재만 담당.
- **flat**: 펼쳐서 보기·단건 조회·다운로드. 기간 필터 **contract_date**. TRUNCATE 없이 **UPSERT + is_active**.
- **longterm_group**: 합쳐서 보기·장기계약 그룹·다운로드. 기간 필터 **initial_contract_date**. 최종계약금액 = **합계**. TRUNCATE 없이 **UPSERT + is_active**.
- **ETL**: `sp_etl_construction_contracts_v2()` 한 번 호출로 flat → longterm_group → is_active 정리. 스케줄러 또는 스프링에서 주기 호출.
- **summary / history**: 화면 구현 핵심에서는 사용하지 않음. history는 디버깅/이력용으로 선택 유지.
