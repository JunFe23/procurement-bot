# 공사 계약 조회 화면 – Spring Boot 연동용 프롬프트

아래 내용을 **Spring Boot 프로젝트에서 Cursor로 개발할 때** 복사해 붙여넣고, "이 설계대로 조회 API와 화면 연동을 구현해줘"라고 요청하면 됩니다.

---

## [아래부터 복사]

---

## 1. 데이터 흐름 (백그라운드)

- **원본**: `construction_contract_raw` — CSV 적재용. 화면/API는 이 테이블을 직접 조회하지 않는다.
- **조회용 테이블 2개** (ETL `sp_etl_construction_contracts()` 로 채움):
  - **`construction_contract_flat`** — 계약 단건(contract_no당 최종 1건). **펼쳐서 보기**용.
  - **`construction_contract_grouped`** — flat을 group_key 기준으로 묶어 집계한 결과. **합쳐서 보기**용. 장기계약은 그룹 1행(금액 합계), 비장기계약은 단건 1행, **같은 컬럼 구조**로 저장됨. (소스=flat이므로 raw의 is_final_contract 오류에 독립적)

화면은 **토글 값에 따라** 둘 중 하나의 테이블만 조회하면 된다. raw를 직접 집계하지 말 것.

---

## 2. 토글에 따른 조회 테이블·기간 필터

| 화면 토글 | 사용 테이블 | 기간 필터 컬럼 | 비고 |
|-----------|-------------|----------------|------|
| **합쳐서 보기 ON** | `construction_contract_grouped` | `initial_contract_date` | 장기=그룹 1행, 비장기=단건 1행, 동일 컬럼 |
| **펼쳐서 보기 OFF** | `construction_contract_flat` | `contract_date` | 계약 1건 = 1행 |

- 기간 조건: `[기간 필터 컬럼] BETWEEN :dateFrom AND :dateTo` (NULL이면 기간 미적용).
- 조회 시 **is_active = 'Y'** 인 행만 사용하는 것을 권장.

---

## 3. 테이블 컬럼 (API 응답 매핑 참고)

### 3.1 construction_contract_flat (펼쳐서 보기)

| DB 컬럼 | 타입 | 화면/API 용도 |
|---------|------|----------------|
| contract_no | VARCHAR(100) PK | 계약번호 |
| vendor_name | TEXT | 업체명 |
| contract_title | TEXT | 계약건명 |
| demand_agency_name | TEXT | 수요기관명 |
| demand_agency_region | VARCHAR(255) | 수요기관지역명 |
| public_procurement_category_name | TEXT | 품명내용 |
| bid_contract_method | VARCHAR(100) | 입찰계약방법 |
| bid_notice_no | VARCHAR(50) | 입찰공고번호 |
| first_contract_date | DATE | 최초계약일자 |
| first_contract_amount | BIGINT | 최초계약금액 |
| contract_date | DATE | 계약일자(기간 필터) |
| contract_amount | BIGINT | 계약금액(최종 1건) |
| latest_change_seq | BIGINT | 계약변경차수 |
| saved | CHAR(1) | 저장 체크박스 (Y/N) |
| vendor_biz_reg_no | VARCHAR(50) | (필요 시) 업체 식별 |
| initial_year_contract_no | VARCHAR(100) | (필요 시) 장기 그룹 키 |
| is_long_term_contract | CHAR(1) | 장기계약 여부 Y/N |

### 3.2 construction_contract_grouped (합쳐서 보기)

