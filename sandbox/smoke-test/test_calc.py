from calc import add


def test_add_positive():
    assert add(2, 3) == 5, f"expected 5, got {add(2, 3)}"


def test_add_negative():
    assert add(-1, -1) == -2, f"expected -2, got {add(-1, -1)}"


if __name__ == "__main__":
    test_add_positive()
    test_add_negative()
    print("all tests passed")
