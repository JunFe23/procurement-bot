# 용역 계약 조회 화면 – Spring Boot 연동용 프롬프트

아래 내용을 **Spring Boot 프로젝트에서 Cursor로 개발할 때** 복사해 붙여넣고, "이 설계대로 조회 API와 화면 연동을 구현해줘"라고 요청하면 됩니다.

---

## [아래부터 복사]

---

## 0. 배경 및 목적

아래 **13개 소분류(기술용역)**에 해당하는 시장 전체 용역 계약을 조회하는 화면이다. 시장 조사 목적.

| 중분류 | 소분류 (public_procurement_category) |
|--------|---------------------------------------|
| 설계 | 토목설계용역, 건축설계용역, 상하수도설계용역, 전기설계용역, 교통설계용역, 정보통신설계용역 |
| 감리 | 건축감리용역, 토목감리용역, 전기감리용역, 정보통신감리용역 |
| CM | 건축CM용역, 토목CM용역 |
| 기타 | 기타기술용역 |

공동수급이어도 **계약별로 1건**으로 표시한다 (공사 데이터와 동일한 방식). 업체별 구분이나 공동수급 여부 식별은 하지 않는다.

---

## 1. 데이터 흐름 (백그라운드)

- **원본**: `service_contract_raw` — CSV 적재용. 화면/API는 이 테이블을 직접 조회하지 않는다.
- **조회용 테이블 2개** (ETL `sp_etl_service_contracts()` 로 채움):
  - **`service_contract_flat`** — 계약납품통합번호당 최종 **1건 1행**. **펼쳐서 보기**용. 공동수급이어도 max change_seq 1행으로 통합.
  - **`service_contract_grouped`** — flat을 초년도계약번호(group_key) 기준으로 묶어 집계한 결과. **합쳐서 보기**용. 장기계속계약은 그룹 1행(금액 합계), 비장기는 단건 1행.

- **공사와 동일한 구조**: 계약 1건 = 1행. 공동수급이어도 `contract_delivery_integrated_no`당 max change_seq 1행으로 저장. 업체별 구분 없음.

---

## 2. 토글에 따른 조회 테이블·기간 필터

| 화면 토글 | 사용 테이블 | 기간 필터 컬럼 | 비고 |
|-----------|-------------|----------------|------|
| **합쳐서 보기 ON** | `service_contract_grouped` | `initial_contract_date` | 장기=그룹 1행, 비장기=단건 1행 |
| **펼쳐서 보기 OFF** | `service_contract_flat` | `contract_date` | 계약납품통합번호당 1행 |

- 기간 조건: `[기간 필터 컬럼] BETWEEN :dateFrom AND :dateTo` (NULL이면 기간 미적용).
- 조회 시 **is_active = 'Y'** 인 행만 사용.

---

## 3. 테이블 컬럼 (API 응답 매핑 참고)

### 3.1 service_contract_flat (펼쳐서 보기)

| DB 컬럼 | 타입 | 화면/API 용도 |
|---------|------|----------------|
| contract_delivery_integrated_no | VARCHAR(100) PK | 계약납품통합번호 |
| vendor_biz_reg_no | VARCHAR(50) | 업체사업자등록번호 |
| vendor_name | TEXT | 업체명 |
| contract_title | TEXT | 계약명 |
| demand_agency | TEXT | 수요기관명 |
| demand_agency_region | VARCHAR(200) | 수요기관지역 |
| contract_method | VARCHAR(50) | 계약방법 |
| contract_type | VARCHAR(50) | 계약유형 |
| procurement_work_area | VARCHAR(50) | 조달업무영역 (일반용역/기술용역) |
| bid_notice_no | VARCHAR(50) | 입찰공고번호 |
| initial_year_contract_no | VARCHAR(100) | 초년도계약번호 (장기 그룹 키) |
| is_long_term | CHAR(1) | 장기계속여부 Y/N |
| representative_item_category_code | VARCHAR(50) | 대표물품분류코드 (용역은 보통 NULL) |
| representative_item_category | VARCHAR(200) | 대표물품분류명 (용역은 보통 NULL) |
| detail_item_code | VARCHAR(50) | 세부품명코드 (용역은 보통 NULL) |
| detail_item_name | VARCHAR(200) | 세부품명 (용역은 보통 NULL) |
| public_procurement_category | VARCHAR(50) | **소분류명** (e.g. 토목설계용역) — 소분류 필터 기준 컬럼 |
| public_procurement_category_major | VARCHAR(100) | 대분류명 (현재 모두 '기술용역') |
| public_procurement_category_mid | VARCHAR(100) | 중분류명 (설계/감리/CM/기타) — 중분류 필터 기준 컬럼 |
| first_contract_date | DATE | 최초기준일자 |
| contract_date | DATE | 기준일자 (기간 필터) |
| start_date | DATE | 착수일자 |
| completion_date | DATE | 완수일자 |
| first_contract_amount | BIGINT | 최초계약금액 |
| contract_amount | BIGINT | 계약금액 |
| latest_change_seq | BIGINT | 반영된 계약납품통합변경차수 |
| saved | CHAR(1) | 저장 체크박스 (Y/N) |

### 3.2 service_contract_grouped (합쳐서 보기)

