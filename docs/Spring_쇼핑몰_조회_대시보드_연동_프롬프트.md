# 쇼핑몰(3자단가) 조회 화면 + 대시보드 연동 – Spring Boot 개발 프롬프트

아래 내용을 **G2BPlatform Spring Boot + Vue 3 프로젝트에서 Cursor로 개발할 때** 복사해 붙여넣고,
"이 설계대로 API와 화면을 구현해줘"라고 요청하면 됩니다.

---

## [아래부터 복사]

---

## 0. 배경 및 목적

탑정보통신(사업자번호 1188119624)의 **종합쇼핑몰(제3자단가계약) 납품 실적**을 조회하는 화면과,
기존 물품 계약 데이터와 **통합하여 대시보드에 시각화**하는 기능을 구현한다.

- 쇼핑몰 데이터 = G2B 특정품목조달내역 중 `계약유형 = '제3자단가계약'`인 건만 해당
- 물품 데이터와 쇼핑몰 데이터는 **별도 조회 페이지**를 각각 제공하고,
  대시보드에서는 **dataSource 파라미터**로 전체/물품/쇼핑몰을 선택해 함께 시각화한다

---

## 1. 데이터 흐름

```
procurement_specific_item_raw (원본, 전체 특정품목조달내역)
  └─ WHERE contract_type = '제3자단가계약'
        ↓ sp_etl_shopping_mall()
shopping_mall_flat       ← 쇼핑몰 조회 화면 전용
        ↓ sp_refresh_shopping_mall_summary()
shopping_mall_summary    ← 대시보드 집계 전용
```

조회 화면과 API는 `shopping_mall_flat`을 직접 사용한다. raw는 직접 조회하지 않는다.

---

## 2. DB 테이블 구조

### 2.1 shopping_mall_flat (조회 화면용)

| DB 컬럼 | 타입 | 설명 |
|---|---|---|
| delivery_contract_no | VARCHAR(64) PK① | 납품요구번호 |
| delivery_contract_change_seq | INT PK② | 납품요구변경차수 |
| delivery_item_seq | INT PK③ | 납품요구물품순번 |
| vendor_biz_reg_no | VARCHAR(32) | 업체사업자등록번호 |
| vendor_name | VARCHAR(255) | 업체명 |
| contract_title | VARCHAR(500) | 계약명(요청명) |
| demand_agency_name | VARCHAR(255) | 수요기관명 |
| demand_agency_region | VARCHAR(255) | 수요기관지역 |
| contract_method | VARCHAR(128) | 계약방법 |
| contract_no | VARCHAR(64) | 계약번호(쇼핑몰 단가계약번호) |
| delivery_place_name | VARCHAR(500) | 납품장소명 |
| supervising_type | VARCHAR(64) | 소관구분 |
| company_type_at_contract | VARCHAR(64) | 기업형태구분 |
| item_category_no | VARCHAR(64) | 물품분류번호 |
| item_category_name | VARCHAR(255) | 물품분류명 |
| detail_item_no | VARCHAR(64) | 세부품명번호 |
| detail_item_name | VARCHAR(255) | 세부품명 |
| item_identifier_no | VARCHAR(64) | 물품식별번호 |
| item_identifier_name | VARCHAR(255) | 물품식별명 |
| unit | VARCHAR(255) | 납품단위명 |
| unit_price | BIGINT | 계약납품단가 |
| quantity | BIGINT | 납품수량 |
| supply_amount | BIGINT | 공급금액(단가×수량) |
| quantity_delta | BIGINT | 납품증감수량 |
| supply_amount_delta | BIGINT | 공급증감금액 |
| is_mas | VARCHAR(8) | MAS여부 |
| is_excellent_product | VARCHAR(8) | 우수제품여부 |
| is_direct_purchase_target | VARCHAR(8) | 직접구매대상여부 |
| ref_date | DATE | 납품요구결재일 **← 기간 필터 기준** |
| first_ref_date | DATE | 최초기준일자 |
| delivery_deadline_date | DATE | 납품기한일자 |
| is_active | CHAR(1) | 활성여부(Y만 조회) |

