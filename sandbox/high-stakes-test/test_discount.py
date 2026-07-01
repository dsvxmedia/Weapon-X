from discount import apply_discount


def test_10_percent_off_100():
    assert apply_discount(100, 10) == 90, f"got {apply_discount(100, 10)}"


def test_25_percent_off_80():
    assert apply_discount(80, 25) == 60, f"got {apply_discount(80, 25)}"


def test_0_percent_off():
    assert apply_discount(50, 0) == 50, f"got {apply_discount(50, 0)}"


if __name__ == "__main__":
    test_10_percent_off_100()
    test_25_percent_off_80()
    test_0_percent_off()
    print("all tests passed")
