-- procurement_raw 기준
-- 1) contract_type = '제3자단가계약' 제외
-- 2) is_final_contract = 'Y' 인 데이터만 대상
-- 3) 입찰공고번호(bid_notice_no) + 업체사업자등록번호(vendor_biz_reg_no) 단위로 집계 (같은 공고에 업체 여러 건 가능)
--    공고번호가 NULL/빈 값인 최종계약: (업체, 계약번호) 단위로 집계해 서로 다른 계약이 한 행으로 뭉치지 않음
--    - 장기계약(is_long_term_continuous = 'Y'): 최초/최종계약일자·금액·계약차수 집계, 장기계약여부 'Y'
--    - 비장기계약: 동일 컬럼 집계, 장기계약여부 'N'
-- 계약차수 = 같은 (입찰공고번호, 업체) 내 계약번호(contract_no) 개수
--
-- 성능: 실행 전 create_index_long_term.sql 로 인덱스 생성 필수

USE g2b;

SELECT
  MAX(vendor_name)                    AS 업체명,
  vendor_biz_reg_no                   AS 업체사업자등록번호,
  MAX(contract_title)                 AS 계약명,
  MAX(demand_agency_name)             AS 수요기관명,
  MAX(demand_agency_region)           AS 수요기관지,
  MAX(detail_item_name)               AS 품명내용,
  MAX(contract_method)                AS 입찰계약방법,
  base.bid_notice_no_norm             AS 입찰공고번호,
  COALESCE(MAX(CASE WHEN base.bid_notice_no_norm = '' THEN base.contract_no END), '') AS 계약번호_공고없음시구분,
  DATE_FORMAT(STR_TO_DATE(CAST(MIN(reference_date) AS CHAR), '%Y%m%d'), '%Y-%m-%d') AS 최초계약일자,
  SUM(CASE WHEN reference_date = first_contract_date THEN IFNULL(contract_amount, 0) ELSE 0 END) AS 최초계약금액,
  DATE_FORMAT(STR_TO_DATE(CAST(MAX(reference_date) AS CHAR), '%Y%m%d'), '%Y-%m-%d') AS 최종계약일자,
  SUM(IFNULL(contract_amount, 0))     AS 최종계약금액,
  COUNT(DISTINCT contract_no)          AS 계약차수,
  IF(MAX(CASE WHEN is_long_term_continuous = 'Y' THEN 'Y' END) = 'Y', 'Y', 'N') AS 장기계약여부
FROM (
  SELECT
    bid_notice_no,
    COALESCE(NULLIF(TRIM(bid_notice_no), ''), '') AS bid_notice_no_norm,
    vendor_biz_reg_no,
    contract_no,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    detail_item_name,
    contract_method,
    reference_date,
    contract_amount,
    is_long_term_continuous,
    MIN(reference_date) OVER (
      PARTITION BY
        COALESCE(NULLIF(TRIM(bid_notice_no), ''), ''),
        vendor_biz_reg_no,
        CASE WHEN COALESCE(NULLIF(TRIM(bid_notice_no), ''), '') = '' THEN contract_no END
    ) AS first_contract_date
  FROM procurement_raw USE INDEX (idx_contract_type_bid_ref)
  WHERE (contract_type IS NULL OR contract_type <> '제3자단가계약')
    AND is_final_contract = 'Y'
) base
GROUP BY
  base.bid_notice_no_norm,
  base.vendor_biz_reg_no,
  CASE WHEN base.bid_notice_no_norm = '' THEN base.contract_no END
ORDER BY base.bid_notice_no_norm, base.vendor_biz_reg_no, CASE WHEN base.bid_notice_no_norm = '' THEN base.contract_no END;
