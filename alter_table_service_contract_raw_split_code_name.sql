-- service_contract_raw: 코드/명칭 분리 ALTER
-- 변경 내용:
--   representative_item_category (코드) → representative_item_category_code
--   + ADD representative_item_category (명칭)
--   detail_item_name (코드) → detail_item_code
--   + ADD detail_item_name (명칭)
--   demand_agency (코드) → demand_agency_code
--   + ADD demand_agency (명칭)
-- 기존 데이터 보존: 코드값은 _code 컬럼으로 이동, 명칭 컬럼은 NULL (재업로드 후 채워짐)
USE g2b;

ALTER TABLE service_contract_raw
  -- 대표물품분류: 기존 컬럼(코드값 저장됨)을 _code로 이름 변경
  CHANGE COLUMN representative_item_category
    representative_item_category_code VARCHAR(50) DEFAULT NULL
    COMMENT '대표물품분류코드 (숫자코드, e.g. 76121598)',

  -- 세부품명: 기존 컬럼(코드값 저장됨)을 _code로 이름 변경
  CHANGE COLUMN detail_item_name
    detail_item_code VARCHAR(50) DEFAULT NULL
    COMMENT '세부품명코드 (숫자코드, e.g. 7612159801)',

  -- 수요기관: 기존 컬럼(코드값 저장됨)을 _code로 이름 변경
  CHANGE COLUMN demand_agency
    demand_agency_code VARCHAR(50) DEFAULT NULL
    COMMENT '수요기관코드 (숫자코드, e.g. 1613191)';

-- 명칭 컬럼 추가 (코드 컬럼 바로 뒤에 위치)
ALTER TABLE service_contract_raw
  ADD COLUMN representative_item_category VARCHAR(200) DEFAULT NULL
    COMMENT '대표물품분류명칭 (e.g. 건설폐기물처리서비스)'
    AFTER representative_item_category_code,

  ADD COLUMN detail_item_name VARCHAR(200) DEFAULT NULL
    COMMENT '세부품명명칭 (e.g. 건설폐기물처리서비스)'
    AFTER detail_item_code,

  ADD COLUMN demand_agency TEXT DEFAULT NULL
    COMMENT '수요기관명칭 (e.g. 국토교통부 원주지방국토관리청)'
    AFTER demand_agency_code;
