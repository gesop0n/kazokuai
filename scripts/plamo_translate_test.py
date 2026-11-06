import unittest

from plamo_translate import translate_markdown


def fake(text):
    return f"<{text}>"


class TranslateMarkdownTest(unittest.TestCase):
    def test_translates_each_paragraph(self):
        source = "First line.\nSecond line.\n\nNext paragraph.\n"
        self.assertEqual(translate_markdown(source, fake), "<First line.\nSecond line.>\n\n<Next paragraph.>\n")

    def test_keeps_code_blocks_with_blank_lines(self):
        source = "Intro.\n\n```text\nkazokuai/\n\n└── mise.toml\n```\n\nAfter.\n"
        self.assertEqual(
            translate_markdown(source, fake),
            "<Intro.>\n\n```text\nkazokuai/\n\n└── mise.toml\n```\n\n<After.>\n",
        )

    def test_keeps_template_headings_and_values(self):
        source = "# ADR 0005: Writing\n\n## Status\n\nAccepted\n\n### Loop\n"
        self.assertEqual(
            translate_markdown(source, fake),
            "# <ADR 0005: Writing>\n\n## Status\n\nAccepted\n\n### <Loop>\n",
        )

    def test_keeps_pr_template_labels(self):
        source = "- **Before:** No check.\n  **After:** It passes.\n\n**Door:** two-way\n"
        self.assertEqual(
            translate_markdown(source, fake),
            "- **Before:** <No check.>\n  **After:** <It passes.>\n\n**Door:** two-way\n",
        )

    def test_keeps_closing_keywords_and_html_tags(self):
        source = "Closes #12\nAdds the check.\n\n<details>\n"
        self.assertEqual(translate_markdown(source, fake), "Closes #12\n<Adds the check.>\n\n<details>\n")

    def test_translates_table_cells(self):
        source = "| Name | Use |\n|---|---|\n| `mise` | Runs tasks |\n"
        self.assertEqual(
            translate_markdown(source, fake),
            "| <Name> | <Use> |\n|---|---|\n| `mise` | <Runs tasks> |\n",
        )


if __name__ == "__main__":
    unittest.main()
