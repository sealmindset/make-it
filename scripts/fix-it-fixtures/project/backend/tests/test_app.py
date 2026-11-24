import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import add


def test_add():
    assert add(2, 3) == 5


def test_add_negative():
    assert add(-1, 1) == 0
