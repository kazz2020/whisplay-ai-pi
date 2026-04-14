import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: markitdown_convert.py <file>", file=sys.stderr)
        return 1

    try:
        from markitdown import MarkItDown
    except ImportError:
        print(
            "MarkItDown is not installed. Install it with: pip install 'markitdown[pdf,docx,pptx,xlsx,xls]'",
            file=sys.stderr,
        )
        return 2

    source_path = sys.argv[1]
    converter = MarkItDown(enable_plugins=False)
    result = converter.convert(source_path)
    text_content = getattr(result, "text_content", "") or ""
    sys.stdout.write(text_content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())