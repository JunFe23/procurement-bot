-- procurement_raw 기준: 업체사업자등록번호 + 입찰공고번호 단위 집계 (rn=1은 최초계약 행)
-- 날짜/금액 포맷팅 포함

WITH RankedProcurement AS (
  SELECT *,
         ROW_NUMBER() OVER (
             PARTITION BY vendor_biz_reg_no, bid_notice_no
             ORDER BY first_reference_date ASC, contract_change_seq ASC, item_seq ASC
         ) AS rn
  FROM procurement_raw
  WHERE bid_notice_no = '20240323555'
    AND vendor_biz_reg_no = '1188119624'
)
SELECT
  MAX(CASE WHEN rn = 1 THEN vendor_name END)       AS 업체명,
  MAX(CASE WHEN rn = 1 THEN contract_title END)   AS 계약명,
  MAX(CASE WHEN rn = 1 THEN demand_agency_name END)     AS 수요기관명,
  MAX(CASE WHEN rn = 1 THEN demand_agency_region END)   AS 수요기관지역명,
  MAX(CASE WHEN rn = 1 THEN detail_item_name END) AS 품명내용,
  MAX(CASE WHEN rn = 1 THEN contract_method END)  AS 입찰계약방법,
  bid_notice_no                                    AS 입찰공고,

  DATE_FORMAT(STR_TO_DATE(CAST(MAX(CASE WHEN rn = 1 THEN first_reference_date END) AS CHAR), '%Y%m%d'), '%Y-%m-%d') AS 최초계약일자,

  ROUND(MAX(CASE WHEN rn = 1 THEN contract_amount END), 0) AS 최초계약금액,
  DATE_FORMAT(STR_TO_DATE(CAST(MAX(reference_date) AS CHAR), '%Y%m%d'), '%Y-%m-%d') AS 최종계약일자,
  ROUND(SUM(contract_amount), 0) AS 최종계약금액,
  COUNT(DISTINCT contract_no) AS 계약차수
FROM RankedProcurement
GROUP BY vendor_biz_reg_no, bid_notice_no;