### 2.2 shopping_mall_summary (대시보드 집계용)

| DB 컬럼 | 타입 | 설명 |
|---|---|---|
| vendor_biz_reg_no | VARCHAR(32) PK① | 업체사업자등록번호 |
| item_category_no | VARCHAR(64) PK② | 물품분류번호 |
| detail_item_no | VARCHAR(64) PK③ | 세부품명번호 |
| ref_year_month | CHAR(7) PK④ | 기준연월(YYYY-MM) |
| vendor_name | VARCHAR(255) | 업체명 |
| demand_agency_name | VARCHAR(255) | 수요기관명 |
| demand_agency_region | VARCHAR(255) | 수요기관지역 |
| item_category_name | VARCHAR(255) | 물품분류명 |
| detail_item_name | VARCHAR(255) | 세부품명 |
| first_ref_date | DATE | 최초 납품요구결재일 **← 기간 필터 기준(from)** |
| final_ref_date | DATE | 최종 납품요구결재일 **← 기간 필터 기준(to)** |
| total_supply_amount | BIGINT | 공급금액 합계 |
| total_quantity | BIGINT | 납품수량 합계 |
| delivery_count | INT | 납품요구 건수 |
| is_mas | VARCHAR(8) | MAS여부 |
| is_excellent_product | VARCHAR(8) | 우수제품여부 |

---

## 3. 구현 대상 — 백엔드 (Spring Boot + MyBatis)

### 3.1 쇼핑몰 조회 API

**파일 위치 참고:**
- 기존 물품 API: `controller/ProcurementContractController.java`
- 기존 매퍼: `mapper/ProcurementContractFlatMapper.java` + `mapper/ProcurementContractFlatMapper.xml`

**새로 생성할 파일:**
```
controller/ShoppingMallController.java
service/ShoppingMallService.java
mapper/ShoppingMallMapper.java
resources/mapper/ShoppingMallMapper.xml
dto/ShoppingMallFlatDto.java
dto/ShoppingMallSearchDto.java
```

**API 엔드포인트:**

```
GET /api/shopping-mall/flat
  파라미터:
    - dateFrom (String, yyyy-MM-dd, 선택) — ref_date 기간 시작
    - dateTo   (String, yyyy-MM-dd, 선택) — ref_date 기간 종료
    - vendorBizRegNo (String, 선택) — 업체사업자등록번호
    - demandAgencyName (String, 선택) — 수요기관명 (LIKE 검색)
    - demandAgencyRegion (String, 선택) — 수요기관지역 (LIKE 검색)
    - itemCategoryNo (String, 선택) — 물품분류번호
    - detailItemNo (String, 선택) — 세부품명번호
    - isMas (String, 선택) — MAS여부 Y/N
    - isExcellentProduct (String, 선택) — 우수제품여부 Y/N
    - page (int, 기본값 1)
    - size (int, 기본값 50)
  응답: { content: [...], totalCount, page, size }
```

**ShoppingMallFlatDto 필드 (응답 JSON 키는 camelCase):**

```java
String deliveryContractNo
Integer deliveryContractChangeSeq
Integer deliveryItemSeq
String vendorBizRegNo
String vendorName
String contractTitle
String demandAgencyName
String demandAgencyRegion
String contractMethod
String contractNo
String deliveryPlaceName
String itemCategoryNo
String itemCategoryName
String detailItemNo
String detailItemName
String itemIdentifierNo
String itemIdentifierName
String unit
Long unitPrice
Long quantity
Long supplyAmount
String isMas
String isExcellentProduct
String isDirectPurchaseTarget
LocalDate refDate
LocalDate firstRefDate
LocalDate deliveryDeadlineDate
```

**MyBatis 쿼리 (`ShoppingMallMapper.xml`) 핵심 조건:**

