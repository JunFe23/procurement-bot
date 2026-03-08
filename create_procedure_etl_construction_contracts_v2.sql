-- 공사 계약 ETL v2: raw → flat UPSERT → longterm_group UPSERT → flat is_active 정리
-- TRUNCATE 사용 안 함. 펼쳐서 보기=flat, 합쳐서 보기=longterm_group.
-- (선택) 추후 batch_id/ingested_at 기반 증분 갱신 시 이 프로시저 내에서 배치 단위 제한 가능.

USE g2b;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_etl_construction_contracts_v2 //

CREATE PROCEDURE sp_etl_construction_contracts_v2()
BEGIN
  DECLARE v_run_date DATE DEFAULT CURDATE();

  -- ========== Step1: raw → flat UPSERT (시설공사, contract_no당 최종 1건)
  -- 최종행: is_final_contract='Y' 우선 → contract_change_seq DESC → contract_date DESC
  -- 날짜: raw 문자열 → STR_TO_DATE(SUBSTRING_INDEX(TRIM(.), '.', 1), '%Y%m%d') 등으로 DATE
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
    initial_year_contract_no            = VALUES(initial_year_contract_no),
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

  -- ========== Step2: raw(시설공사, 장기계약) → longterm_group UPSERT
  -- group_key = COALESCE(initial_year_contract_no, contract_no). 초기 계약 = 그룹 내 contract_change_seq 최소 행.
  -- initial_contract_date = 그룹 내 1차 계약의 contract_date. 문자열·initial_* = 초기 계약 기준. final_* = MAX(날짜/차수), SUM(금액), COUNT(*)
  INSERT INTO construction_contract_longterm_group (
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
    COALESCE(lg.saved, 'N'),
    'Y',
    v_run_date,
    NOW()
  FROM (
    SELECT
      base.group_key,
      MAX(CASE WHEN base.rn = 1 THEN base.vendor_name END)                  AS vendor_name,
      MAX(CASE WHEN base.rn = 1 THEN base.contract_title END)               AS contract_title,
      MAX(CASE WHEN base.rn = 1 THEN base.demand_agency_name END)           AS demand_agency_name,
      MAX(CASE WHEN base.rn = 1 THEN base.demand_agency_region END)        AS demand_agency_region,
      MAX(CASE WHEN base.rn = 1 THEN base.public_procurement_category_name END) AS public_procurement_category_name,
      MAX(CASE WHEN base.rn = 1 THEN base.bid_contract_method END)         AS bid_contract_method,
      MAX(CASE WHEN base.rn = 1 THEN base.bid_notice_no END)                AS bid_notice_no,
      MAX(CASE WHEN base.rn = 1 THEN base.contract_date_d END)             AS initial_contract_date,
      MAX(CASE WHEN base.rn = 1 THEN base.first_contract_amount END)        AS initial_contract_amount,
      MAX(base.contract_date_d)                                            AS final_contract_date,
      SUM(base.contract_amount)                                           AS final_contract_amount_sum,
      MAX(base.contract_change_seq)                                        AS final_change_seq,
      COUNT(*)                                                             AS contract_count
    FROM (
      SELECT
        COALESCE(r.initial_year_contract_no, r.contract_no) AS group_key,
        r.contract_change_seq,
        r.contract_date_d,
        r.first_contract_amount,
        r.contract_amount,
        r.vendor_name,
        r.contract_title,
        r.demand_agency_name,
        r.demand_agency_region,
        r.public_procurement_category_name,
        r.bid_contract_method,
        r.bid_notice_no,
        ROW_NUMBER() OVER (
          PARTITION BY COALESCE(r.initial_year_contract_no, r.contract_no)
          ORDER BY r.contract_change_seq ASC
        ) AS rn
      FROM (
        SELECT
          contract_no,
          contract_change_seq,
          initial_year_contract_no,
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
          ) AS contract_date_d
        FROM construction_contract_raw
        WHERE (public_procurement_category_major = '시설공사')
          AND (public_procurement_category_mid IN ('개별법령', '시설물유지관리공사'))
          AND (TRIM(COALESCE(public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사'))
          AND (
            COALESCE(TRIM(long_term_continuation_seq), '') NOT IN ('', '0')
            OR TRIM(COALESCE(is_initial_long_term_contract, '')) = 'Y'
          )
      ) r
    ) base
    GROUP BY base.group_key
  ) g
  LEFT JOIN construction_contract_longterm_group lg ON lg.group_key = g.group_key
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

  -- ========== Step4: raw(시설공사, 장기)에 더 이상 없는 group_key → longterm_group is_active='N'
  UPDATE construction_contract_longterm_group lg
  SET lg.is_active = 'N', lg.etl_loaded_at = NOW()
  WHERE lg.is_active = 'Y'
    AND NOT EXISTS (
      SELECT 1
      FROM (
        SELECT DISTINCT COALESCE(initial_year_contract_no, contract_no) AS gk
        FROM construction_contract_raw
        WHERE (public_procurement_category_major = '시설공사')
          AND (public_procurement_category_mid IN ('개별법령', '시설물유지관리공사'))
          AND (TRIM(COALESCE(public_procurement_category_name, '')) IN ('전기공사', '정보통신공사', '기계설비공사', '시설물유지관리공사', '상하수도설비공사', '기타시설공사'))
          AND (
            COALESCE(TRIM(long_term_continuation_seq), '') NOT IN ('', '0')
            OR TRIM(COALESCE(is_initial_long_term_contract, '')) = 'Y'
          )
      ) t
      WHERE t.gk = lg.group_key
    );

END //

DELIMITER ;
