-- 공사 계약 ETL: raw → flat UPSERT → flat → grouped UPSERT → flat/grouped is_active 정리
-- TRUNCATE 사용 안 함. 펼쳐서 보기=flat, 합쳐서 보기=construction_contract_grouped.
-- Step2는 raw가 아닌 flat(contract_no당 최종 1건)을 소스로 grouped 집계.
-- → is_final_contract 오류에 독립적이고, 날짜/금액 타입 변환 불필요, 대용량 raw 직접 집계 회피.
-- 시설공사 필터: public_procurement_category_major = '시설공사' AND mid IN (...) AND name IN (...)

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_etl_construction_contracts //

CREATE PROCEDURE sp_etl_construction_contracts()
BEGIN
  DECLARE v_run_date DATE DEFAULT CURDATE();

  -- ========== Step1: raw → flat UPSERT (시설공사, contract_no당 최종 1건)
  -- 최종행: is_final_contract='Y' 우선 → contract_change_seq DESC → contract_date DESC
  INSERT INTO construction_contract_flat (
    contract_no,
    vendor_biz_reg_no,
    domain_type,
    initial_year_contract_no,
    is_long_term_contract,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    public_procurement_category_name,
    bid_contract_method,
    bid_notice_no,
    first_contract_date,
    first_contract_amount,
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
    r.vendor_biz_reg_no,
    'CONST',
    r.initial_year_contract_no,
    CASE
      WHEN COALESCE(TRIM(r.long_term_continuation_seq), '') NOT IN ('', '0') OR r.is_initial_long_term_contract = 'Y' THEN 'Y'
      ELSE 'N'
    END,
    r.vendor_name,
    r.contract_title,
    r.demand_agency_name,
    r.demand_agency_region,
    r.public_procurement_category_name,
    r.bid_contract_method,
    r.bid_notice_no,
    r.first_contract_date_d,
    r.first_contract_amount,
    r.contract_date_d,
    r.contract_amount,
    r.contract_change_seq,
    COALESCE(f.saved, 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    SELECT
      contract_no,
      contract_change_seq,
      vendor_biz_reg_no,
      initial_year_contract_no,
      long_term_continuation_seq,
      is_initial_long_term_contract,
      vendor_name,
      contract_title,
      demand_agency_name,
      demand_agency_region,
      public_procurement_category_name,
      bid_contract_method,
      bid_notice_no,
      first_contract_amount,
      contract_amount,
      COALESCE(
        STR_TO_DATE(SUBSTRING_INDEX(TRIM(first_contract_date), '.', 1), '%Y%m%d'),
        STR_TO_DATE(SUBSTRING_INDEX(TRIM(first_contract_date), ' ', 1), '%Y-%m-%d')
      ) AS first_contract_date_d,
      COALESCE(
        STR_TO_DATE(SUBSTRING_INDEX(TRIM(contract_date), '.', 1), '%Y%m%d'),
        STR_TO_DATE(SUBSTRING_INDEX(TRIM(contract_date), ' ', 1), '%Y-%m-%d')
      ) AS contract_date_d,
      ROW_NUMBER() OVER (
        PARTITION BY contract_no
        ORDER BY
          (CASE WHEN TRIM(COALESCE(is_final_contract, '')) = 'Y' THEN 1 ELSE 0 END) DESC,
          contract_change_seq DESC,
          COALESCE(
            STR_TO_DATE(SUBSTRING_INDEX(TRIM(contract_date), '.', 1), '%Y%m%d'),
            STR_TO_DATE(SUBSTRING_INDEX(TRIM(contract_date), ' ', 1), '%Y-%m-%d'),
            DATE '1000-01-01'
          ) DESC
      ) AS rn
    FROM construction_contract_raw
    WHERE (public_procurement_category_major = '시설공사')
      AND (public_procurement_category_mid IN ('개별법령', '시설물유지관리공사'))
      AND (TRIM(COALESCE(public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사'))
  ) r
  LEFT JOIN construction_contract_flat f ON f.contract_no = r.contract_no
  WHERE r.rn = 1
  ON DUPLICATE KEY UPDATE
    vendor_biz_reg_no                  = VALUES(vendor_biz_reg_no),
    initial_year_contract_no           = VALUES(initial_year_contract_no),
    is_long_term_contract              = VALUES(is_long_term_contract),
    vendor_name                        = VALUES(vendor_name),
    contract_title                     = VALUES(contract_title),
    demand_agency_name                 = VALUES(demand_agency_name),
    demand_agency_region               = VALUES(demand_agency_region),
    public_procurement_category_name   = VALUES(public_procurement_category_name),
    bid_contract_method                = VALUES(bid_contract_method),
    bid_notice_no                      = VALUES(bid_notice_no),
    first_contract_date                = VALUES(first_contract_date),
    first_contract_amount              = VALUES(first_contract_amount),
    contract_date                      = VALUES(contract_date),
    contract_amount                    = VALUES(contract_amount),
    latest_change_seq                  = VALUES(latest_change_seq),
    is_active                          = 'Y',
    last_seen_date                     = v_run_date,
    etl_loaded_at                      = NOW();

  -- ========== Step2: flat → construction_contract_grouped UPSERT
  -- 소스: construction_contract_flat (contract_no당 최종 1건, is_active='Y')
  -- 장기: 같은 group_key를 가진 flat 행들을 집계해 1행으로. 비장기: 단건 1행 그대로.
  -- initial 기준 행: group_key 내에서 first_contract_date ASC, contract_date ASC 순 첫 번째 행.
  -- DATE/BIGINT 변환 불필요(flat이 이미 변환 완료).
  INSERT INTO construction_contract_grouped (
    group_key,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    public_procurement_category_name,
    bid_contract_method,
    bid_notice_no,
    initial_contract_date,
    initial_contract_amount,
    final_contract_date,
    final_contract_amount_sum,
    final_change_seq,
    contract_count,
    is_long_term_contract,
    saved,
    is_active,
    last_seen_date,
    etl_loaded_at
  )
  SELECT
    g.group_key,
    g.vendor_name,
    g.contract_title,
    g.demand_agency_name,
    g.demand_agency_region,
    g.public_procurement_category_name,
    g.bid_contract_method,
    g.bid_notice_no,
    g.initial_contract_date,
    g.initial_contract_amount,
    g.final_contract_date,
    g.final_contract_amount_sum,
    g.final_change_seq,
    g.contract_count,
    g.is_long_term_contract,
    COALESCE(lg.saved, 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    SELECT
      base.group_key,
      MAX(CASE WHEN base.rn = 1 THEN base.vendor_name END)                       AS vendor_name,
      MAX(CASE WHEN base.rn = 1 THEN base.contract_title END)                    AS contract_title,
      MAX(CASE WHEN base.rn = 1 THEN base.demand_agency_name END)                AS demand_agency_name,
      MAX(CASE WHEN base.rn = 1 THEN base.demand_agency_region END)              AS demand_agency_region,
      MAX(CASE WHEN base.rn = 1 THEN base.public_procurement_category_name END)  AS public_procurement_category_name,
      MAX(CASE WHEN base.rn = 1 THEN base.bid_contract_method END)               AS bid_contract_method,
      MAX(CASE WHEN base.rn = 1 THEN base.bid_notice_no END)                     AS bid_notice_no,
      MAX(CASE WHEN base.rn = 1 THEN base.first_contract_date END)               AS initial_contract_date,
      MAX(CASE WHEN base.rn = 1 THEN base.first_contract_amount END)             AS initial_contract_amount,
      MAX(base.contract_date)                                                     AS final_contract_date,
      SUM(base.contract_amount)                                                   AS final_contract_amount_sum,
      MAX(base.latest_change_seq)                                                 AS final_change_seq,
      COUNT(*)                                                                    AS contract_count,
      CASE WHEN COUNT(*) > 1 THEN 'Y' ELSE 'N' END                               AS is_long_term_contract
    FROM (
      SELECT
        COALESCE(f.initial_year_contract_no, f.contract_no) AS group_key,
        f.vendor_name,
        f.contract_title,
        f.demand_agency_name,
        f.demand_agency_region,
        f.public_procurement_category_name,
        f.bid_contract_method,
        f.bid_notice_no,
        f.first_contract_date,
        f.first_contract_amount,
        f.contract_date,
        f.contract_amount,
        f.latest_change_seq,
        ROW_NUMBER() OVER (
          PARTITION BY COALESCE(f.initial_year_contract_no, f.contract_no)
          ORDER BY f.first_contract_date ASC, f.contract_date ASC
        ) AS rn
      FROM construction_contract_flat f
      WHERE f.is_active = 'Y'
    ) base
    GROUP BY base.group_key
  ) g
  LEFT JOIN construction_contract_grouped lg ON lg.group_key = g.group_key
  ON DUPLICATE KEY UPDATE
    vendor_name                        = VALUES(vendor_name),
    contract_title                     = VALUES(contract_title),
    demand_agency_name                 = VALUES(demand_agency_name),
    demand_agency_region               = VALUES(demand_agency_region),
    public_procurement_category_name   = VALUES(public_procurement_category_name),
    bid_contract_method                = VALUES(bid_contract_method),
    bid_notice_no                      = VALUES(bid_notice_no),
    initial_contract_date              = VALUES(initial_contract_date),
    initial_contract_amount            = VALUES(initial_contract_amount),
    final_contract_date                = VALUES(final_contract_date),
    final_contract_amount_sum          = VALUES(final_contract_amount_sum),
    final_change_seq                   = VALUES(final_change_seq),
    contract_count                     = VALUES(contract_count),
    is_long_term_contract              = VALUES(is_long_term_contract),
    is_active                          = 'Y',
    last_seen_date                     = v_run_date,
    etl_loaded_at                      = NOW();

  -- ========== Step3: raw(시설공사)에 더 이상 없는 contract_no → flat is_active='N'
  UPDATE construction_contract_flat f
  SET f.is_active = 'N', f.etl_loaded_at = NOW()
  WHERE f.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM construction_contract_raw r
      WHERE r.contract_no = f.contract_no
        AND r.public_procurement_category_major = '시설공사'
        AND r.public_procurement_category_mid IN ('개별법령', '시설물유지관리공사')
        AND TRIM(COALESCE(r.public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사')
    );

  -- ========== Step4: flat(is_active='Y')에 더 이상 없는 group_key → grouped is_active='N'
  -- flat 기반이므로 raw 재스캔 불필요. Step3 이후에 실행되어야 flat의 is_active가 반영됨.
  UPDATE construction_contract_grouped lg
  SET lg.is_active = 'N', lg.etl_loaded_at = NOW()
  WHERE lg.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM construction_contract_flat f
      WHERE f.is_active = 'Y'
        AND COALESCE(f.initial_year_contract_no, f.contract_no) = lg.group_key
    );

END //

DELIMITER ;
