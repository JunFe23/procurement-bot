# -*- coding: utf-8 -*-
"""
특정품목 조달 내역 CSV → MySQL 적재 스크립트.

Usage:
  python specific_item_upload.py --downloads-dir ./downloads_specific_item
"""

import argparse
import glob
import os
import time
import uuid
from typing import Dict, Iterable, List, Optional

import pandas as pd
from sqlalchemy import create_engine, text

DB_CONNECTION_STR = "mysql+pymysql://root:@localhost:3306/g2b"
TABLE_NAME = "procurement_specific_item_raw"
LOG_TABLE_NAME = "procurement_specific_item_ingestion_log"

ENCODING = "utf-16"
SEPARATOR = "\t"
CHUNK_SIZE = 10000
HEADER_MATCH = "조달방식구분"

# 리포트 헤더 기준 컬럼 매핑 (한글 → 영문)
KOR_TO_ENG = {
    "조달방식구분": "procurement_method_type",
    "계약유형": "contract_type",
    "계약납품구분": "delivery_contract_type",
    "기준일자": "reference_date",
    "계약납품통합번호": "delivery_contract_no",
    "계약납품통합변경차수": "delivery_contract_change_seq",
    "계약납품요구물품순번": "delivery_item_seq",
    "최종계약납품요구여부": "is_final_delivery_request",
    "수요기관번호": "demand_agency_no",
    "수요기관명": "demand_agency_name",
    "소관구분": "supervising_type",
    "수요기관지역": "demand_agency_region",
    "물품분류번호": "item_category_no",
    "물품분류명": "item_category_name",
    "세부품명번호": "detail_item_no",
    "세부품명": "detail_item_name",
    "물품식별번호": "item_identifier_no",
    "물품식별명": "item_identifier_name",
    "계약납품단위명": "delivery_unit_name",
    "업체": "vendor_name",
    "계약시점 기업형태구분": "company_type_at_contract",
    "계약명": "contract_title",
    "우수제품여부": "is_excellent_product",
    "직접구매대상여부": "is_direct_purchase_target",
    "MAS여부": "is_mas",
    "이단계경쟁제안서제출여부": "is_two_stage_proposal",
    "최초기준일자": "first_reference_date",
    "계약번호": "contract_no",
    "계약변경차수": "contract_change_seq",
    "계약방법": "contract_method",
    "납품장소명": "delivery_place_name",
    "납품기한일자": "delivery_deadline_date",
    "업체사업자등록번호": "vendor_biz_reg_no",
    "인도조건": "delivery_terms",
    "계약납품단가": "delivery_unit_price",
    "계약납품수량": "delivery_quantity",
    "공급금액": "supply_amount",
    "계약납품증감수량": "delivery_quantity_delta",
    "공급증감금액": "supply_amount_delta",
}

REQUIRED_COLUMNS = [
    "delivery_contract_no",
    "delivery_contract_change_seq",
    "delivery_item_seq",
]

