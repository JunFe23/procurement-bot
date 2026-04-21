# 대시보드 시장현황 탭 구현 프롬프트
## G2BPlatform — Spring Boot + Vue 3 + MyBatis

아래 내용을 Cursor AI에 붙여넣고 "이 설계대로 구현해줘"라고 요청하세요.

---

## [아래부터 복사]

---

## 0. 배경 및 목적

`ReportDashboardView.vue`의 **시장현황 탭**에서 물품 / 3자단가 / 용역 / 공사 체크박스를
복수 선택하면, 선택한 데이터 소스들의 집계 결과가 아래 4개 차트 영역에 **동적으로 반영**되도록
백엔드 API와 프론트엔드를 완성한다.

현재 상태:
- `/api/report/market` 엔드포인트는 존재하지만 `getMarketOverview()`가 **빈 데이터**만 반환
- 프론트엔드 `loadDashboardData()`와 `watch(marketDataSources, ...)` 모두 **TODO 상태**
- 시장현황 탭 차트 데이터는 전부 **정적 목업값**으로 하드코딩

---

## 1. 프로젝트 파일 경로

```
backend/src/main/java/org/example/g2bplatform/
  controller/ReportDataController.java          ← 수정
  service/ReportDataService.java                ← 수정
  mapper/ProcurementContractSummaryMapper.java  ← 수정

backend/src/main/resources/org/example/g2bplatform/mapper/
  ProcurementContractSummaryMapper.xml          ← 쿼리 추가

frontend/src/views/
  ReportDashboardView.vue                       ← 수정
```

---

## 2. 시장현황 탭 UI 구성 (구현 목표)

```
[체크박스 필터]  ☑ 물품  ☑ 3자단가  ☑ 용역  ☑ 공사

┌──────────────────────────────────────────────┐
│ 요약 카드 4개                                  │
│  전체 매출액 | 전체 계약건수 | 평균 계약금액 | 우수제품 비율 │
└──────────────────────────────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐
│ 영역별 매출액 현황   │  │ 영역별 계약건수      │
│ (세로 바 차트)       │  │ (세로 바 차트)       │
│ 체크된 소스별 막대   │  │ 체크된 소스별 막대   │
└─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐
│ 물품+3자단가         │  │ 영역별 상세 현황     │
│ 우수제품 vs 일반제품 │  │ (리스트: 건수+금액)  │
│ (도넛 차트 텍스트)   │  │                     │
└─────────────────────┘  └─────────────────────┘
```

체크박스 값:
- `procurement`    → 물품       → `procurement_contract_summary`
- `shopping_mall`  → 3자단가    → `shopping_mall_summary`
- `service`        → 용역       → `service_contract_grouped`
- `construction`   → 공사       → `construction_contract_grouped`

---

## 3. API 설계

### 엔드포인트

```
GET /api/report/market
  파라미터:
    - from      (String, yyyy-MM-dd, 필수)
    - to        (String, yyyy-MM-dd, 필수)
    - sources   (String, 쉼표 구분, 기본값 "procurement,shopping_mall,service,construction")
                예: sources=procurement,shopping_mall
```

### 응답 구조

```json
{
  "success": true,
  "data": {
    "perSource": {
      "procurement": {
        "salesAmount": 5000000000,
        "contractCount": 5,
        "excellentAmount": 4900000000,
        "generalAmount": 100000000
      },
      "shopping_mall": {
        "salesAmount": 500000000,
        "contractCount": 17,
        "excellentAmount": 410000000,
        "generalAmount": 90000000
      },
      "service": {
        "salesAmount": 1710000000,
        "contractCount": 8,
        "excellentAmount": 0,
        "generalAmount": 0
      },
      "construction": {
        "salesAmount": 6450000000,
        "contractCount": 7,
        "excellentAmount": 0,
        "generalAmount": 0
      }
    },
    "condition": {
      "from": "2025-01-01",
      "to": "2025-12-31",
      "sources": ["procurement", "shopping_mall", "service", "construction"]
    }
  }
}
```

**소스가 체크되지 않은 경우:** 해당 key는 응답에 포함하지 않거나 null로 반환.