| DB 컬럼 | 타입 | 화면/API 용도 |
|---------|------|----------------|
| group_key | VARCHAR(100) PK | 그룹 식별자(장기=초년도계약번호, 비장기=계약번호) |
| vendor_name | TEXT | 업체명 |
| contract_title | TEXT | 계약건명 |
| demand_agency_name | TEXT | 수요기관명 |
| demand_agency_region | VARCHAR(255) | 수요기관지역명 |
| public_procurement_category_name | TEXT | 품명내용 |
| bid_contract_method | VARCHAR(100) | 입찰계약방법 |
| bid_notice_no | VARCHAR(50) | 입찰공고번호 |
| initial_contract_date | DATE | 최초계약일자(기간 필터) |
| initial_contract_amount | BIGINT | 최초계약금액 |
| final_contract_date | DATE | 최종계약일자 |
| final_contract_amount_sum | BIGINT | **최종계약금액(장기=합계, 단건=해당 금액)** |
| final_change_seq | BIGINT | 계약변경차수 |
| contract_count | INT | 그룹 내 건수(1=단건, 2+=장기) |
| is_long_term_contract | CHAR(1) | 장기계약 여부 Y/N |
| saved | CHAR(1) | 저장 체크박스 (Y/N) |

- **합쳐서 보기** 화면에서는 flat이 아닌 **grouped 한 테이블만** 조회하고, 위 컬럼을 그대로 노출하면 된다.  
  “최초계약일자” = initial_contract_date, “최종계약일자” = final_contract_date, “최종계약금액” = final_contract_amount_sum 로 매핑하면 됨.

---

## 4. API 설계 제안

- **목록 조회**  
  - 쿼리 파라미터 예: `grouped=true|false`, `dateFrom`, `dateTo`, `page`, `size`, 정렬 옵션 등.  
  - `grouped=true` → `construction_contract_grouped` 조회, 기간은 `initial_contract_date`  
  - `grouped=false` → `construction_contract_flat` 조회, 기간은 `contract_date`  
  - 공통: `is_active = 'Y'` 조건 적용.

- **저장(saved) 체크박스 갱신**  
  - `grouped=true` → `construction_contract_grouped.group_key` 기준으로 `saved` UPDATE  
  - `grouped=false` → `construction_contract_flat.contract_no` 기준으로 `saved` UPDATE  

- **엑셀/파일 다운로드**  
  - 목록과 동일: 토글 ON이면 grouped, OFF면 flat에서 같은 조건(기간 등)으로 조회한 결과를 그대로 다운로드.

---

## 5. 구현 시 유의사항

1. **테이블 2개만 사용**  
   화면/다운로드 모두 `construction_contract_flat` 또는 `construction_contract_grouped` 만 사용. raw, summary, history 테이블은 이 조회 화면과 연동하지 않는다.

2. **기간 필터**  
   - 합쳐서 보기: 반드시 `initial_contract_date`  
   - 펼쳐서 보기: 반드시 `contract_date`  
   서로 다른 컬럼이므로, 토글에 따라 쿼리(또는 JPA 조건)를 분기해야 한다.

3. **날짜/금액 타입**  
   DB는 DATE, BIGINT. API에서는 ISO 날짜 문자열, Long 또는 적절한 숫자 타입으로 매핑.

4. **동일 화면 레이아웃**  
   합쳐서 보기에서도 “최초계약일자·최종계약일자·최종계약금액·변경차수” 등 컬럼명을 grouped 컬럼(initial_contract_date, final_contract_date, final_contract_amount_sum, final_change_seq)에 맞춰 통일하면, 프론트는 토글만 바꿔도 같은 테이블/카드 UI를 재사용할 수 있다.

---

## 6. 정리 (체크리스트)

- [ ] 토글 ON → `construction_contract_grouped` 조회, 기간 필터 `initial_contract_date`
- [ ] 토글 OFF → `construction_contract_flat` 조회, 기간 필터 `contract_date`
- [ ] 목록·다운로드 모두 위 규칙 동일 적용
- [ ] saved 갱신 시 grouped면 group_key, flat이면 contract_no 기준 UPDATE
- [ ] is_active = 'Y' 조건 적용
- [ ] 응답 DTO는 두 테이블 컬럼을 위 표 기준으로 매핑 (필요 시 공통 DTO + grouped 전용 필드 분리)

---

위 설계대로 공사 계약 조회 API를 구현하고, 기존 화면이 이 API를 사용하도록 연동해줘.
