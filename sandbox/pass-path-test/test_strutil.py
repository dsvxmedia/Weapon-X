from strutil import last_n_chars


def test_last_3_chars():
    assert last_n_chars("hello world", 3) == "rld", f"got {last_n_chars('hello world', 3)!r}"


def test_last_1_char():
    assert last_n_chars("abc", 1) == "c", f"got {last_n_chars('abc', 1)!r}"


def test_n_equals_length():
    assert last_n_chars("abc", 3) == "abc", f"got {last_n_chars('abc', 3)!r}"


if __name__ == "__main__":
    test_last_3_chars()
    test_last_1_char()
    test_n_equals_length()
    print("all tests passed")
