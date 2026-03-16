# 물품 계약 조회 화면 – Spring Boot 연동용 프롬프트

아래 내용을 **Spring Boot 프로젝트에서 Cursor로 개발할 때** 복사해 붙여넣고, "이 설계대로 조회 API와 화면 연동을 구현해줘"라고 요청하면 됩니다.

---

## [아래부터 복사]

---

## 0. 배경 및 목적

탑인더스트리(사업자번호 1188117437), 탑정보통신(1188119624)이 체결한 물품 계약의 **물품분류번호·세부품명번호 조합과 동일한 품목을 가진 시장 전체 계약**을 조회하는 화면이다. 시장 조사 목적이며, 두 회사의 계약도 포함된다.

---

## 1. 데이터 흐름 (백그라운드)

- **원본**: `procurement_raw` — CSV 적재용. 화면/API는 이 테이블을 직접 조회하지 않는다.
- **조회용 테이블 2개** (ETL `sp_etl_procurement_contracts()` 로 채움):
  - **`procurement_contract_flat`** — (contract_no, item_seq)당 최종 1건. **펼쳐서 보기**용. 아이템 단위 상세 조회.
  - **`procurement_contract_grouped`** — flat을 (bid_notice_no + vendor_biz_reg_no) 기준으로 묶어 집계한 결과. **합쳐서 보기**용. 장기계약은 그룹 1행(금액 합계), 비장기계약은 단건 1행, **같은 컬럼 구조**.

화면은 **토글 값에 따라** 둘 중 하나의 테이블만 조회하면 된다. raw를 직접 집계하지 말 것.

---

## 2. 토글에 따른 조회 테이블·기간 필터

| 화면 토글 | 사용 테이블 | 기간 필터 컬럼 | 비고 |
|-----------|-------------|----------------|------|
| **합쳐서 보기 ON** | `procurement_contract_grouped` | `initial_contract_date` | 장기=그룹 1행, 비장기=단건 1행, 동일 컬럼 |
| **펼쳐서 보기 OFF** | `procurement_contract_flat` | `contract_date` | (contract_no, item_seq) = 1행 |

- 기간 조건: `[기간 필터 컬럼] BETWEEN :dateFrom AND :dateTo` (NULL이면 기간 미적용).
- 조회 시 **is_active = 'Y'** 인 행만 사용.

---

## 3. 테이블 컬럼 (API 응답 매핑 참고)

### 3.1 procurement_contract_flat (펼쳐서 보기)

| DB 컬럼 | 타입 | 화면/API 용도 |
|---------|------|----------------|
| contract_no | VARCHAR(100) PK① | 계약번호 |
| item_seq | BIGINT PK② | 물품순번 |
| vendor_biz_reg_no | VARCHAR(50) | 업체사업자등록번호 |
| vendor_name | TEXT | 업체명 |
| contract_title | TEXT | 계약명 |
| demand_agency_name | TEXT | 수요기관명 |
| demand_agency_region | VARCHAR(100) | 수요기관지역명 |
| contract_method | VARCHAR(100) | 계약방법명 |
| bid_notice_no | VARCHAR(50) | 입찰공고번호 |
| item_category_no | VARCHAR(20) | 물품분류번호 |
| item_category_name | TEXT | 물품분류명 |
| detail_item_no | VARCHAR(50) | 세부품명번호 |
| detail_item_name | TEXT | 세부품명 |
| item_identifier_no | VARCHAR(50) | 물품식별번호 |
| item_identifier_name | TEXT | 물품식별명 |
| unit | VARCHAR(100) | 단위 |
| unit_price | BIGINT | 단가 |
| quantity | BIGINT | 수량 |
| is_mas | VARCHAR(10) | MAS여부 |
| is_excellent_product | VARCHAR(10) | 우수제품여부 |
| is_sme_competitive | VARCHAR(10) | 중기간경쟁물품여부 |
| first_contract_date | DATE | 최초계약일자 |
| contract_date | DATE | 계약일자(기간 필터) |
| contract_amount | BIGINT | 계약금액 |
| latest_change_seq | BIGINT | 계약변경차수 |
| is_long_term | CHAR(1) | 장기계속여부 Y/N |
| saved | CHAR(1) | 저장 체크박스 (Y/N) |

### 3.2 procurement_contract_grouped (합쳐서 보기)

| DB 컬럼 | 타입 | 화면/API 용도 |
|---------|------|----------------|
| bid_notice_no | VARCHAR(50) PK① | 입찰공고번호(없으면 빈값 '') |
| vendor_biz_reg_no | VARCHAR(50) PK② | 업체사업자등록번호 |
| contract_no | VARCHAR(100) PK③ | 계약번호(공고없으면 실제값, 공고있으면 '') |
| vendor_name | TEXT | 업체명 |
| contract_title | TEXT | 계약명 |
| demand_agency_name | TEXT | 수요기관명 |
| demand_agency_region | VARCHAR(100) | 수요기관지역명 |
| contract_method | VARCHAR(100) | 계약방법명 |
| detail_item_name | TEXT | 세부품명(최초 계약 기준) |
| initial_contract_date | DATE | 최초계약일자(기간 필터) |
| initial_contract_amount | BIGINT | 최초계약금액 |
| final_contract_date | DATE | 최종계약일자 |
| final_contract_amount_sum | BIGINT | **최종계약금액(장기=합계, 단건=해당 금액)** |
| contract_count | INT | 그룹 내 계약 건수(1=단건, 2+=장기) |
| is_long_term | CHAR(1) | 장기계속여부 Y/N |
| saved | CHAR(1) | 저장 체크박스 (Y/N) |

