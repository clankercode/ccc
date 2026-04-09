import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tests.test_ccc_contract_impl import SingleImplCccContractTests
from tests.test_harness import _resolve_selected_languages


class CccContractTests(SingleImplCccContractTests):
    """Compatibility wrapper for the maintained cross-implementation contract suite."""

    selected_languages = _resolve_selected_languages("all")


if __name__ == "__main__":
    unittest.main(verbosity=2)
