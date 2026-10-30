"""Reject unsafe process IDs; never fall back to a bundle-wide activation."""
import unittest
import foreground


class ForegroundTest(unittest.TestCase):
    def test_rejects_nonpositive_process_ids(self):
        for pid in (0, -1):
            with self.subTest(pid=pid), self.assertRaises(ValueError):
                foreground.activate_pid(pid)

    def test_absent_process_is_not_substituted_with_another_app(self):
        self.assertFalse(foreground.activate_pid(2147483647, timeout=0))


if __name__ == '__main__':
    unittest.main()