CREATE_TABLE_SQL = f"""
CREATE TABLE IF NOT EXISTS {TABLE_NAME} (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  procurement_method_type VARCHAR(64),
  contract_type VARCHAR(64),
  delivery_contract_type VARCHAR(64),
  reference_date VARCHAR(16),
  delivery_contract_no VARCHAR(64) NOT NULL,
  delivery_contract_change_seq INT NOT NULL,
  delivery_item_seq INT NOT NULL,
  is_final_delivery_request VARCHAR(8),
  demand_agency_no VARCHAR(64),
  demand_agency_name VARCHAR(255),
  supervising_type VARCHAR(64),
  demand_agency_region VARCHAR(255),
  item_category_no VARCHAR(64),
  item_category_name VARCHAR(255),
  detail_item_no VARCHAR(64),
  detail_item_name VARCHAR(255),
  item_identifier_no VARCHAR(64),
  item_identifier_name VARCHAR(255),
  delivery_unit_name VARCHAR(255),
  vendor_name VARCHAR(255),
  company_type_at_contract VARCHAR(64),
  contract_title VARCHAR(500),
  is_excellent_product VARCHAR(8),
  is_direct_purchase_target VARCHAR(8),
  is_mas VARCHAR(8),
  is_two_stage_proposal VARCHAR(8),
  first_reference_date VARCHAR(16),
  contract_no VARCHAR(64),
  contract_change_seq INT,
  contract_method VARCHAR(128),
  delivery_place_name VARCHAR(500),
  delivery_deadline_date VARCHAR(16),
  vendor_biz_reg_no VARCHAR(32),
  delivery_terms VARCHAR(255),
  delivery_unit_price VARCHAR(64),
  delivery_quantity VARCHAR(64),
  supply_amount VARCHAR(64),
  delivery_quantity_delta VARCHAR(64),
  supply_amount_delta VARCHAR(64),
  UNIQUE KEY uk_delivery_contract_item (
    delivery_contract_no,
    delivery_contract_change_seq,
    delivery_item_seq
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Specific item report ingestion")
    parser.add_argument(
        "--downloads-dir",
        default="./downloads_specific_item",
        help="Source directory to scan (default: ./downloads_specific_item)",
    )
    parser.add_argument(
        "--completed-dir",
        default="./completed_specific_item",
        help="Archive directory for processed files (default: ./completed_specific_item)",
    )
    parser.add_argument(
        "--pattern",
        default="*특정품목조달내역*.csv",
        help="Filename pattern to match",
    )
    parser.add_argument("--file", help="Process a single file (override pattern)")
    parser.add_argument("--dry-run", action="store_true", help="Validate only")
    parser.add_argument(
        "--dedupe-in-file",
        action="store_true",
        help="Drop duplicate rows within each file",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--stop-on-fail",
        dest="stop_on_fail",
        action="store_true",
        help="Stop at first failure (default)",
    )
    group.add_argument(
        "--no-stop-on-fail",
        dest="stop_on_fail",
        action="store_false",
        help="Continue on failures",
    )
    parser.set_defaults(stop_on_fail=True)
    return parser.parse_args()


def ensure_table(engine) -> None:
    with engine.begin() as conn:
        conn.execute(text(CREATE_TABLE_SQL))


def ensure_log_table(engine) -> None:
    create_sql = f"""
        CREATE TABLE IF NOT EXISTS {LOG_TABLE_NAME} (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            file_path VARCHAR(512) NOT NULL UNIQUE,
            file_name VARCHAR(255) NOT NULL,
            file_mtime BIGINT NOT NULL,
            status VARCHAR(32) NOT NULL,
            rows_inserted BIGINT DEFAULT 0,
            started_at DATETIME NULL,
            finished_at DATETIME NULL,
            error_message TEXT NULL,
            run_id CHAR(36) NULL
        )
    """
    with engine.begin() as conn:
        conn.execute(text(create_sql))


def format_error_message(error: object, max_len: int = 2000) -> str:
    message = str(error)
    message = message.replace("\x00", "")
    if len(message) <= max_len:
        return message
    head = message[: max_len - 20]
    return f"{head} ... [truncated]"


def fetch_column_max_lengths(engine, table_name: str) -> Dict[str, int]:
    query = text(
        """
        SELECT column_name, character_maximum_length
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = :table_name
          AND character_maximum_length IS NOT NULL
        """
    )
    with engine.connect() as conn:
        rows = conn.execute(query, {"table_name": table_name}).fetchall()
    return {row[0]: int(row[1]) for row in rows}


def apply_column_length_limits(
    df: pd.DataFrame, max_lengths: Optional[Dict[str, int]]
) -> pd.DataFrame:
    if not max_lengths:
        return df
    for col, max_len in max_lengths.items():
        if col in df.columns:
            df[col] = df[col].astype("string").str.slice(0, max_len)
    return df


def detect_header_row(file_path: str, max_lines: int = 200) -> int:
    with open(file_path, "r", encoding=ENCODING, errors="ignore") as handle:
        for idx, line in enumerate(handle):
            if HEADER_MATCH in line:
                return idx
            if idx >= max_lines:
                break
    raise ValueError(f"Header row not found in {file_path}")


def iter_file_chunks(file_path: str) -> Iterable[pd.DataFrame]:
    header_row = detect_header_row(file_path)
    return pd.read_csv(
        file_path,
        encoding=ENCODING,
        sep=SEPARATOR,
        skiprows=header_row,
        low_memory=False,
        thousands=",",
        chunksize=CHUNK_SIZE,
    )


def normalize_dataframe(
    df: pd.DataFrame,
    dedupe_in_file: bool,
    max_lengths: Optional[Dict[str, int]] = None,
) -> pd.DataFrame:
    df.columns = [str(c).strip().strip('"') for c in df.columns]
    df = df.rename(columns=KOR_TO_ENG)

    missing = [col for col in REQUIRED_COLUMNS if col not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    df["delivery_contract_no"] = (
        df["delivery_contract_no"].fillna("").astype(str).str.strip()
    )
    if (df["delivery_contract_no"] == "").any():
        raise ValueError("delivery_contract_no contains empty values")

    for col in ["delivery_contract_change_seq", "delivery_item_seq"]:
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype("int64")

    if dedupe_in_file:
        df = df.drop_duplicates(subset=REQUIRED_COLUMNS, keep="last")

    target_columns = [col for col in KOR_TO_ENG.values() if col in df.columns]
    df = df[target_columns]
    return apply_column_length_limits(df, max_lengths)


def list_source_files(downloads_dir: str, pattern: str, file_arg: Optional[str]) -> List[str]:
    if file_arg:
        candidate = os.path.expanduser(file_arg)
        if os.path.exists(candidate):
            return [candidate]
        candidate = os.path.join(downloads_dir, file_arg)
        if os.path.exists(candidate):
            return [candidate]
        raise FileNotFoundError(f"File not found: {file_arg}")
    return sorted(glob.glob(os.path.join(downloads_dir, pattern)))


def fetch_log_record(engine, file_path: str) -> Optional[Dict]:
    query = text(
        f"""
        SELECT file_path, file_mtime, status, rows_inserted
        FROM {LOG_TABLE_NAME}
        WHERE file_path = :file_path
        """
    )
    with engine.connect() as conn:
        result = conn.execute(query, {"file_path": file_path}).mappings().first()
    return dict(result) if result else None


def upsert_log(
    engine,
    *,
    file_path: str,
    file_name: str,
    file_mtime: int,
    status: str,
    rows_inserted: int,
    run_id: str,
    error_message: Optional[object] = None,
    set_started: bool = False,
) -> None:
    if error_message:
        error_message = format_error_message(error_message)
    insert_sql = f"""
        INSERT INTO {LOG_TABLE_NAME} (
            file_path, file_name, file_mtime, status, rows_inserted,
            started_at, finished_at, error_message, run_id
        ) VALUES (
            :file_path, :file_name, :file_mtime, :status, :rows_inserted,
            CASE WHEN :set_started = 1 THEN NOW() ELSE NULL END,
            CASE WHEN :set_started = 1 THEN NULL ELSE NOW() END,
            :error_message, :run_id
        )
        ON DUPLICATE KEY UPDATE
            file_name = VALUES(file_name),
            file_mtime = VALUES(file_mtime),
            status = VALUES(status),
            rows_inserted = VALUES(rows_inserted),
            started_at = CASE WHEN :set_started = 1 THEN NOW() ELSE started_at END,
            finished_at = CASE WHEN :set_started = 1 THEN NULL ELSE NOW() END,
            error_message = VALUES(error_message),
            run_id = VALUES(run_id)
    """
    payload = {
        "file_path": file_path,
        "file_name": file_name,
        "file_mtime": file_mtime,
        "status": status,
        "rows_inserted": rows_inserted,
        "error_message": error_message,
        "run_id": run_id,
        "set_started": 1 if set_started else 0,
    }
    with engine.begin() as conn:
        conn.execute(text(insert_sql), payload)


def process_file(
    engine,
    file_path: str,
    *,
    dedupe_in_file: bool,
    dry_run: bool,
    file_name: str,
    max_lengths: Optional[Dict[str, int]],
) -> int:
    file_rows = 0
    if dry_run:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            normalized = normalize_dataframe(
                chunk, dedupe_in_file, max_lengths=max_lengths
            )
            file_rows += len(normalized)
            print(
                f"   ↳ [{file_name}] 청크 {idx}: {len(normalized)}건 검증 (누적 {file_rows}건)"
            )
        return file_rows

    with engine.begin() as conn:
        for idx, chunk in enumerate(iter_file_chunks(file_path), start=1):
            if chunk.empty:
                continue
            normalized = normalize_dataframe(
                chunk, dedupe_in_file, max_lengths=max_lengths
            )
            normalized.to_sql(
                name=TABLE_NAME,
                con=conn,
                if_exists="append",
                index=False,
                method="multi",
            )
            file_rows += len(normalized)
            print(
                f"   ↳ [{file_name}] 청크 {idx}: {len(normalized)}건 insert (누적 {file_rows}건)"
            )
    return file_rows


def main() -> None:
    args = parse_args()
    downloads_dir = os.path.expanduser(args.downloads_dir)
    completed_dir = os.path.expanduser(args.completed_dir)
    files = list_source_files(downloads_dir, args.pattern, args.file)

    if not files:
        print(f"📭 '{downloads_dir}' 폴더에 처리할 파일이 없습니다.")
        return

    engine = create_engine(DB_CONNECTION_STR)
    ensure_table(engine)
    ensure_log_table(engine)
    run_id = str(uuid.uuid4())
    try:
        column_max_lengths = fetch_column_max_lengths(engine, TABLE_NAME)
    except Exception as exc:
        column_max_lengths = {}
        print(f"⚠️ 컬럼 길이 조회 실패 (길이 제한 미적용): {exc}")

    success_count = 0
    failed_count = 0
    skipped_count = 0
    last_success_file = None
    failed_file = None

    print(f"🚀 총 {len(files)}개의 파일을 발견했습니다.")
    for idx, file_path in enumerate(files):
        file_name = os.path.basename(file_path)
        file_mtime = int(os.path.getmtime(file_path))
        print("\n==================================================")
        print(f"[{idx + 1}/{len(files)}] 처리 시작: {file_name}")
        print("==================================================")

        existing = fetch_log_record(engine, file_path)
        if (
            existing
            and existing.get("status") == "SUCCESS"
            and int(existing.get("file_mtime", 0)) == file_mtime
        ):
            skipped_count += 1
            upsert_log(
                engine,
                file_path=file_path,
                file_name=file_name,
                file_mtime=file_mtime,
                status="SKIPPED",
                rows_inserted=0,
                run_id=run_id,
                error_message=None,
                set_started=False,
            )
            print("⏭️  스킵: 이미 성공 처리된 파일")
            continue

        upsert_log(
            engine,
            file_path=file_path,
            file_name=file_name,
            file_mtime=file_mtime,
            status="RUNNING",
            rows_inserted=0,
            run_id=run_id,
            error_message=None,
            set_started=True,
        )

        start_time = time.time()
        try:
            rows = process_file(
                engine,
                file_path,
                dedupe_in_file=args.dedupe_in_file,
                dry_run=args.dry_run,
                file_name=file_name,
                max_lengths=column_max_lengths,
            )
            duration = time.time() - start_time
            if args.dry_run:
                skipped_count += 1
                upsert_log(
                    engine,
                    file_path=file_path,
                    file_name=file_name,
                    file_mtime=file_mtime,
                    status="SKIPPED",
                    rows_inserted=rows,
                    run_id=run_id,
                    error_message="dry-run",
                    set_started=False,
                )
                print(f"🧪 DRY RUN 완료 ({duration:.1f}초, {rows}건)")
            else:
                success_count += 1
                last_success_file = file_name
                upsert_log(
                    engine,
                    file_path=file_path,
                    file_name=file_name,
                    file_mtime=file_mtime,
                    status="SUCCESS",
                    rows_inserted=rows,
                    run_id=run_id,
                    error_message=None,
                    set_started=False,
                )
                print(f"✅ DB 적재 완료 ({duration:.1f}초, {rows}건)")
                if not os.path.exists(completed_dir):
                    os.makedirs(completed_dir)
                destination = os.path.join(completed_dir, file_name)
                if os.path.exists(destination):
                    os.remove(destination)
                os.replace(file_path, destination)
                print(f"📦 파일 이동 완료: {downloads_dir} -> {completed_dir}/{file_name}")
        except Exception as exc:
            failed_count += 1
            failed_file = file_name
            upsert_log(
                engine,
                file_path=file_path,
                file_name=file_name,
                file_mtime=file_mtime,
                status="FAILED",
                rows_inserted=0,
                run_id=run_id,
                error_message=exc,
                set_started=False,
            )
            print(f"❌ 처리 실패: {exc}")
            if args.stop_on_fail:
                break

    print("\n🎯 요약")
    print(f"   성공: {success_count}건 / 실패: {failed_count}건 / 스킵: {skipped_count}건")
    if last_success_file:
        print(f"   마지막 성공 파일: {last_success_file}")
    if failed_file:
        print(f"   실패 파일: {failed_file}")


if __name__ == "__main__":
    main()