---

## 4. DB 쿼리 설계

### 4.1 물품 집계 (procurement_contract_summary)

```sql
-- selectMarketSourceProcurement
SELECT
    IFNULL(SUM(final_contract_amount), 0)                                        AS salesAmount,
    COUNT(*)                                                                       AS contractCount
FROM procurement_contract_summary
WHERE final_contract_date >= #{from}
  AND final_contract_date <= #{to}
```

**우수제품 집계 (procurement_contract_flat에서 별도 조회)**

`procurement_contract_summary`에는 `is_excellent_product` 컬럼이 없으므로
`procurement_contract_flat`에서 아이템 단위 공급금액을 합산한다.

```sql
-- selectMarketExcellentProcurement
SELECT
    is_excellent_product                                                           AS excellentFlag,
    IFNULL(SUM(contract_amount), 0)                                               AS amount
FROM procurement_contract_flat
WHERE is_active = 'Y'
  AND contract_date >= #{from}
  AND contract_date <= #{to}
GROUP BY is_excellent_product
```

### 4.2 3자단가 집계 (shopping_mall_summary)

```sql
-- selectMarketSourceShoppingMall
SELECT
    IFNULL(SUM(total_supply_amount), 0)                                           AS salesAmount,
    IFNULL(SUM(delivery_count), 0)                                                AS contractCount,
    IFNULL(SUM(CASE WHEN is_excellent_product = 'Y'
                    THEN total_supply_amount ELSE 0 END), 0)                      AS excellentAmount,
    IFNULL(SUM(CASE WHEN is_excellent_product != 'Y' OR is_excellent_product IS NULL
                    THEN total_supply_amount ELSE 0 END), 0)                      AS generalAmount
FROM shopping_mall_summary
WHERE final_ref_date >= #{from}
  AND final_ref_date <= #{to}
```

### 4.3 용역 집계 (service_contract_grouped)

```sql
-- selectMarketSourceService
SELECT
    IFNULL(SUM(final_contract_amount_sum), 0)                                     AS salesAmount,
    COUNT(*)                                                                       AS contractCount
FROM service_contract_grouped
WHERE is_active = 'Y'
  AND final_contract_date >= #{from}
  AND final_contract_date <= #{to}
```

### 4.4 공사 집계 (construction_contract_grouped)

```sql
-- selectMarketSourceConstruction
SELECT
    IFNULL(SUM(final_contract_amount_sum), 0)                                     AS salesAmount,
    COUNT(*)                                                                       AS contractCount
FROM construction_contract_grouped
WHERE is_active = 'Y'
  AND final_contract_date >= #{from}
  AND final_contract_date <= #{to}
```

---

## 5. MyBatis Mapper 수정

### 5.1 ProcurementContractSummaryMapper.java에 메서드 추가

```java
// 시장현황: 물품 집계
Map<String, Object> selectMarketSourceProcurement(
    @Param("from") String from,
    @Param("to") String to
);

// 시장현황: 물품 우수제품 집계 (flat 테이블)
List<Map<String, Object>> selectMarketExcellentProcurement(
    @Param("from") String from,
    @Param("to") String to
);

// 시장현황: 3자단가 집계
Map<String, Object> selectMarketSourceShoppingMall(
    @Param("from") String from,
    @Param("to") String to
);

// 시장현황: 용역 집계
Map<String, Object> selectMarketSourceService(
    @Param("from") String from,
    @Param("to") String to
);

// 시장현황: 공사 집계
Map<String, Object> selectMarketSourceConstruction(
    @Param("from") String from,
    @Param("to") String to
);
```

### 5.2 ProcurementContractSummaryMapper.xml에 쿼리 추가

위 4.1 ~ 4.4 쿼리를 각각 id로 등록한다.

---

## 6. ReportDataService.java 수정

기존 `getMarketOverview()`를 파라미터를 받는 메서드로 교체한다.

