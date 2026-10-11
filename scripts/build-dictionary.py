#!/usr/bin/env python3
"""Developer-only compiler: pinned Hunspell words -> minimal acyclic word graph."""
import argparse
import hashlib
import re
import struct
from pathlib import Path
from urllib.request import urlopen

REVISION = "32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4"
BASE = f"https://raw.githubusercontent.com/LibreOffice/dictionaries/{REVISION}/"
FILES = {
    "ru_RU/ru_RU.dic": "f6047416a0204adbecf3a451b874ec8a97ee37e2cbc714466ef04d8dbcc0d6fc",
    "ru_RU/ru_RU.aff": "38ce7d4af78e211e9bafe4bf7e3d6a2c420591136cb738ec6648f8fdf6524cd7",
    "en/en_US.dic": "f0b1a234bd178bdd01875b2a392a9647f888b8fe879f79c52aae62c2759b3647",
    "en/en_US.aff": "e746c882dd6f303c2c46e7452804b9201115a6942cfeb15f18f8edf774d2e24e",
}
ROOT = Path(__file__).resolve().parent.parent


def source(name, directory):
    if directory:
        with (directory / Path(name).name).open("rb") as file:
            data = file.read(8_000_001)
    else:
        with urlopen(BASE + name, timeout=30) as response:
            data = response.read(8_000_001)
    if len(data) > 8_000_000 or hashlib.sha256(data).hexdigest() != FILES[name]:
        raise ValueError(f"Unverified dictionary source: {name}")
    return data.decode("utf-8-sig")


def encode(word):
    word = word.lower()
    if not 1 <= len(word) <= 64:
        return None
    if re.fullmatch("[a-z]+", word):
        return word.encode("ascii")
    if re.fullmatch("[а-яё]+", word):
        return bytes(160 if c == "ё" else 128 + ord(c) - ord("а") for c in word)
    return None


def expand(dictionary, affixes):
    """This pinned pair uses one-byte flags, single affixes and cross products only."""
    rules, cross = {}, {}
    ignored = {"SET", "TRY", "ICONV", "NOSUGGEST", "COMPOUNDMIN", "ONLYINCOMPOUND",
               "COMPOUNDRULE", "WORDCHARS", "REP"}
    for line in affixes.splitlines():
        fields = line.split()
        if not fields or fields[0].startswith("#"):
            continue
        if fields[0] not in ("PFX", "SFX"):
            if fields[0] not in ignored:
                raise ValueError(f"Unsupported affix directive: {line}")
            continue
        kind, flag = fields[:2]
        if len(fields) == 4:
            cross[kind, flag] = fields[2] == "Y"
            continue
        if len(fields) != 5 or "/" in fields[3]:
            raise ValueError(f"Unsupported affix rule: {line}")
        strip, add, condition = fields[2:]
        pattern = "^" + condition if kind == "PFX" else condition + "$"
        rule = ("" if strip == "0" else strip, "" if add == "0" else add, re.compile(pattern))
        rules.setdefault((kind, flag), []).append(rule)

    def apply(word, kind, flag):
        for strip, add, condition in rules.get((kind, flag), []):
            if not condition.search(word):
                continue
            if kind == "PFX" and word.startswith(strip):
                yield add + word[len(strip):]
            elif kind == "SFX" and word.endswith(strip):
                yield (word[:-len(strip)] if strip else word) + add

    words = set()
    lines = dictionary.splitlines()
    if int(lines[0]) != len(lines) - 1:
        raise ValueError("Dictionary entry count mismatch")
    for entry in lines[1:]:
        word, _, flags = entry.partition("/")
        if "c" in flags:  # en_US ONLYINCOMPOUND: never accept a standalone ordinal fragment.
            continue
        forms = [word]
        for flag in flags:
            forms.extend(apply(word, "SFX", flag))
            for prefixed in apply(word, "PFX", flag):
                forms.append(prefixed)
                if cross.get(("PFX", flag)):
                    for suffix in flags:
                        if cross.get(("SFX", suffix)):
                            forms.extend(apply(prefixed, "SFX", suffix))
        words.update(encoded for form in forms if (encoded := encode(form)) is not None)
    return words


class Node:
    def __init__(self):
        self.terminal = False
        self.edges = {}
        self.index = None


def compile_graph(words):
    root, previous, pending, registry, nodes = Node(), b"", [], {}, []

    def minimize(depth):
        while len(pending) > depth:
            parent, label, child = pending.pop()
            signature = (child.terminal, tuple((k, v.index) for k, v in child.edges.items()))
            if signature not in registry:
                child.index = len(nodes)
                registry[signature] = child
                nodes.append(child)
            parent.edges[label] = registry[signature]

    for word in sorted(words):
        common = 0
        while common < min(len(word), len(previous)) and word[common] == previous[common]:
            common += 1
        minimize(common)
        node = root if common == 0 else pending[common - 1][2]
        for label in word[common:]:
            child = Node()
            node.edges[label] = child
            pending.append((node, label, child))
            node = child
        node.terminal = True
        previous = word
    minimize(0)
    root.index = len(nodes)
    nodes.append(root)
    offsets, payload = [], bytearray()
    for node in nodes:
        offsets.append(16 + len(payload))
        payload.append(len(node.edges) | (128 if node.terminal else 0))
        for label, child in node.edges.items():
            payload.extend(struct.pack("<BI", label, offsets[child.index]))
    data = b"KTLEX001" + struct.pack("<II", offsets[-1], len(words)) + payload
    counts = {}
    for offset in offsets:
        counts[offset] = int(bool(data[offset] & 128)) + sum(
            counts[struct.unpack_from("<I", data, offset + 2 + i * 5)[0]]
            for i in range(data[offset] & 63))
    if counts[offsets[-1]] != len(words) or len(data) > 8_388_608:
        raise ValueError("Serialized graph adds words or exceeds the runtime cap")
    # Check every generated word against the serialized graph, not just the in-memory builder.
    for word in words:
        node = offsets[-1]
        for label in word:
            degree = data[node] & 63
            edges = {data[node + 1 + i * 5]: struct.unpack_from("<I", data, node + 2 + i * 5)[0]
                     for i in range(degree)}
            node = edges[label]
        if not data[node] & 128:
            raise ValueError("Nonterminal word in serialized dictionary")
    return data, len(nodes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="verified upstream basenames, for offline regeneration")
    parser.add_argument("--output", type=Path, default=ROOT / "Sources/KeytideCore/Resources/words.lex")
    args = parser.parse_args()
    words = set()
    for stem in ("ru_RU/ru_RU", "en/en_US"):
        expanded = expand(source(stem + ".dic", args.source_dir), source(stem + ".aff", args.source_dir))
        print(f"{stem}: {len(expanded):,} plain word forms")
        words.update(expanded)
    for line in (ROOT / "scripts/dictionary-extra.txt").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        encoded = encode(line)
        if encoded is None:
            raise ValueError(f"Invalid supplement word: {line}")
        words.add(encoded)
    data, states = compile_graph(words)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"{len(words):,} words, {states:,} states, {len(data):,} bytes, SHA-256 {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main()