| DB 컬럼 | 타입 | 화면/API 용도 |
|---------|------|----------------|
| group_key | VARCHAR(100) PK | COALESCE(초년도계약번호, 계약납품통합번호) |
| vendor_biz_reg_no | VARCHAR(50) | 업체사업자등록번호 |
| vendor_name | TEXT | 업체명 |
| contract_title | TEXT | 계약명 (그룹 내 최초 계약 기준) |
| demand_agency | TEXT | 수요기관명 |
| demand_agency_region | VARCHAR(200) | 수요기관지역 |
| contract_method | VARCHAR(50) | 계약방법 |
| procurement_work_area | VARCHAR(50) | 조달업무영역 |
| detail_item_code | VARCHAR(50) | 세부품명코드 (용역은 보통 NULL) |
| detail_item_name | VARCHAR(200) | 세부품명 (용역은 보통 NULL) |
| initial_contract_date | DATE | 그룹 최초 계약일 (기간 필터) |
| initial_contract_amount | BIGINT | 그룹 최초 계약금액 |
| final_contract_date | DATE | 그룹 최종 계약일 |
| final_contract_amount_sum | BIGINT | **그룹 전체 계약금액 합계 (장기=합계, 단건=해당 금액)** |
| contract_count | INT | 그룹 내 계약 건수 (1=단건, 2+=장기계속) |
| is_long_term | CHAR(1) | 장기계속여부 Y/N |
| saved | CHAR(1) | 저장 체크박스 (Y/N) |

---

## 4. API 설계 제안

- **목록 조회**
  - 쿼리 파라미터: `grouped=true|false`, `dateFrom`, `dateTo`, `page`, `size`, 정렬 옵션 등.
  - `grouped=true`  → `service_contract_grouped` 조회, 기간 필터 `initial_contract_date`
  - `grouped=false` → `service_contract_flat` 조회, 기간 필터 `contract_date`
  - 공통: `is_active = 'Y'` 조건 적용.

- **저장(saved) 체크박스 갱신**
  - `grouped=true`  → `service_contract_grouped` UPDATE — PK: **group_key** 단일 컬럼
  - `grouped=false` → `service_contract_flat` UPDATE — PK: **contract_delivery_integrated_no** 단일 컬럼

- **엑셀/파일 다운로드**
  - 목록과 동일: 토글 ON이면 grouped, OFF이면 flat에서 같은 조건으로 조회한 결과를 그대로 다운로드.

---

## 5. 구현 시 유의사항

1. **테이블 2개만 사용**
   화면/다운로드 모두 `service_contract_flat` 또는 `service_contract_grouped` 만 사용. `service_contract_raw` 는 이 조회 화면과 연동하지 않는다.

2. **기간 필터 컬럼이 다름**
   - 합쳐서 보기: 반드시 `initial_contract_date`
   - 펼쳐서 보기: 반드시 `contract_date`
   토글에 따라 쿼리(또는 JPA 조건)를 반드시 분기할 것.

3. **PK는 단일 컬럼**
   - flat: `contract_delivery_integrated_no` 단일 PK
   - grouped: `group_key` 단일 PK
   공사·물품과 동일한 단일 PK 구조이므로 saved 갱신 시 해당 컬럼 1개만 WHERE 조건으로 사용.

4. **공동수급 처리 방식**
   공동수급 계약이어도 `contract_delivery_integrated_no`당 max change_seq 행 1건만 저장한다 (공사와 동일). 업체별 구분이나 공동수급 식별 없음. **is_joint_venture 컬럼은 존재하지 않는다.**

5. **날짜·금액 타입**
   DB는 DATE, BIGINT. API에서는 ISO 날짜 문자열, Long 또는 적절한 숫자 타입으로 매핑.

6. **동일 화면 레이아웃 재사용**
   합쳐서 보기에서도 "최초계약일자·최종계약일자·최종계약금액·계약건수" 컬럼을 grouped 컬럼(initial_contract_date, final_contract_date, final_contract_amount_sum, contract_count)에 매핑하면, 프론트는 토글만 바꿔도 같은 테이블/카드 UI를 재사용할 수 있다.

7. **용역 전용 추가 필터 (권장)**
   - `public_procurement_category_mid` (중분류: 설계 / 감리 / CM / 기타) — 드롭다운 필터
   - `public_procurement_category` (소분류: 토목설계용역 등 13종) — 드롭다운 필터
   - `is_long_term` (장기계속 여부 Y/N)
   - `vendor_name` (업체명 검색)
   - `demand_agency` (수요기관명 검색)

---

## 6. 정리 (체크리스트)

- [ ] 토글 ON  → `service_contract_grouped` 조회, 기간 필터 `initial_contract_date`
- [ ] 토글 OFF → `service_contract_flat` 조회, 기간 필터 `contract_date`
- [ ] 목록·다운로드 모두 위 규칙 동일 적용
- [ ] saved 갱신 — grouped: `group_key` 단일 컬럼 UPDATE
- [ ] saved 갱신 — flat: `contract_delivery_integrated_no` 단일 컬럼 UPDATE
- [ ] is_active = 'Y' 조건 적용
- [ ] 공동수급 포함 모든 계약: 계약 단위 1건 1행 (공사와 동일, 업체별 구분 없음, is_joint_venture 컬럼 없음)
- [ ] 응답 DTO는 두 테이블 컬럼을 위 표 기준으로 매핑 (공통 DTO + flat/grouped 전용 필드 분리 고려)

---

위 설계대로 용역 계약 조회 API를 구현하고, 기존 공사·물품 조회 화면과 동일한 구조로 용역 조회 화면을 연동해줘.
기존 화면 코드를 참고해서 동일한 레이아웃·검색 조건으로 만들되, 테이블명·컬럼명·PK만 위 설계에 맞게 교체하면 된다.