```java
/**
 * 시장현황 탭 집계.
 * @param from    yyyy-MM-dd (필수)
 * @param to      yyyy-MM-dd (필수)
 * @param sources 쉼표 구분 소스 목록 (procurement, shopping_mall, service, construction)
 */
public Map<String, Object> getMarketOverview(String from, String to, String sources) {
    // 날짜 파싱/검증 (기존 getDemandAgencyMarket 방식과 동일)
    if (from == null || from.isBlank()) throw new IllegalArgumentException("from은 필수입니다");
    if (to == null || to.isBlank())   throw new IllegalArgumentException("to는 필수입니다");
    try {
        LocalDate f = LocalDate.parse(from.trim());
        LocalDate t = LocalDate.parse(to.trim());
        if (f.isAfter(t)) throw new IllegalArgumentException("from은 to보다 클 수 없습니다");
    } catch (DateTimeParseException e) {
        throw new IllegalArgumentException("날짜 형식 오류 (yyyy-MM-dd)");
    }

    // sources 파싱
    Set<String> sourceSet = new HashSet<>();
    if (sources != null && !sources.isBlank()) {
        for (String s : sources.split(",")) {
            String t = s.trim().toLowerCase();
            if (Set.of("procurement","shopping_mall","service","construction").contains(t)) {
                sourceSet.add(t);
            }
        }
    }
    if (sourceSet.isEmpty()) {
        sourceSet = Set.of("procurement","shopping_mall","service","construction");
    }

    Map<String, Object> perSource = new LinkedHashMap<>();

    // 물품
    if (sourceSet.contains("procurement")) {
        Map<String, Object> row = procurementContractSummaryMapper.selectMarketSourceProcurement(from, to);
        // 우수제품 집계는 procurement_contract_flat에서 조회
        List<Map<String, Object>> excellent = procurementContractSummaryMapper.selectMarketExcellentProcurement(from, to);
        long excellentAmt = 0L, generalAmt = 0L;
        for (Map<String, Object> r : excellent) {
            String flag = String.valueOf(r.getOrDefault("excellentFlag", ""));
            long amt = toLong(r.get("amount"));
            if ("Y".equalsIgnoreCase(flag)) excellentAmt += amt;
            else generalAmt += amt;
        }
        if (row != null) {
            row.put("excellentAmount", excellentAmt);
            row.put("generalAmount", generalAmt);
        }
        perSource.put("procurement", row);
    }

    // 3자단가
    if (sourceSet.contains("shopping_mall")) {
        perSource.put("shopping_mall", procurementContractSummaryMapper.selectMarketSourceShoppingMall(from, to));
    }

    // 용역
    if (sourceSet.contains("service")) {
        Map<String, Object> row = procurementContractSummaryMapper.selectMarketSourceService(from, to);
        if (row != null) { row.put("excellentAmount", 0L); row.put("generalAmount", 0L); }
        perSource.put("service", row);
    }

    // 공사
    if (sourceSet.contains("construction")) {
        Map<String, Object> row = procurementContractSummaryMapper.selectMarketSourceConstruction(from, to);
        if (row != null) { row.put("excellentAmount", 0L); row.put("generalAmount", 0L); }
        perSource.put("construction", row);
    }

    List<String> resolvedSources = new ArrayList<>(sourceSet);
    Map<String, Object> condition = new LinkedHashMap<>();
    condition.put("from", from);
    condition.put("to", to);
    condition.put("sources", resolvedSources);

    Map<String, Object> data = new LinkedHashMap<>();
    data.put("perSource", perSource);
    data.put("condition", condition);

    return wrap(data);
}

/** Number 변환 헬퍼 */
private long toLong(Object v) {
    if (v == null) return 0L;
    try { return Long.parseLong(v.toString()); } catch (Exception e) { return 0L; }
}
```

---

## 7. ReportDataController.java 수정

기존 `/api/report/market` 엔드포인트를 아래로 교체한다.

