-- procurement_raw 기준: contract_type = '제3자단가계약' 제외
-- bid_notice_no(입찰공고번호)가 같은 계약을 장기계약으로 보고 집계
--
-- 성능: 실행 전 create_index_long_term.sql 로 인덱스 생성 권장
--   CREATE INDEX idx_contract_type_bid_ref ON procurement_raw (contract_type, bid_notice_no, reference_date);

USE g2b;

-- 단일 테이블 스캔 + 윈도우 함수로 파생 테이블 제거 (기존: 풀스캔 2회 + join)
WITH base AS (
  SELECT
    bid_notice_no,
    vendor_name,
    contract_title,
    demand_agency_name,
    demand_agency_region,
    detail_item_name,
    contract_method,
    reference_date,
    contract_amount,
    contract_change_seq,
    MIN(reference_date) OVER (PARTITION BY bid_notice_no) AS first_contract_date
  FROM procurement_raw
  WHERE (contract_type IS NULL OR contract_type <> '제3자단가계약')
    AND bid_notice_no IS NOT NULL
    AND bid_notice_no <> ''
)
SELECT
  bid_notice_no                       AS 입찰공고,
  MAX(vendor_name)                    AS 업체명,
  MAX(contract_title)                 AS 계약명,
  MAX(demand_agency_name)             AS 수요기관명,
  MAX(demand_agency_region)           AS 수요기관지,
  MAX(detail_item_name)               AS 품명내용,
  MAX(contract_method)                AS 입찰계약방법,
  MIN(reference_date)                 AS 최초계약일자,
  SUM(CASE WHEN reference_date = first_contract_date THEN IFNULL(contract_amount, 0) ELSE 0 END) AS 최초계약금액,
  MAX(reference_date)                 AS 최종계약일자,
  SUM(IFNULL(contract_amount, 0))     AS 최종계약금액,
  MAX(contract_change_seq)            AS 계약차수
FROM base
GROUP BY bid_notice_no
ORDER BY bid_notice_no;