```xml
<select id="selectFlatList" resultType="...ShoppingMallFlatDto">
  SELECT *
  FROM shopping_mall_flat
  WHERE is_active = 'Y'
  <if test="dateFrom != null and dateFrom != ''">
    AND ref_date >= #{dateFrom}
  </if>
  <if test="dateTo != null and dateTo != ''">
    AND ref_date &lt;= #{dateTo}
  </if>
  <if test="vendorBizRegNo != null and vendorBizRegNo != ''">
    AND vendor_biz_reg_no = #{vendorBizRegNo}
  </if>
  <if test="demandAgencyName != null and demandAgencyName != ''">
    AND demand_agency_name LIKE CONCAT('%', #{demandAgencyName}, '%')
  </if>
  <if test="demandAgencyRegion != null and demandAgencyRegion != ''">
    AND demand_agency_region LIKE CONCAT('%', #{demandAgencyRegion}, '%')
  </if>
  <if test="itemCategoryNo != null and itemCategoryNo != ''">
    AND item_category_no = #{itemCategoryNo}
  </if>
  <if test="detailItemNo != null and detailItemNo != ''">
    AND detail_item_no = #{detailItemNo}
  </if>
  <if test="isMas != null and isMas != ''">
    AND is_mas = #{isMas}
  </if>
  <if test="isExcellentProduct != null and isExcellentProduct != ''">
    AND is_excellent_product = #{isExcellentProduct}
  </if>
  ORDER BY ref_date DESC
  LIMIT #{offset}, #{size}
</select>
```

---

### 3.2 대시보드 API 확장

**기존 파일 수정:**
- `controller/ReportDataController.java`
- `service/ReportDataService.java`
- `mapper/ProcurementContractSummaryMapper.java`
- `resources/mapper/ProcurementContractSummaryMapper.xml`

**dataSource 파라미터 추가:**

```
GET /api/report/demand-agency-market
  기존 파라미터 유지 + 추가:
    - dataSource (String, 기본값 "procurement")
      "procurement"    → procurement_contract_summary만 조회 (기존 동작)
      "shopping_mall"  → shopping_mall_summary만 조회
      "all"            → 두 테이블 UNION ALL 조회

GET /api/report/region-market
  동일하게 dataSource 파라미터 추가
```

**수요기관별 (demand-agency-market) UNION ALL 쿼리 예시:**

```sql
-- dataSource = 'all' 일 때
SELECT demand_agency_name AS demandAgencyName,
       SUM(amount) AS salesAmount,
       COUNT(*) AS contractCount,
       SUM(amount) / COUNT(*) AS avgAmount
FROM (
  -- 물품
  SELECT demand_agency_name,
         IFNULL(final_contract_amount, 0) AS amount
  FROM procurement_contract_summary
  WHERE final_contract_date >= #{from}
    AND final_contract_date <= #{to}

  UNION ALL

  -- 쇼핑몰
  SELECT demand_agency_name,
         IFNULL(total_supply_amount, 0) AS amount
  FROM shopping_mall_summary
  WHERE final_ref_date >= #{from}
    AND final_ref_date <= #{to}
) combined
WHERE demand_agency_name IS NOT NULL AND demand_agency_name <> ''
GROUP BY demand_agency_name
ORDER BY salesAmount DESC
LIMIT #{topN}
```

**지역별 (region-market) UNION ALL 쿼리 예시:**

```sql
-- dataSource = 'all' 일 때
SELECT SUBSTRING_INDEX(COALESCE(NULLIF(TRIM(region), ''), '(미지정)'), ' ', 1) AS region,
       SUM(amount) AS salesAmount,
       COUNT(*) AS contractCount,
       SUM(amount) / COUNT(*) AS avgAmount
FROM (
  SELECT demand_agency_region AS region,
         IFNULL(final_contract_amount, 0) AS amount
  FROM procurement_contract_summary
  WHERE first_contract_date >= #{from}
    AND first_contract_date <= #{to}

  UNION ALL

  SELECT demand_agency_region AS region,
         IFNULL(total_supply_amount, 0) AS amount
  FROM shopping_mall_summary
  WHERE first_ref_date >= #{from}
    AND first_ref_date <= #{to}
) combined
GROUP BY SUBSTRING_INDEX(COALESCE(NULLIF(TRIM(region), ''), '(미지정)'), ' ', 1)
ORDER BY salesAmount DESC
```