```java
@Operation(summary = "시장현황 데이터", description = "체크된 소스(물품/3자단가/용역/공사)의 기간별 집계")
@GetMapping("/market")
public ResponseEntity<Map<String, Object>> getMarketOverview(
    @Parameter(description = "기간 시작 (yyyy-MM-dd)") @RequestParam String from,
    @Parameter(description = "기간 종료 (yyyy-MM-dd)")  @RequestParam String to,
    @Parameter(description = "소스 목록 (쉼표 구분: procurement,shopping_mall,service,construction)")
    @RequestParam(required = false, defaultValue = "procurement,shopping_mall,service,construction")
    String sources
) {
    try {
        return ResponseEntity.ok(reportDataService.getMarketOverview(from, to, sources));
    } catch (IllegalArgumentException e) {
        Map<String, Object> err = new HashMap<>();
        err.put("success", false);
        err.put("message", e.getMessage());
        return ResponseEntity.badRequest().body(err);
    }
}
```

---

## 8. Vue 프론트엔드 수정 (ReportDashboardView.vue)

### 8.1 추가할 반응형 상태

```javascript
// 시장현황 로딩/에러 상태
const marketLoading = ref(false)
const marketError   = ref('')
const marketLoaded  = ref(false)
```

### 8.2 loadMarketData() 함수 (loadDashboardData 교체)

```javascript
const loadMarketData = async () => {
  const { from, to } = dashboardPeriod.value
  const sourcesParam = marketDataSources.value.join(',')

  marketLoading.value = true
  marketError.value   = ''
  try {
    const { data } = await axios.get('/api/report/market', {
      params: { from, to, sources: sourcesParam },
    })
    if (!data || data.success !== true || !data.data) {
      throw new Error('API 응답 형식이 올바르지 않습니다.')
    }
    applyMarketData(data.data)
    marketLoaded.value = true
  } catch (e) {
    marketError.value = e?.message || '시장현황 데이터 조회 실패'
  } finally {
    marketLoading.value = false
  }
}
```

### 8.3 applyMarketData() 함수 — API 응답 → 화면 데이터 변환

```javascript
const applyMarketData = (apiData) => {
  const ps = apiData.perSource || {}

  // ── 소스별 집계 ─────────────────────────────────────────────
  const getSales = (key) => toNumber(ps[key]?.salesAmount)
  const getCount = (key) => toNumber(ps[key]?.contractCount)

  const goodsAmt  = getSales('procurement')
  const mallAmt   = getSales('shopping_mall')
  const svcAmt    = getSales('service')
  const consAmt   = getSales('construction')
  const goodsCnt  = getCount('procurement')
  const mallCnt   = getCount('shopping_mall')
  const svcCnt    = getCount('service')
  const consCnt   = getCount('construction')

  // ── 요약 카드 ───────────────────────────────────────────────
  const totalAmt  = goodsAmt + mallAmt + svcAmt + consAmt
  const totalCnt  = goodsCnt + mallCnt + svcCnt + consCnt
  const avgAmt    = totalCnt > 0 ? Math.round(totalAmt / totalCnt) : 0

  const excelAmt  = toNumber(ps['procurement']?.excellentAmount)
                  + toNumber(ps['shopping_mall']?.excellentAmount)
  const goodsMallAmt = goodsAmt + mallAmt
  const excelRatio = goodsMallAmt > 0
    ? ((excelAmt / goodsMallAmt) * 100).toFixed(1) + '%'
    : '-'

  summaryStats.value = [
    { label: '전체 매출액',   value: formatKrwCompact(totalAmt), colorClass: 'blue' },
    { label: '전체 계약건수', value: `${totalCnt.toLocaleString()}건`, colorClass: 'green' },
    { label: '평균 계약금액', value: formatKrwCompact(avgAmt),   colorClass: 'orange' },
    { label: '우수제품 비율', value: excelRatio,                 colorClass: 'purple' },
  ]

  // ── 영역별 매출액/계약건수 바 차트 ──────────────────────────
  // 체크된 소스만 막대로 표시, 물품+3자단가는 합산
  const barEntries = []
  if (ps['procurement'] || ps['shopping_mall']) {
    barEntries.push({ label: '물품+3자단가', sales: goodsAmt + mallAmt, count: goodsCnt + mallCnt })
  }
  if (ps['service']) {
    barEntries.push({ label: '용역', sales: svcAmt, count: svcCnt })
  }
  if (ps['construction']) {
    barEntries.push({ label: '공사', sales: consAmt, count: consCnt })
  }

  const maxSales = Math.max(...barEntries.map(b => b.sales), 1)
  const maxCount = Math.max(...barEntries.map(b => b.count), 1)

  revenueBars.value = barEntries.map(b => ({
    label:  b.label,
    height: pct(b.sales, maxSales),
  }))
  countBars.value = barEntries.map(b => ({
    label:  b.label,
    height: pct(b.count, maxCount),
  }))

  // ── 우수제품 vs 일반제품 텍스트 ────────────────────────────
  const genAmt = toNumber(ps['procurement']?.generalAmount)
               + toNumber(ps['shopping_mall']?.generalAmount)
  // 도넛 카드 제목 아래의 두 텍스트 업데이트 (ref 추가 필요)
  excellentAmount.value = excelAmt
  generalAmount.value   = genAmt

  // ── 영역별 상세 현황 리스트 ─────────────────────────────────
  const details = []
  if (ps['procurement'] || ps['shopping_mall']) {
    details.push({
      label:  '물품+3자단가',
      count:  goodsCnt + mallCnt,
      amount: formatKrwCompact(goodsAmt + mallAmt),
      color:  '#3498db',
    })
  }
  if (ps['service']) {
    details.push({ label: '용역', count: svcCnt, amount: formatKrwCompact(svcAmt), color: '#2ecc71' })
  }
  if (ps['construction']) {
    details.push({ label: '공사', count: consCnt, amount: formatKrwCompact(consAmt), color: '#f39c12' })
  }
  detailItems.value = details
}
```

