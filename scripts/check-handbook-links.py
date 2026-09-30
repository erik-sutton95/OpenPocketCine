#!/usr/bin/env python3
"""Check rendered handbook routes and anchors, including locale fallback pages."""

import argparse
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids = set()
        self.links = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if "id" in attributes:
            self.ids.add(attributes["id"])
        if tag == "a" and attributes.get("href"):
            self.links.append(attributes["href"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="/")
    parser.add_argument("--dist", type=Path, default=Path("handbook/dist"))
    args = parser.parse_args()
    base = "/" + args.base.strip("/") + "/" if args.base.strip("/") else "/"
    origin = "https://opencapture.org"
    production = "/openpocketcine/docs/"
    pages = {}
    for path in args.dist.rglob("*.html"):
        route = base + path.relative_to(args.dist).as_posix().removesuffix("index.html")
        pages[route] = Page(path.read_text(encoding="utf-8"))
    if not pages:
        parser.error("No rendered HTML found; build the handbook first")
    errors = set()
    for route, page in pages.items():
        for href in page.links:
            target = urlsplit(urljoin(origin + route, href))
            if target.scheme not in ("http", "https") or target.netloc != "opencapture.org":
                continue
            destination = unquote(target.path)
            # Canonical production URLs also resolve during a root preview build.
            if base != production and destination.startswith(production):
                destination = base + destination.removeprefix(production)
            page_route = destination.removesuffix("index.html")
            if page_route in pages:
                if target.fragment and unquote(target.fragment) not in pages[page_route].ids:
                    errors.add((route, href, "missing anchor"))
                continue
            candidate = args.dist / destination.removeprefix(base)
            if destination.startswith(base) and candidate.is_file():
                continue
            # ponytail: website pages outside the handbook live in the private
            # opencapture-site repo, so only handbook routes are checked here.
            if destination.startswith(base):
                errors.add((route, href, "missing route"))
    for route, href, reason in sorted(errors):
        print(f"{route}: {href}: {reason}")
    print(f"Handbook links: {len(pages)} pages, {len(errors)} errors")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
