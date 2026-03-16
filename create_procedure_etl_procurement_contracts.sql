-- 물품 계약 ETL: raw → flat UPSERT → grouped UPSERT → flat/grouped is_active 정리
-- 대상: 탑인더스트리(1188117437), 탑정보통신(1188119624) 취급 (item_category_no, detail_item_no) 쌍에 해당하는 시장 전체 계약
-- 필터: is_final_contract='Y', contract_type <> '제3자단가계약'
-- TRUNCATE 사용 안 함. 펼쳐서 보기=flat, 합쳐서 보기=procurement_contract_grouped.
--
-- Step0: 탑인더스트리/탑정보통신의 (item_category_no, detail_item_no) 쌍을 임시 테이블에 저장 (EXISTS 대신 JOIN으로 성능 확보)
-- Step1: raw JOIN tmp_target_items → flat UPSERT  (contract_no, item_seq)당 최종 1건
-- Step2: flat(is_active='Y') → grouped UPSERT      (bid_notice_no, vendor)당 집계 1행
-- Step3: raw에 더 이상 없는 (contract_no, item_seq) → flat is_active='N'
-- Step4: flat(is_active='Y')에 더 이상 없는 그룹    → grouped is_active='N'
--
-- 권장 인덱스 (없으면 실행 전 생성):
--   CREATE INDEX idx_vendor_final ON procurement_raw (vendor_biz_reg_no, is_final_contract, item_category_no, detail_item_no);
--   CREATE INDEX idx_final_type_item ON procurement_raw (is_final_contract, contract_type, item_category_no, detail_item_no);

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_etl_procurement_contracts //