### 8.4 우수제품 도넛 카드 ref 추가

```javascript
const excellentAmount = ref(0)
const generalAmount   = ref(0)
```

### 8.5 템플릿 — 도넛 카드 텍스트 바인딩 수정

```html
<!-- 기존 하드코딩 제거, 동적으로 변경 -->
<div class="pie-label left">우수제품: {{ formatKrwCompact(excellentAmount) }}</div>
<div class="pie-label right">일반제품: {{ formatKrwCompact(generalAmount) }}</div>
```

### 8.6 watch 및 onMounted 수정

```javascript
// 기존 loadDashboardData() → loadMarketData()로 교체
const loadDashboardData = async () => {
  await loadMarketData()
}

// 체크박스 변경 시 재조회
watch(marketDataSources, () => {
  loadMarketData()
})

// 기간 필터 변경 시에도 시장현황이 현재 탭이면 재조회
watch([dashboardFilterMode, dashboardYear, dashboardFrom, dashboardTo], () => {
  agencyLoaded.value  = false
  regionLoaded.value  = false
  marketLoaded.value  = false
  if (activeTab.value === '시장현황') loadMarketData()
  if (activeTab.value === '수요기관별' && !agencyLoading.value) fetchDemandAgencyMarket()
  if (activeTab.value === '지역별'    && !regionLoading.value)  fetchRegionMarket()
})

// 탭 전환 시 시장현황도 lazy load 적용
watch(activeTab, (tab) => {
  if (tab === '시장현황'   && !marketLoaded.value && !marketLoading.value) loadMarketData()
  if (tab === '수요기관별' && !agencyLoaded.value  && !agencyLoading.value) fetchDemandAgencyMarket()
  if (tab === '지역별'     && !regionLoaded.value   && !regionLoading.value)  fetchRegionMarket()
})
```

### 8.7 시장현황 섹션에 로딩/에러 배너 추가

```html
<section v-if="activeTab === '시장현황'" class="section">
  <h2 class="section-title">전체 조달시장 현황</h2>

  <!-- 로딩 -->
  <div v-if="marketLoading" class="loading-banner loading-banner-prominent">
    <div class="loading-spinner loading-spinner-large"></div>
    <p class="loading-text">로딩 중</p>
    <p class="loading-sub">시장현황 데이터를 불러오고 있습니다.</p>
  </div>

  <!-- 에러 -->
  <div v-else-if="marketError" class="info-banner">
    <div class="banner-left">
      <div class="info-icon">!</div>
      <div class="banner-text">
        <strong>데이터 조회 실패</strong>
        <p>{{ marketError }}</p>
      </div>
    </div>
  </div>

  <!-- 정상 데이터 -->
  <template v-else>
    <!-- 기존 summaryCards, chart-grid 등 그대로 유지 -->
    ...
  </template>
</section>
```

