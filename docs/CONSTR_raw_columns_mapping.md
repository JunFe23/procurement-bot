# construction_contract_raw 컬럼 매핑 및 ETL 가이드

## 1. raw 테이블 컬럼 확인 및 표준 매핑

실행하여 실제 컬럼 확인:

```sql
USE g2b;
SHOW COLUMNS FROM construction_contract_raw;
```

현재 DDL 기준 **construction_contract_raw → 표준명(flat/grouped·history·summary용) 매핑**:

| raw 컬럼명 (construction_contract_raw) | 표준/용도 | 비고 |
|----------------------------------------|-----------|------|
| contract_no | contract_no | PK 구성, FK 대상 |
| contract_change_seq | change_seq | 이력 PK·요약 latest_change_seq |
| contract_date | contract_date | YYYYMMDD 등 → DATE 변환 |
| contract_title | contract_title | |
| procurement_method_type | (화면 미사용) | |
| vendor_biz_reg_no | vendor_biz_reg_no | |
| vendor_name | vendor_name | |
| demand_agency_code | (화면 미사용) | |
| demand_agency_name | demand_agency_name | |
| site_region | (화면 미사용) | |
| start_date | (이력 보존 가능) | VARCHAR→DATE |
| completion_date | (이력 보존 가능) | VARCHAR→DATE |
| total_completion_date | (이력 보존 가능) | VARCHAR→DATE |
| business_type | (화면 미사용) | |
| contract_request_no | (화면 미사용) | |
| initial_year_contract_no | initial_year_contract_no | |
| long_term_continuation_seq | (장기계약 판단용) | is_long_term_contract Y/N |
| bid_notice_no | bid_notice_no | |
| bid_notice_seq | (이력 보존 가능) | |
| award_rate | (이력 보존 가능) | |
| first_contract_date | first_contract_date | VARCHAR→DATE |
| is_first_contract | is_first_contract | CHAR(1) |
| is_final_contract | is_final_contract | CHAR(1), 최종행 선택 |
| is_initial_long_term_contract | is_initial_long_term_contract | CHAR(1), 장기계약 판단 |
| department_type | (화면 미사용) | |
| demand_agency_region | demand_agency_region | |
| is_women_enterprise_at_contract | (화면 미사용) | |
| company_type_at_contract | (화면 미사용) | |
| contract_law_type | (화면 미사용) | |
| standard_contract_method | (화면 미사용) | |
| joint_supply_type | (화면 미사용) | |
| contract_branch | (화면 미사용) | |
| contract_agency_name | (화면 미사용) | |
| bid_contract_method | bid_contract_method | |
| award_method | (이력 보존 가능) | |
| public_procurement_category_major | (필터용) | '시설공사' |
| public_procurement_category_mid | (필터용) | '개별법령','시설물유지관리공사' |
| public_procurement_category_name | public_procurement_category_name | 필터 + 화면 |
| contract_amount | contract_amount | BIGINT |
| contract_amount_delta | contract_diff_amount | 이력용 별칭, BIGINT |
| first_contract_amount | first_contract_amount | BIGINT |
| total_supplementary_amount | total_book_contract_amount | 이력용 별칭, BIGINT |
| estimated_price | estimated_price | BIGINT |
| estimated_amount | estimated_amount | BIGINT |
| award_amount | bid_amount | 이력용 별칭, BIGINT |

- **시설공사 필터**: `public_procurement_category_major = '시설공사'` AND `public_procurement_category_mid IN ('개별법령','시설물유지관리공사')` AND `public_procurement_category_name IN ('전기공사','정보통신공사','기계설비공사','시설물유지관리공사','상하수도설비공사','기타시설공사')`.  
- raw에 위 컬럼이 없으면 “공사 raw만 존재”로 가정하고 필터 없이 진행(가정 내용 명시).

---

## 2. 실행 순서 (트랜잭션 권장)

### 2.1 화면·다운로드용 (flat + grouped, 권장)

1. **컬럼 확인**  
   `SHOW COLUMNS FROM construction_contract_raw;` 로 실제 컬럼명 확인 후, 위 매핑표와 다르면 DDL/ETL에서 컬럼명 수정.

2. **DDL 적용 (순서 유지)**
   - `create_table_construction_contract_flat.sql` — 펼쳐서 보기용
   - `create_table_construction_contract_grouped.sql` — 합쳐서 보기용

3. **ETL 프로시저 생성**
   - `create_procedure_etl_construction_contracts.sql`  
     → `CALL sp_etl_construction_contracts();` 로 flat·grouped 증분 갱신

4. **ETL 실행 (트랜잭션 권장)**

```sql
START TRANSACTION;
CALL sp_etl_construction_contracts();
COMMIT;
-- 실패 시: ROLLBACK;
```

- **프로시저 내부**: Step1 raw→flat UPSERT, Step2 raw→grouped UPSERT, Step3 flat is_active 정리, Step4 grouped is_active 정리.
- **construction_upload.py**는 raw 적재만 수행. ETL 호출은 수동/스케줄/스프링에서 수행.

### 2.2 기존 summary/history (선택, deprecated for screen)

- `alter_table_construction_contract_summary_dates_and_soft_delete.sql`  
  (summary에 DATE, is_active, last_seen_date, created_at, updated_at 반영)
- `create_table_construction_contract_change_history.sql`  
  (history 테이블 생성, FK → summary)
- 화면 구현은 **flat + construction_contract_grouped** 사용. summary/history는 이력·디버깅용 선택.

---

## 3. 예외/주의사항

- **is_final_contract='Y'가 여러 건인 경우**: 동일 contract_no 내에서 `is_final_contract='Y'`가 복수면, `contract_change_seq DESC`, 그 다음 `contract_date DESC`(날짜 파싱 후)로 정렬해 1건만 선택.
- **change_seq가 NULL/비정상**: raw PK가 `(contract_no, contract_change_seq)` NOT NULL이므로 NULL 없음. 음수나 비정상값은 정렬 시 그대로 사용(필요 시 ETL에서 제외 규칙 추가).
- **날짜 파싱 실패**: `STR_TO_DATE(컬럼, '%Y%m%d')` 또는 `'%Y-%m-%d'` 시 NULL이면 해당 컬럼은 NULL 저장. 파싱 실패 건은 별도 로그 테이블에 기록하는 것을 권장(별도 구현).

---

## 4. 시설공사 필터 (가정)

- raw에 다음 컬럼이 존재한다고 가정하고 ETL에 반영함.
  - `public_procurement_category_major` = '시설공사'
  - `public_procurement_category_mid` IN ('개별법령', '시설물유지관리공사')
  - `public_procurement_category_name` IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사')
- 위 컬럼이 없으면 “공사 raw만 존재”로 두고, 프로시저 내 WHERE 조건을 제거하거나 주석 처리해 전체 raw를 대상으로 할 수 있음.
