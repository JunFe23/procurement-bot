# -*- coding: utf-8 -*-
import unittest

import pandas as pd

from manual_upload import normalize_dataframe


class NormalizeDataFrameTests(unittest.TestCase):
    def test_normalize_and_cast_required_columns(self):
        df = pd.DataFrame(
            {
                " 계약번호 ": ["  A-1  "],
                "계약변경차수": [None],
                "물품순번": ["2"],
                "조달구분": ["물품"],
            }
        )
        normalized = normalize_dataframe(df, dedupe_in_file=False)
        self.assertEqual(normalized.loc[0, "contract_no"], "A-1")
        self.assertEqual(normalized.loc[0, "contract_change_seq"], 0)
        self.assertEqual(normalized.loc[0, "item_seq"], 2)
        self.assertIn("procurement_type", normalized.columns)

    def test_missing_required_columns_raises(self):
        df = pd.DataFrame({"계약번호": ["A-1"]})
        with self.assertRaises(ValueError):
            normalize_dataframe(df, dedupe_in_file=False)

    def test_empty_contract_no_raises(self):
        df = pd.DataFrame(
            {
                "계약번호": [None],
                "계약변경차수": [1],
                "물품순번": [1],
            }
        )
        with self.assertRaises(ValueError):
            normalize_dataframe(df, dedupe_in_file=False)

    def test_dedupe_in_file(self):
        df = pd.DataFrame(
            {
                "계약번호": ["A-1", "A-1"],
                "계약변경차수": [1, 1],
                "물품순번": [1, 1],
                "조달구분": ["A", "B"],
            }
        )
        normalized = normalize_dataframe(df, dedupe_in_file=True)
        self.assertEqual(len(normalized), 1)
        self.assertEqual(normalized.loc[normalized.index[0], "procurement_type"], "B")


if __name__ == "__main__":
    unittest.main()