CREATE PROCEDURE sp_etl_procurement_contracts()
BEGIN
  DECLARE v_run_date DATE DEFAULT CURDATE();

  -- ========== Step0: 타깃 (item_category_no, detail_item_no) 쌍 임시 저장
  -- 탑인더스트리/탑정보통신이 is_final_contract='Y'로 체결한 품목 기준
  -- 임시 테이블 JOIN으로 Step1/Step3의 EXISTS 서브쿼리 반복 실행 방지
  DROP TEMPORARY TABLE IF EXISTS tmp_target_items;
  CREATE TEMPORARY TABLE tmp_target_items (
    item_category_no VARCHAR(20)  NOT NULL,
    detail_item_no   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (item_category_no, detail_item_no)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

  INSERT IGNORE INTO tmp_target_items (item_category_no, detail_item_no)
  SELECT DISTINCT
    item_category_no,
    detail_item_no
  FROM procurement_raw
  WHERE vendor_biz_reg_no IN ('1188117437', '1188119624')
    AND is_final_contract = 'Y'
    AND item_category_no IS NOT NULL
    AND detail_item_no   IS NOT NULL;

  -- ========== Step1: raw → flat UPSERT
  -- 소스: procurement_raw JOIN tmp_target_items, is_final_contract='Y', 제3자단가계약 제외
  -- (contract_no, item_seq)당 최종 1건: is_final_contract='Y' 중 contract_change_seq DESC
  -- LEFT JOIN flat → saved 값 보존 (신규는 'N', 기존은 유지)
  INSERT INTO procurement_contract_flat (
    contract_no,
    item_seq,
    vendor_biz_reg_no,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    contract_method,
    bid_notice_no,
    is_long_term,
    item_category_no,
    item_category_name,
    detail_item_no,
    detail_item_name,
    item_identifier_no,
    item_identifier_name,
    unit,
    unit_price,
    quantity,
    is_mas,
    is_excellent_product,
    is_sme_competitive,
    first_contract_date,
    contract_date,
    contract_amount,
    latest_change_seq,
    saved,
    is_active,
    last_seen_date,
    etl_loaded_at
  )
  SELECT
    r.contract_no,
    r.item_seq,
    r.vendor_biz_reg_no,
    r.vendor_name,
    r.contract_title,
    r.demand_agency_name,
    r.demand_agency_region,
    r.contract_method,
    r.bid_notice_no,
    COALESCE(NULLIF(TRIM(r.is_long_term_continuous), ''), 'N'),
    r.item_category_no,
    r.item_category_name,
    r.detail_item_no,
    r.detail_item_name,
    r.item_identifier_no,
    r.item_identifier_name,
    r.unit,
    r.unit_price,
    r.quantity,
    r.is_mas,
    r.is_excellent_product,
    r.is_sme_competitive_item,
    -- first_reference_date / reference_date: BIGINT YYYYMMDD → DATE
    STR_TO_DATE(CAST(r.first_reference_date AS CHAR), '%Y%m%d'),
    STR_TO_DATE(CAST(r.reference_date       AS CHAR), '%Y%m%d'),
    r.contract_amount,
    r.contract_change_seq,
    COALESCE(f.saved, 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    SELECT
      pr.contract_no,
      pr.item_seq,
      pr.contract_change_seq,
      pr.vendor_biz_reg_no,
      pr.vendor_name,
      pr.contract_title,
      pr.demand_agency_name,
      pr.demand_agency_region,
      pr.contract_method,
      pr.bid_notice_no,
      pr.is_long_term_continuous,
      pr.item_category_no,
      pr.item_category_name,
      pr.detail_item_no,
      pr.detail_item_name,
      pr.item_identifier_no,
      pr.item_identifier_name,
      pr.unit,
      pr.unit_price,
      pr.quantity,
      pr.is_mas,
      pr.is_excellent_product,
      pr.is_sme_competitive_item,
      pr.first_reference_date,
      pr.reference_date,
      pr.contract_amount,
      -- 동일 (contract_no, item_seq)에 is_final_contract='Y'가 복수인 엣지케이스 대비
      ROW_NUMBER() OVER (
        PARTITION BY pr.contract_no, pr.item_seq
        ORDER BY pr.contract_change_seq DESC
      ) AS rn
    FROM procurement_raw pr
    JOIN tmp_target_items ti
      ON ti.item_category_no = pr.item_category_no
     AND ti.detail_item_no   = pr.detail_item_no
    WHERE pr.is_final_contract = 'Y'
      AND (pr.contract_type IS NULL OR pr.contract_type <> '제3자단가계약')
  ) r
  LEFT JOIN procurement_contract_flat f
    ON f.contract_no = r.contract_no
   AND f.item_seq    = r.item_seq
  WHERE r.rn = 1
  ON DUPLICATE KEY UPDATE
    vendor_biz_reg_no    = VALUES(vendor_biz_reg_no),
    vendor_name          = VALUES(vendor_name),
    contract_title       = VALUES(contract_title),
    demand_agency_name   = VALUES(demand_agency_name),
    demand_agency_region = VALUES(demand_agency_region),
    contract_method      = VALUES(contract_method),
    bid_notice_no        = VALUES(bid_notice_no),
    is_long_term         = VALUES(is_long_term),
    item_category_no     = VALUES(item_category_no),
    item_category_name   = VALUES(item_category_name),
    detail_item_no       = VALUES(detail_item_no),
    detail_item_name     = VALUES(detail_item_name),
    item_identifier_no   = VALUES(item_identifier_no),
    item_identifier_name = VALUES(item_identifier_name),
    unit                 = VALUES(unit),
    unit_price           = VALUES(unit_price),
    quantity             = VALUES(quantity),
    is_mas               = VALUES(is_mas),
    is_excellent_product = VALUES(is_excellent_product),
    is_sme_competitive   = VALUES(is_sme_competitive),
    first_contract_date  = VALUES(first_contract_date),
    contract_date        = VALUES(contract_date),
    contract_amount      = VALUES(contract_amount),
    latest_change_seq    = VALUES(latest_change_seq),
    is_active            = 'Y',
    last_seen_date       = v_run_date,
    etl_loaded_at        = NOW();

  -- ========== Step2: flat → grouped UPSERT
  -- 소스: procurement_contract_flat (is_active='Y')
  -- 그룹 키:
  --   bid_notice_no      = COALESCE(NULLIF(TRIM(bid_notice_no),''), '')
  --   vendor_biz_reg_no  = 업체사업자등록번호
  --   contract_no (grouped PK) = 공고 있으면 '', 없으면 실제 계약번호 (개별 계약 분리)
  -- 문자열 컬럼: 그룹 내 최초 계약(contract_date ASC, contract_no ASC, item_seq ASC) 기준 1행
  -- initial_contract_amount: contract_date = 그룹 MIN(contract_date)인 행들의 금액 합계
  -- final_contract_amount_sum: 그룹 내 전체 contract_amount 합계
  -- is_long_term: contract_count > 1 OR 그룹 내 is_long_term='Y' 있으면 'Y'
  INSERT INTO procurement_contract_grouped (
    bid_notice_no,
    vendor_biz_reg_no,
    contract_no,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    contract_method,
    detail_item_name,
    initial_contract_date,
    initial_contract_amount,
    final_contract_date,
    final_contract_amount_sum,
    contract_count,
    is_long_term,
    saved,
    is_active,
    last_seen_date,
    etl_loaded_at
  )
  SELECT
    g.bid_notice_no_norm,
    g.vendor_biz_reg_no,
    g.contract_no_key,
    MAX(CASE WHEN g.rn = 1 THEN g.vendor_name          END),
    MAX(CASE WHEN g.rn = 1 THEN g.contract_title        END),
    MAX(CASE WHEN g.rn = 1 THEN g.demand_agency_name    END),
    MAX(CASE WHEN g.rn = 1 THEN g.demand_agency_region  END),
    MAX(CASE WHEN g.rn = 1 THEN g.contract_method       END),
    MAX(CASE WHEN g.rn = 1 THEN g.detail_item_name      END),
    MIN(g.contract_date),
    SUM(CASE WHEN g.contract_date = g.grp_min_date THEN IFNULL(g.contract_amount, 0) ELSE 0 END),
    MAX(g.contract_date),
    SUM(IFNULL(g.contract_amount, 0)),
    COUNT(DISTINCT g.contract_no),
    CASE WHEN COUNT(DISTINCT g.contract_no) > 1 OR MAX(g.is_long_term) = 'Y' THEN 'Y' ELSE 'N' END,
    COALESCE(MAX(lg.saved), 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    SELECT
      f.contract_no,
      f.item_seq,
      f.vendor_biz_reg_no,
      f.vendor_name,
      f.contract_title,
      f.demand_agency_name,
      f.demand_agency_region,
      f.contract_method,
      f.detail_item_name,
      f.contract_date,
      f.contract_amount,
      f.is_long_term,
      COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), '')                                            AS bid_notice_no_norm,
      CASE WHEN COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), '') = '' THEN f.contract_no ELSE '' END AS contract_no_key,
      -- 그룹 내 최솟값 날짜: initial_contract_amount 계산용
      MIN(f.contract_date) OVER (
        PARTITION BY
          COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), ''),
          f.vendor_biz_reg_no,
          CASE WHEN COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), '') = '' THEN f.contract_no ELSE '' END
      ) AS grp_min_date,
      -- rn=1: 그룹 내 최초 계약 행 (문자열 컬럼 대표값 추출용)
      ROW_NUMBER() OVER (
        PARTITION BY
          COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), ''),
          f.vendor_biz_reg_no,
          CASE WHEN COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), '') = '' THEN f.contract_no ELSE '' END
        ORDER BY f.contract_date ASC, f.contract_no ASC, f.item_seq ASC
      ) AS rn
    FROM procurement_contract_flat f
    WHERE f.is_active = 'Y'
  ) g
  LEFT JOIN procurement_contract_grouped lg
    ON lg.bid_notice_no     = g.bid_notice_no_norm
   AND lg.vendor_biz_reg_no = g.vendor_biz_reg_no
   AND lg.contract_no       = g.contract_no_key
  GROUP BY g.bid_notice_no_norm, g.vendor_biz_reg_no, g.contract_no_key
  ON DUPLICATE KEY UPDATE
    vendor_name               = VALUES(vendor_name),
    contract_title            = VALUES(contract_title),
    demand_agency_name        = VALUES(demand_agency_name),
    demand_agency_region      = VALUES(demand_agency_region),
    contract_method           = VALUES(contract_method),
    detail_item_name          = VALUES(detail_item_name),
    initial_contract_date     = VALUES(initial_contract_date),
    initial_contract_amount   = VALUES(initial_contract_amount),
    final_contract_date       = VALUES(final_contract_date),
    final_contract_amount_sum = VALUES(final_contract_amount_sum),
    contract_count            = VALUES(contract_count),
    is_long_term              = VALUES(is_long_term),
    is_active                 = 'Y',
    last_seen_date            = v_run_date,
    etl_loaded_at             = NOW();

  -- ========== Step3: raw(필터 조건)에 더 이상 없는 (contract_no, item_seq) → flat is_active='N'
  UPDATE procurement_contract_flat f
  SET f.is_active = 'N', f.etl_loaded_at = NOW()
  WHERE f.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM procurement_raw pr
      JOIN tmp_target_items ti
        ON ti.item_category_no = pr.item_category_no
       AND ti.detail_item_no   = pr.detail_item_no
      WHERE pr.contract_no      = f.contract_no
        AND pr.item_seq         = f.item_seq
        AND pr.is_final_contract = 'Y'
        AND (pr.contract_type IS NULL OR pr.contract_type <> '제3자단가계약')
    );

  -- ========== Step4: flat(is_active='Y')에 더 이상 없는 그룹 → grouped is_active='N'
  -- Step3 이후 실행해야 flat의 is_active 변경이 반영됨
  UPDATE procurement_contract_grouped lg
  SET lg.is_active = 'N', lg.etl_loaded_at = NOW()
  WHERE lg.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM procurement_contract_flat f
      WHERE f.is_active = 'Y'
        AND COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), '') = lg.bid_notice_no
        AND f.vendor_biz_reg_no = lg.vendor_biz_reg_no
        AND CASE WHEN COALESCE(NULLIF(TRIM(f.bid_notice_no), ''), '') = '' THEN f.contract_no ELSE '' END = lg.contract_no
    );

  -- Step0 임시 테이블 정리
  DROP TEMPORARY TABLE IF EXISTS tmp_target_items;

END //

DELIMITER ;
