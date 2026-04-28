from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable, List

from kws_training_project.tokenizer import encode_keyword_line, normalize_phrase, unique_keywords, write_tokens_file
from kws_training_project.utils import ensure_dir


def _read_lines(path: str | Path) -> List[str]:
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def convert_keywords(text_path: str | Path, tokens_path: str | Path, output_path: str | Path) -> List[str]:
    lines = _read_lines(text_path)
    phrases = []
    for line in lines:
        if line.startswith("#"):
            continue
        phrase = line
        if "@" in line:
            phrase = line.split("@", 1)[1].strip()
        phrase = phrase.split(":")[0].split("#")[0].strip()
        if phrase:
            phrases.append(phrase)
    tokens = write_tokens_file(tokens_path, phrases)
    ensure_dir(Path(output_path).parent)
    encoded: List[str] = []
    with open(output_path, "w", encoding="utf-8") as f:
        for line in lines:
            encoded_line = encode_keyword_line(line)
            if not encoded_line:
                continue
            encoded.append(encoded_line)
            f.write(encoded_line)
            f.write("\n")
    return encoded


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert keyword text into tokens.txt and encoded keyword lines.")
    parser.add_argument("text_arg", nargs="?", help="Input keyword text file")
    parser.add_argument("tokens_arg", nargs="?", help="Output tokens.txt")
    parser.add_argument("output_arg", nargs="?", help="Output encoded keyword file")
    parser.add_argument("--text", dest="text_opt", help="Input keyword text file")
    parser.add_argument("--tokens", dest="tokens_opt", help="Output tokens.txt")
    parser.add_argument("--output", dest="output_opt", help="Output encoded keyword file")
    args = parser.parse_args()

    text_path = args.text_opt or args.text_arg
    tokens_path = args.tokens_opt or args.tokens_arg
    output_path = args.output_opt or args.output_arg
    if not text_path or not tokens_path or not output_path:
        raise SystemExit("Provide input, tokens, and output paths via positional args or --text/--tokens/--output.")

    convert_keywords(text_path, tokens_path, output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