---

## 4. 구현 대상 — 프론트엔드 (Vue 3 + Pinia)

### 4.1 쇼핑몰 조회 페이지 (신규)

**파일 위치 참고:**
- 기존 물품 조회: `src/views/ReportProcurementView.vue`
- 기존 용역 조회: `src/views/ReportServiceView.vue`

**새로 생성:**
```
src/views/ReportShoppingMallView.vue
```

**라우터 등록 (`src/router/index.js`):**
```js
{
  path: '/report-shopping-mall',
  name: 'ReportShoppingMall',
  component: () => import('@/views/ReportShoppingMallView.vue'),
  meta: { requiresAuth: true }
}
```

**사이드바 메뉴 추가 (`LegacySidebarLayout.vue` 또는 `MainLayoutView.vue`):**
- 기존 "보고서 > 물품" 항목 아래에 "보고서 > 쇼핑몰" 항목 추가

**화면 구성 (`ReportShoppingMallView.vue`):**

검색 필터:
- 기간 (ref_date 기준, dateFrom ~ dateTo, 날짜 picker)
- 수요기관명 (텍스트 검색)
- 수요기관지역 (텍스트 or 드롭다운)
- 물품분류번호 (텍스트)
- 세부품명번호 (텍스트)
- MAS여부 (드롭다운: 전체/Y/N)
- 우수제품여부 (드롭다운: 전체/Y/N)

테이블 컬럼 (DataTables):
| 컬럼명 | DB 필드 | 비고 |
|---|---|---|
| 납품요구결재일 | refDate | 기본 정렬 DESC |
| 수요기관명 | demandAgencyName | |
| 수요기관지역 | demandAgencyRegion | |
| 계약명(요청명) | contractTitle | |
| 물품분류명 | itemCategoryName | |
| 세부품명 | detailItemName | |
| 물품식별명 | itemIdentifierName | |
| 단가 | unitPrice | 숫자 포맷(,) |
| 수량 | quantity | 숫자 포맷(,) |
| 공급금액 | supplyAmount | 숫자 포맷(,) |
| MAS | isMas | |
| 우수제품 | isExcellentProduct | |
| 직접구매 | isDirectPurchaseTarget | |
| 업체명 | vendorName | |
| 납품장소명 | deliveryPlaceName | |

페이지네이션: 서버 사이드 (page, size 파라미터)

**API 호출 예시:**
```js
const fetchList = async () => {
  const { data } = await axios.get('/api/shopping-mall/flat', {
    params: {
      dateFrom: searchParams.dateFrom,
      dateTo: searchParams.dateTo,
      demandAgencyName: searchParams.demandAgencyName,
      itemCategoryNo: searchParams.itemCategoryNo,
      detailItemNo: searchParams.detailItemNo,
      isMas: searchParams.isMas,
      isExcellentProduct: searchParams.isExcellentProduct,
      page: currentPage.value,
      size: pageSize.value,
    }
  })
  rows.value = data.content
  totalCount.value = data.totalCount
}
```

---

### 4.2 대시보드 dataSource 필터 추가

**기존 파일 수정:**
```
src/views/ReportDashboardView.vue
```

**변경 사항:**

1. 대시보드 상단에 **데이터 소스 선택 탭 또는 세그먼트 버튼** 추가:
   ```
   [ 전체 ]  [ 물품 ]  [ 쇼핑몰 ]
   ```
   선택값은 `dataSource` ref (`'all'` | `'procurement'` | `'shopping_mall'`)로 관리

2. **수요기관별 탭** `fetchDemandAgencyMarket()` 함수에 `dataSource` 파라미터 추가:
   ```js
   const { data } = await axios.get('/api/report/demand-agency-market', {
     params: {
       dateBasis: 'FINAL',
       from: dashboardPeriod.value.from,
       to: dashboardPeriod.value.to,
       topN: 10,
       dataSource: dataSource.value,   // ← 추가
     }
   })
   ```

