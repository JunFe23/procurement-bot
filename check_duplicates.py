# -*- coding: utf-8 -*-
import argparse
import glob
import os
from typing import Dict, Iterable, List, Optional, Tuple

import pandas as pd

KOR_TO_ENG = {
    "조달구분": "procurement_type",
    "계약구분": "contract_type",
    "계약번호": "contract_no",
    "계약변경차수": "contract_change_seq",
    "물품순번": "item_seq",
    "최종계약여부": "is_final_contract",
    "수요기관명": "demand_agency_name",
    "수요기관코드": "demand_agency_code",
    "수요기관구분": "demand_agency_type",
    "수요기관지역명": "demand_agency_region",
    "계약명": "contract_title",
    "계약법유형": "contract_law_type",
    "조항호명": "article_clause_name",
    "계약방법명": "contract_method",
    "물품분류번호": "item_category_no",
    "물품분류명": "item_category_name",
    "세부품명번호": "detail_item_no",
    "세부품명": "detail_item_name",
    "물품식별번호": "item_identifier_no",
    "물품식별명": "item_identifier_name",
    "MAS여부": "is_mas",
    "우수제품여부": "is_excellent_product",
    "중기간경쟁물품여부": "is_sme_competitive_item",
    "최초기준일자": "first_reference_date",
    "기준일자": "reference_date",
    "납품기한": "delivery_deadline",
    "업체명": "vendor_name",
    "업체사업자등록번호": "vendor_biz_reg_no",
    "기업구분": "company_type",
    "낙찰결정방법": "award_method",
    "공공조달분류번호": "public_procurement_category_no",
    "입찰공고번호": "bid_notice_no",
    "입찰공고차수": "bid_notice_seq",
    "장기계약차수": "long_term_contract_seq",
    "장기계속여부": "is_long_term_continuous",
    "단위": "unit",
    "단가": "unit_price",
    "수량": "quantity",
    "증감수량": "quantity_delta",
    "계약금액": "contract_amount",
    "계약증감금액": "contract_amount_delta",
}

REQUIRED_COLUMNS = ["contract_no", "contract_change_seq", "item_seq"]

ENCODING = "utf-16"
SEPARATOR = "\t"
SKIP_ROWS = 28
CHUNK_SIZE = 10000


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check duplicate rows in CSV files")
    parser.add_argument(
        "--downloads-dir",
        default="./downloads",
        help="Directory containing CSV files (default: ./downloads)",
    )
    parser.add_argument(
        "--file",
        help="Specific CSV file to check (basename or full path)",
    )
    parser.add_argument("--contract-no", help="Target contract_no")
    parser.add_argument("--contract-change-seq", type=int, help="Target contract_change_seq")
    parser.add_argument("--item-seq", type=int, help="Target item_seq")
    parser.add_argument(
        "--show-rows",
        action="store_true",
        help="Print matching rows for the target key",
    )
    parser.add_argument(
        "--across-files",
        action="store_true",
        help="Check duplicate keys across multiple files",
    )
    parser.add_argument(
        "--max-keys",
        type=int,
        default=20,
        help="Max duplicate keys to display (default: 20)",
    )
    return parser.parse_args()


def list_csv_files(downloads_dir: str) -> List[str]:
    return sorted(glob.glob(os.path.join(downloads_dir, "*.csv")))