---

## 4. API 설계 제안

- **목록 조회**
  - 쿼리 파라미터: `grouped=true|false`, `dateFrom`, `dateTo`, `page`, `size`, 정렬 옵션 등.
  - `grouped=true`  → `procurement_contract_grouped` 조회, 기간 필터 `initial_contract_date`
  - `grouped=false` → `procurement_contract_flat` 조회, 기간 필터 `contract_date`
  - 공통: `is_active = 'Y'` 조건 적용.

- **저장(saved) 체크박스 갱신**
  - `grouped=true`  → `procurement_contract_grouped` 기준 UPDATE — PK는 **(bid_notice_no, vendor_biz_reg_no, contract_no)** 복합키
  - `grouped=false` → `procurement_contract_flat` 기준 UPDATE — PK는 **(contract_no, item_seq)** 복합키

- **엑셀/파일 다운로드**
  - 목록과 동일: 토글 ON이면 grouped, OFF이면 flat에서 같은 조건으로 조회한 결과를 그대로 다운로드.

---

## 5. 구현 시 유의사항

1. **테이블 2개만 사용**
   화면/다운로드 모두 `procurement_contract_flat` 또는 `procurement_contract_grouped` 만 사용. `procurement_raw`, `procurement_contract_summary` 는 이 조회 화면과 연동하지 않는다.

2. **기간 필터 컬럼이 다름**
   - 합쳐서 보기: 반드시 `initial_contract_date`
   - 펼쳐서 보기: 반드시 `contract_date`
   토글에 따라 쿼리(또는 JPA 조건)를 반드시 분기할 것.

3. **grouped PK가 복합키 3개**
   `(bid_notice_no, vendor_biz_reg_no, contract_no)` 세 컬럼이 묶여서 PK. saved 갱신 시 세 컬럼을 모두 WHERE 조건으로 사용해야 한다.
   - `bid_notice_no = ''` (빈값)이면 공고번호 없는 계약 — `contract_no` 로 구분.
   - `bid_notice_no != ''` 이면 공고번호 있는 계약 — `contract_no = ''` (빈값).

4. **flat PK도 복합키 2개**
   `(contract_no, item_seq)`. 동일한 contract_no 하에 item_seq가 다른 행이 여러 개 존재할 수 있다. saved 갱신 시 두 컬럼 모두 필요.

5. **날짜·금액 타입**
   DB는 DATE, BIGINT. API에서는 ISO 날짜 문자열, Long 또는 적절한 숫자 타입으로 매핑.

6. **동일 화면 레이아웃 재사용**
   합쳐서 보기에서도 "최초계약일자·최종계약일자·최종계약금액·계약건수" 컬럼을 grouped 컬럼(initial_contract_date, final_contract_date, final_contract_amount_sum, contract_count)에 매핑하면, 프론트는 토글만 바꿔도 같은 테이블/카드 UI를 재사용할 수 있다.

7. **기존 공사 화면과 동일 검색 조건**
   화면의 검색 파라미터(기간, 업체명, 수요기관명 등)는 기존 공사 조회 화면과 동일한 구조를 사용하면 된다. 단, 물품 화면에서만 추가로 `detail_item_name`, `item_category_no` 등 물품 관련 필터를 선택적으로 추가할 수 있다.

---

## 6. 정리 (체크리스트)

- [ ] 토글 ON  → `procurement_contract_grouped` 조회, 기간 필터 `initial_contract_date`
- [ ] 토글 OFF → `procurement_contract_flat` 조회, 기간 필터 `contract_date`
- [ ] 목록·다운로드 모두 위 규칙 동일 적용
- [ ] saved 갱신 — grouped: (bid_notice_no, vendor_biz_reg_no, contract_no) 3개 컬럼 UPDATE
- [ ] saved 갱신 — flat: (contract_no, item_seq) 2개 컬럼 UPDATE
- [ ] is_active = 'Y' 조건 적용
- [ ] 응답 DTO는 두 테이블 컬럼을 위 표 기준으로 매핑 (공통 DTO + flat/grouped 전용 필드 분리 고려)

---

위 설계대로 물품 계약 조회 API를 구현하고, 기존 공사 조회 화면과 동일한 구조로 물품 조회 화면을 연동해줘.
기존 공사 화면 코드를 참고해서 동일한 레이아웃·검색 조건으로 만들되, 테이블명·컬럼명·PK만 위 설계에 맞게 교체하면 된다.
