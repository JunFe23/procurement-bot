-- 공사 계약 변경 이력: contract_no + change_seq 단위 (FK → summary.contract_no)
-- raw 원본 추적용 raw_pk 또는 식별자 포함

USE g2b;

CREATE TABLE IF NOT EXISTS construction_contract_change_history (
  id                          BIGINT        AUTO_INCREMENT PRIMARY KEY COMMENT '자동 PK',
  contract_no                  VARCHAR(100)  NOT NULL COMMENT '계약번호(FK)',
  change_seq                   BIGINT        NOT NULL COMMENT '계약변경차수',
  contract_date                DATE          DEFAULT NULL COMMENT '해당 차수 계약일자',
  contract_amount              BIGINT        DEFAULT NULL COMMENT '해당 차수 계약금액',
  contract_diff_amount         BIGINT        DEFAULT NULL COMMENT '계약증감금액',
  first_contract_amount        BIGINT        DEFAULT NULL COMMENT '최초계약금액',
  total_book_contract_amount   BIGINT        DEFAULT NULL COMMENT '총부기계약금액',
  estimated_price              BIGINT        DEFAULT NULL COMMENT '예정가격',
  estimated_amount             BIGINT        DEFAULT NULL COMMENT '추정금액',
  bid_amount                   BIGINT        DEFAULT NULL COMMENT '낙찰금액',
  is_first_contract            CHAR(1)       DEFAULT NULL COMMENT '최초계약여부 Y/N',
  is_final_contract            CHAR(1)       DEFAULT NULL COMMENT '최종계약여부 Y/N',
  is_first_long_term_contract  CHAR(1)       DEFAULT NULL COMMENT '최초장기계속계약여부 Y/N',
  raw_contract_no              VARCHAR(100)  DEFAULT NULL COMMENT '원본 raw contract_no(추적)',
  raw_change_seq               BIGINT        DEFAULT NULL COMMENT '원본 raw contract_change_seq(추적)',
  created_at                   DATETIME      DEFAULT CURRENT_TIMESTAMP,
  updated_at                   DATETIME      DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_contract_change (contract_no, change_seq),
  KEY fk_history_summary (contract_no),
  CONSTRAINT fk_construction_history_summary
    FOREIGN KEY (contract_no) REFERENCES construction_contract_summary (contract_no) ON DELETE RESTRICT ON UPDATE CASCADE,
  KEY idx_history_contract_date (contract_date),
  KEY idx_history_final (is_final_contract)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='공사 계약 변경 이력(contract_no+change_seq, FK→summary)';