---

## 9. DB 인덱스 최적화

아래 SQL을 MySQL에서 실행한다.

### 9.1 procurement_contract_summary (기간 필터용)

```sql
-- 시장현황 집계: final_contract_date 단일 인덱스 (이미 있을 수 있으니 IF NOT EXISTS 활용)
ALTER TABLE procurement_contract_summary
    ADD INDEX IF NOT EXISTS idx_pcs_market (final_contract_date);
```

### 9.2 procurement_contract_flat (우수제품 집계용)

```sql
-- 우수제품 집계: is_active + contract_date + is_excellent_product 복합 인덱스
ALTER TABLE procurement_contract_flat
    ADD INDEX IF NOT EXISTS idx_pcf_market
        (is_active, contract_date, is_excellent_product, contract_amount);
```

### 9.3 shopping_mall_summary (3자단가 기간 필터)

```sql
ALTER TABLE shopping_mall_summary
    ADD INDEX IF NOT EXISTS idx_sms_market
        (final_ref_date, is_excellent_product);
```

### 9.4 service_contract_grouped (용역 기간 필터)

```sql
ALTER TABLE service_contract_grouped
    ADD INDEX IF NOT EXISTS idx_scg_market
        (is_active, final_contract_date);
```

### 9.5 construction_contract_grouped (공사 기간 필터)

```sql
ALTER TABLE construction_contract_grouped
    ADD INDEX IF NOT EXISTS idx_ccg_market
        (is_active, final_contract_date);
```

---

## 10. 날짜 기준 컬럼 요약

| 테이블 | 기간 필터 컬럼 | 금액 컬럼 |
|---|---|---|
| `procurement_contract_summary` | `final_contract_date` | `final_contract_amount` |
| `procurement_contract_flat` | `contract_date` | `contract_amount` |
| `shopping_mall_summary` | `final_ref_date` | `total_supply_amount` |
| `service_contract_grouped` | `final_contract_date` | `final_contract_amount_sum` |
| `construction_contract_grouped` | `final_contract_date` | `final_contract_amount_sum` |

---

## 11. 구현 체크리스트

### 백엔드
- [ ] `ProcurementContractSummaryMapper.xml` — 섹션 4의 4개 쿼리 + 우수제품 쿼리 추가
- [ ] `ProcurementContractSummaryMapper.java` — 5개 메서드 선언 추가
- [ ] `ReportDataService.java` — `getMarketOverview(from, to, sources)` 구현
- [ ] `ReportDataController.java` — `/api/report/market` 파라미터(from, to, sources) 추가

### DB 인덱스
- [ ] 섹션 9의 인덱스 5개 실행 (이미 존재하는 인덱스는 자동 스킵)

### 프론트엔드
- [ ] `marketLoading`, `marketError`, `marketLoaded`, `excellentAmount`, `generalAmount` ref 추가
- [ ] `loadMarketData()` 함수 구현
- [ ] `applyMarketData()` 함수 구현
- [ ] `excellentAmount` / `generalAmount` 도넛 카드 텍스트 바인딩
- [ ] `watch(marketDataSources, ...)` 연동
- [ ] `watch([dashboardFilterMode, ...], ...)` 시장현황 재조회 추가
- [ ] `watch(activeTab, ...)` 시장현황 lazy load 추가
- [ ] 시장현황 섹션 로딩/에러 배너 템플릿 추가

---

## 12. 참고 — 기존 유틸 함수 (Vue 파일 내 이미 구현됨)

- `formatKrwCompact(amount)` — 원 단위 숫자 → "X.X억 / XX만 / XX원" 텍스트 변환
- `pct(value, max)` — 비율 퍼센트 문자열 반환 (예: "75%")
- `toNumber(v)` — 숫자 변환 헬퍼

이 함수들은 수정 없이 재사용한다.
