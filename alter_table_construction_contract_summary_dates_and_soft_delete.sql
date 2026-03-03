-- summary 테이블: 날짜 컬럼 DATE 변경 + soft delete·갱신 추적 컬럼 추가
-- TRUNCATE 금지 대비: is_active, last_seen_date, updated_at/created_at
-- 기존 VARCHAR가 YYYYMMDD 또는 YYYY-MM-DD 형식이면 아래 변환 후 MODIFY 권장

USE g2b;

-- 0) (선택) 기존 VARCHAR 날짜가 있으면 정규화. 이미 DATE면 생략.
-- UPDATE construction_contract_summary SET first_contract_date = DATE_FORMAT(STR_TO_DATE(TRIM(first_contract_date), '%Y%m%d'), '%Y-%m-%d') WHERE first_contract_date REGEXP '^[0-9]{8}$';
-- UPDATE construction_contract_summary SET contract_date       = DATE_FORMAT(STR_TO_DATE(TRIM(contract_date), '%Y%m%d'), '%Y-%m-%d') WHERE contract_date REGEXP '^[0-9]{8}$';

-- 1) 날짜 컬럼을 DATE로 변경 (VARCHAR → DATE 시 MySQL이 YYYY-MM-DD/YYYYMMDD 해석 시도)
ALTER TABLE construction_contract_summary
  MODIFY COLUMN first_contract_date DATE DEFAULT NULL COMMENT '최초계약일자',
  MODIFY COLUMN contract_date       DATE DEFAULT NULL COMMENT '최종계약일자';

-- 2) soft delete 및 갱신 추적 컬럼 추가
ALTER TABLE construction_contract_summary
  ADD COLUMN is_active     CHAR(1)   NOT NULL DEFAULT 'Y' COMMENT '활성 여부(N=raw에 없음)' AFTER saved,
  ADD COLUMN last_seen_date DATE     DEFAULT NULL COMMENT 'raw에 마지막으로 본 날짜(갱신일)' AFTER is_active,
  ADD COLUMN created_at    DATETIME  DEFAULT CURRENT_TIMESTAMP COMMENT '최초 생성' AFTER last_seen_date,
  ADD COLUMN updated_at    DATETIME  DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP COMMENT '최종 수정' AFTER created_at;

-- 3) 인덱스 (선택: is_active 필터용)
-- CREATE INDEX idx_construction_summary_is_active ON construction_contract_summary (is_active);
-- 이미 idx_saved 등이 있으면 필요 시에만 추가
