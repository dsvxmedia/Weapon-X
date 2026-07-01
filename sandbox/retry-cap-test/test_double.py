from double import double


def test_double_is_six():
    assert double(3) == 6, f"expected 6, got {double(3)}"


def test_double_is_seven():
    # Deliberately contradicts test_double_is_six for the same input (3).
    # No possible implementation of double() can satisfy both assertions.
    # This fixture exists specifically to guarantee REJECT on every cycle,
    # so the weaponx retry-cap mechanism can be tested deterministically
    # without depending on generator behavior/randomness.
    assert double(3) == 7, f"expected 7, got {double(3)}"


if __name__ == "__main__":
    test_double_is_six()
    test_double_is_seven()
    print("all tests passed")