3. **지역별 탭** `fetchRegionMarket()` 함수에 동일하게 추가:
   ```js
   const { data } = await axios.get('/api/report/region-market', {
     params: {
       from: dashboardPeriod.value.from,
       to: dashboardPeriod.value.to,
       dataSource: dataSource.value,   // ← 추가
     }
   })
   ```

4. `dataSource` 값이 바뀔 때마다 현재 탭의 데이터를 재조회하도록 `watch` 추가:
   ```js
   watch(dataSource, () => {
     fetchDemandAgencyMarket()
     fetchRegionMarket()
   })
   ```

---

## 5. 구현 시 유의사항

### 5.1 금액 단위 차이
- `procurement_contract_summary.final_contract_amount` = 계약 전체 금액 (계약 단위)
- `shopping_mall_summary.total_supply_amount` = 단가 × 수량 합계 (납품요구 단위)
- UNION ALL 시 같은 `amount` 컬럼명으로 집계하지만, 대시보드 레전드나 툴팁에 **"물품: 계약금액 합계 / 쇼핑몰: 공급금액 합계"** 구분 표기 권장

### 5.2 날짜 기준 차이
- 물품: `contract_date` = 계약일
- 쇼핑몰: `ref_date` = 납품요구결재일
- `dataSource='all'` 일 때 UNION 쿼리에서 각 테이블의 날짜 컬럼에 맞게 기간 필터 적용

### 5.3 기존 코드 참고
- 물품 조회 API: `ProcurementContractFlatController.java` + `ProcurementContractFlatMapper.xml`
- 대시보드 API: `ReportDataController.java` + `ReportDataService.java` + `ProcurementContractSummaryMapper.xml`
- 물품 조회 Vue: `ReportProcurementView.vue` (검색 필터, DataTables 구조 동일하게 적용)

---

## 6. 실행 순서 (DB 적재)

쇼핑몰 데이터를 DB에 올리는 순서:

```sql
-- 1. 테이블 생성 (최초 1회)
SOURCE create_table_shopping_mall_flat.sql;
SOURCE create_table_shopping_mall_summary.sql;

-- 2. 프로시저 생성 (최초 1회 또는 변경 시)
SOURCE create_procedure_etl_shopping_mall.sql;
SOURCE create_procedure_refresh_shopping_mall_summary.sql;

-- 3. ETL 실행 (raw → flat, 시간 소요 있음)
CALL sp_etl_shopping_mall();

-- 4. summary 갱신 (flat → summary)
CALL sp_refresh_shopping_mall_summary();
```

이후 신규 CSV 적재 시: `specific_item_upload.py` 실행 → `CALL sp_etl_shopping_mall()` → `CALL sp_refresh_shopping_mall_summary()` 순서로 호출.

---

## 7. 체크리스트

- [ ] `ShoppingMallController` — `GET /api/shopping-mall/flat` 구현
- [ ] `ShoppingMallService` — 페이지네이션 + 검색 파라미터 처리
- [ ] `ShoppingMallMapper.xml` — 동적 WHERE 절 MyBatis 쿼리
- [ ] `ShoppingMallFlatDto` — DB 컬럼 ↔ JSON 필드 매핑
- [ ] `ReportDataController` — `dataSource` 파라미터 추가
- [ ] `ReportDataService` — dataSource 분기 로직 추가
- [ ] `ProcurementContractSummaryMapper.xml` — UNION ALL 쿼리 추가
- [ ] `ReportShoppingMallView.vue` — 조회 화면 신규 생성
- [ ] `router/index.js` — `/report-shopping-mall` 라우트 추가
- [ ] `LegacySidebarLayout.vue` — 사이드바 메뉴 추가
- [ ] `ReportDashboardView.vue` — dataSource 세그먼트 버튼 + watch 추가
