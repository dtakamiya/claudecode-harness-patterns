import unittest
from slug import slugify

class T(unittest.TestCase):
    def test_basic(self): self.assertEqual(slugify("Hello World"), "hello-world")
    def test_runs(self): self.assertEqual(slugify("a  --  b__c"), "a-b-c")
    def test_trim(self): self.assertEqual(slugify("  --Hi!--  "), "hi")
    def test_accents(self): self.assertEqual(slugify("Crème Brûlée"), "creme-brulee")
    def test_sharp_s(self): self.assertEqual(slugify("Straße"), "strasse")
    def test_ligature(self): self.assertEqual(slugify("Æon"), "aeon")
    def test_nonlatin_is_separator(self): self.assertEqual(slugify("a日本b"), "a-b")
    def test_digits(self): self.assertEqual(slugify("Top 10 Tips"), "top-10-tips")
    def test_empty(self): self.assertEqual(slugify(""), "")
    def test_all_sep(self): self.assertEqual(slugify("!!! ---"), "")
    def test_max_len_cut(self): self.assertEqual(slugify("hello world", 8), "hello-wo")
    def test_max_len_strip_trailing(self): self.assertEqual(slugify("hello world", 6), "hello")
    def test_max_len_zero(self): self.assertEqual(slugify("abc", 0), "")
    def test_max_len_larger(self): self.assertEqual(slugify("abc", 99), "abc")
    def test_neg(self):
        with self.assertRaises(ValueError): slugify("a", -1)
    def test_type(self):
        with self.assertRaises(TypeError): slugify(123)

if __name__ == "__main__": unittest.main()
