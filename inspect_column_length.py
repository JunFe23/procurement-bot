# -*- coding: utf-8 -*-
import argparse
import os
from typing import Dict, Iterable, List, Optional, Tuple

import pandas as pd
from sqlalchemy import create_engine, text

from manual_upload import (
    DB_CONNECTION_STR,
    ENCODING,
    KOR_TO_ENG,
    SEPARATOR,
    SKIP_ROWS,
    TABLE_NAME,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inspect CSV values that exceed DB column length"
    )
    parser.add_argument(
        "--file",
        required=True,
        help="CSV file path (absolute or relative)",
    )
    parser.add_argument(
        "--column",
        default="unit",
        help="Target column (default: unit)",
    )
    parser.add_argument(
        "--max-len",
        type=int,
        help="Max length override (skip DB lookup)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Max rows to print (default: 20)",
    )
    parser.add_argument(
        "--show-columns",
        default="contract_no,contract_change_seq,item_seq,unit",
        help="Comma-separated columns to show in output",
    )
    parser.add_argument(
        "--use-db",
        action="store_true",
        help="Fetch column length from DB",
    )
    return parser.parse_args()


def iter_csv_chunks(file_path: str) -> Iterable[pd.DataFrame]:
    return pd.read_csv(
        file_path,
        encoding=ENCODING,
        sep=SEPARATOR,
        skiprows=SKIP_ROWS,
        low_memory=False,
        thousands=",",
        chunksize=10000,
    )


def normalize_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    df.columns = [str(c).strip() for c in df.columns]
    return df.rename(columns=KOR_TO_ENG)


def fetch_column_length(column_name: str) -> Optional[int]:
    query = text(
        """
        SELECT character_maximum_length
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = :table_name
          AND column_name = :column_name
        """
    )
    engine = create_engine(DB_CONNECTION_STR)
    with engine.connect() as conn:
        row = conn.execute(
            query, {"table_name": TABLE_NAME, "column_name": column_name}
        ).first()
    if not row or row[0] is None:
        return None
    return int(row[0])


def inspect_column(
    file_path: str,
    column_name: str,
    max_len: Optional[int],
    limit: int,
    show_columns: List[str],
) -> Tuple[int, int, List[pd.DataFrame]]:
    total_rows = 0
    over_rows = 0
    samples: List[pd.DataFrame] = []

    for chunk in iter_csv_chunks(file_path):
        if chunk.empty:
            continue
        df = normalize_dataframe(chunk)
        total_rows += len(df)
        if column_name not in df.columns:
            raise ValueError(f"Column not found after rename: {column_name}")

        series = df[column_name].fillna("").astype(str)
        lengths = series.str.len()
        if max_len is None:
            current_max = int(lengths.max()) if not lengths.empty else 0
            max_len = current_max

        mask = lengths > max_len
        if mask.any():
            over_rows += int(mask.sum())
            if len(samples) < limit:
                subset_cols = [c for c in show_columns if c in df.columns]
                samples.append(df.loc[mask, subset_cols].copy())

    return total_rows, over_rows, samples


def main() -> None:
    args = parse_args()
    file_path = os.path.expanduser(args.file)
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    max_len = args.max_len
    if args.use_db and max_len is None:
        max_len = fetch_column_length(args.column)

    show_columns = [c.strip() for c in args.show_columns.split(",") if c.strip()]
    total_rows, over_rows, samples = inspect_column(
        file_path=file_path,
        column_name=args.column,
        max_len=max_len,
        limit=args.limit,
        show_columns=show_columns,
    )

    print(f"파일: {os.path.basename(file_path)}")
    print(f"대상 컬럼: {args.column}")
    if max_len is not None:
        print(f"최대 길이 기준: {max_len}")
    print(f"총 행 수: {total_rows}")
    print(f"초과 행 수: {over_rows}")

    if samples:
        print("\n---- 초과 행 샘플 ----")
        print(pd.concat(samples, ignore_index=True).head(args.limit))
        print("---------------------")


if __name__ == "__main__":
    main()
