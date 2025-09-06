#!/usr/bin/env python3
"""
Extract hosts from href attributes in an HTML file and write them as *host* per line.

Usage:
  python main.py INPUT_HTML [OUTPUT_TXT]

If OUTPUT_TXT is not provided, the script writes to <INPUT_BASENAME>_links.txt
alongside the input file.
"""

from __future__ import annotations

import argparse
import os
from html.parser import HTMLParser
from typing import List, Set
from urllib.parse import urlparse


class _HrefParser(HTMLParser):
	def __init__(self) -> None:
		super().__init__()
		self.hrefs: List[str] = []

	def handle_starttag(self, tag: str, attrs):  # type: ignore[override]
		# Collect any href attribute on any tag
		for (k, v) in attrs:
			if k.lower() == "href" and v is not None:
				self.hrefs.append(v)


def extract_hosts_from_html(html_text: str) -> List[str]:
	"""Parse HTML text, extract href values, and return a list of hostnames.

	Rules:
	- Only http/https URLs are considered.
	- Output is the network location (host[:port]) without scheme or path.
	- Duplicates are removed, preserving first-seen order.
	"""
	parser = _HrefParser()
	parser.feed(html_text)

	seen: Set[str] = set()
	hosts: List[str] = []
	for href in parser.hrefs:
		parsed = urlparse(href)
		if parsed.scheme in {"http", "https"} and parsed.netloc:
			host = parsed.netloc
			if host not in seen:
				seen.add(host)
				hosts.append(host)
	return hosts


def main() -> int:
	ap = argparse.ArgumentParser(description="Extract hosts from hrefs in an HTML file.")
	ap.add_argument("input_html", help="Path to input HTML file")
	ap.add_argument(
		"output_txt",
		nargs="?",
		help="Path to output text file (defaults to <input_basename>_links.txt in the same directory)",
	)
	args = ap.parse_args()

	input_path = args.input_html
	if not os.path.isfile(input_path):
		raise SystemExit(f"Input file not found: {input_path}")

	out_path = args.output_txt
	if not out_path:
		base = os.path.splitext(os.path.basename(input_path))[0]
		out_path = os.path.join(os.path.dirname(input_path), f"{base}_links.txt")

	with open(input_path, "r", encoding="utf-8", errors="ignore") as f:
		html_text = f.read()

	hosts = extract_hosts_from_html(html_text)

	with open(out_path, "w", encoding="utf-8") as f:
		for host in hosts:
			f.write(f"*{host}*\n")

	print(f"Wrote {len(hosts)} host(s) to {out_path}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