def normalize_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    df.columns = [str(c).strip() for c in df.columns]
    df = df.rename(columns=KOR_TO_ENG)
    missing = [col for col in REQUIRED_COLUMNS if col not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")
    df["contract_no"] = df["contract_no"].fillna("").astype(str).str.strip()
    df["contract_change_seq"] = (
        pd.to_numeric(df["contract_change_seq"], errors="coerce")
        .fillna(0)
        .astype("int64")
    )
    df["item_seq"] = (
        pd.to_numeric(df["item_seq"], errors="coerce").fillna(0).astype("int64")
    )
    return df


def iter_csv_chunks(file_path: str) -> Iterable[pd.DataFrame]:
    return pd.read_csv(
        file_path,
        encoding=ENCODING,
        sep=SEPARATOR,
        skiprows=SKIP_ROWS,
        low_memory=False,
        thousands=",",
        chunksize=CHUNK_SIZE,
    )


def count_duplicates(
    file_path: str,
    target_key: Optional[Tuple[str, int, int]],
    show_rows: bool,
) -> Dict[str, int]:
    total_rows = 0
    duplicate_rows = 0
    target_hits = 0
    target_rows: List[pd.DataFrame] = []
    seen_keys: set[Tuple[str, int, int]] = set()
    duplicate_keys: set[Tuple[str, int, int]] = set()

    for chunk in iter_csv_chunks(file_path):
        if chunk.empty:
            continue
        df = normalize_dataframe(chunk)
        total_rows += len(df)

        keys = list(zip(df["contract_no"], df["contract_change_seq"], df["item_seq"]))
        for key in keys:
            if key in seen_keys:
                duplicate_rows += 1
                duplicate_keys.add(key)
            else:
                seen_keys.add(key)

        if target_key:
            contract_no, contract_change_seq, item_seq = target_key
            hit_mask = (
                (df["contract_no"] == contract_no)
                & (df["contract_change_seq"] == contract_change_seq)
                & (df["item_seq"] == item_seq)
            )
            hits = df.loc[hit_mask, REQUIRED_COLUMNS]
            target_hits += len(hits)
            if show_rows and not hits.empty:
                target_rows.append(df.loc[hit_mask])

    if show_rows and target_rows:
        print("---- matching rows ----")
        print(pd.concat(target_rows, ignore_index=True))
        print("-----------------------")

    return {
        "total_rows": total_rows,
        "duplicate_rows": duplicate_rows,
        "duplicate_keys": len(duplicate_keys),
        "target_hits": target_hits,
    }


def resolve_file(downloads_dir: str, file_arg: Optional[str]) -> List[str]:
    if not file_arg:
        return list_csv_files(downloads_dir)
    if os.path.isabs(file_arg) and os.path.exists(file_arg):
        return [file_arg]
    candidate = os.path.join(downloads_dir, file_arg)
    if os.path.exists(candidate):
        return [candidate]
    raise FileNotFoundError(f"File not found: {file_arg}")


def count_duplicates_across_files(
    files: List[str],
    max_keys: int,
) -> Dict[str, object]:
    total_rows = 0
    duplicate_keys: set[Tuple[str, int, int]] = set()
    key_sources: Dict[Tuple[str, int, int], set[str]] = {}

    for file_path in files:
        file_name = os.path.basename(file_path)
        for chunk in iter_csv_chunks(file_path):
            if chunk.empty:
                continue
            df = normalize_dataframe(chunk)
            total_rows += len(df)
            keys = list(zip(df["contract_no"], df["contract_change_seq"], df["item_seq"]))
            for key in keys:
                sources = key_sources.setdefault(key, set())
                sources.add(file_name)
                if len(sources) > 1:
                    duplicate_keys.add(key)

    sample_keys = list(duplicate_keys)[: max_keys]
    sample_detail = [
        {
            "key": key,
            "files": sorted(key_sources.get(key, set())),
        }
        for key in sample_keys
    ]
    return {
        "total_rows": total_rows,
        "duplicate_key_count": len(duplicate_keys),
        "sample_detail": sample_detail,
    }


def main() -> None:
    args = parse_args()
    downloads_dir = os.path.expanduser(args.downloads_dir)
    files = resolve_file(downloads_dir, args.file)

    target_key = None
    if args.contract_no and args.contract_change_seq is not None and args.item_seq is not None:
        target_key = (args.contract_no, args.contract_change_seq, args.item_seq)

    if not files:
        print(f"No CSV files found in {downloads_dir}")
        return

    if args.across_files and len(files) > 1:
        print("== 파일 간 중복 키 검사 ==")
        stats = count_duplicates_across_files(files, args.max_keys)
        print(f"총 행 수: {stats['total_rows']}")
        print(f"파일 간 중복 키 수: {stats['duplicate_key_count']}")
        if stats["sample_detail"]:
            print("중복 키 샘플:")
            for entry in stats["sample_detail"]:
                key = entry["key"]
                files_list = ", ".join(entry["files"])
                print(f"  {key} -> {files_list}")
        return

    for file_path in files:
        file_name = os.path.basename(file_path)
        print(f"\n== {file_name} ==")
        stats = count_duplicates(file_path, target_key, args.show_rows)
        print(f"총 행 수: {stats['total_rows']}")
        print(f"파일 내 중복 행 수: {stats['duplicate_rows']}")
        print(f"중복 키 수: {stats['duplicate_keys']}")
        if target_key:
            print(f"지정 키 매칭 수: {stats['target_hits']}")


if __name__ == "__main__":
    main()
