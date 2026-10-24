#!/usr/bin/env python3
"""Black-box regression checks for the benchmark CLI; no third-party packages."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / ".build/debug/LumaBenchmark"
checks = 0


def check(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1
    print(f"PASS  {message}")


def run(*args):
    return subprocess.run([str(binary), *args], capture_output=True, text=True, check=False)


def report(*args):
    result = run(*args)
    if result.returncode:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout)


disabled = report("--disable-semantics", "--repetitions", "2", "--warmups", "0")
fixture = root / "Sources/LumaBenchmark/Fixtures/english-v1.json"
check(disabled["schema"] == "lumadesk-benchmark-report/v1", "Report declares a versioned schema")
check(disabled["corpusSHA256"] == hashlib.sha256(fixture.read_bytes()).hexdigest(), "Report identifies exact corpus bytes")
check(disabled["corpusLicense"] == "CC0-1.0" and disabled["documentCount"] == 16 and disabled["queryCount"] == 15, "Bundled corpus retains provenance, license and counts")
modes = {mode["mode"]: mode for mode in disabled["modes"]}
check(set(modes) == {"bm25", "semantic", "hybrid"}, "Default benchmark runs all three retrieval modes")
check(modes["semantic"]["status"] == "unavailable" and modes["semantic"]["evaluatedQueries"] == 0 and modes["semantic"].get("meanRecallAt5") is None, "Disabled semantic mode emits no fabricated quality score")
check(all(q["status"] == "unavailable" and not q["rankedDocumentIDs"] and q.get("ndcgAt5") is None for q in modes["semantic"]["queries"]), "Unavailable semantics never returns lexical baseline results")
check(modes["hybrid"]["fallbackQueries"] == 15 and modes["hybrid"]["semanticQueries"] == 0, "Hybrid records every disabled-model fallback")
check(all(m["coverage"]["embeddedPassages"] == 0 and not m["coverage"]["modelAvailable"] for m in modes.values()), "Disabled model coverage is explicit for every mode")
check(all(m["evaluatedQueries"] == 13 for name, m in modes.items() if name != "semantic"), "Only positively judged queries enter macro quality means")
for name in ("bm25", "hybrid"):
    queries = {q["id"]: q for q in modes[name]["queries"]}
    check(all(queries[q]["status"] == "no-relevant-judgments" and queries[q].get("recallAt5") is None for q in ("no-answer", "empty")), f"{name}: no-answer controls are excluded, not counted as accuracy")
check(all(len(q["milliseconds"]) == 2 and all(t >= 0 for t in q["milliseconds"]) and len(set(q["rankedDocumentIDs"])) == len(q["rankedDocumentIDs"]) <= 5 for m in modes.values() for q in m["queries"]), "Reports retain requested timing samples and unique top-five documents")
repeat = report("--mode", "bm25", "--disable-semantics", "--repetitions", "1", "--warmups", "0")
check([q["rankedDocumentIDs"] for q in repeat["modes"][0]["queries"]] == [q["rankedDocumentIDs"] for q in modes["bm25"]["queries"]], "Pure BM25 rankings are deterministic across independent runs")
check(run("--help").returncode == 0 and "Usage:" in run("--help").stdout, "CLI help documents reproducible options")
for arguments in (("--mode", "invalid"), ("--repetitions", "0"), ("--warmups", "11"), ("--output",), ("--unknown", "value")):
    result = run(*arguments)
    check(result.returncode != 0 and "Benchmark failed:" in result.stderr, f"Invalid arguments fail clearly: {' '.join(arguments)}")

with tempfile.TemporaryDirectory(prefix="lumadesk-benchmark-checks-") as folder:
    folder = Path(folder)
    output = folder / "report.json"
    result = run("--mode", "bm25", "--output", str(output), "--repetitions", "1", "--warmups", "0")
    check(result.returncode == 0 and not result.stdout and json.loads(output.read_text())["modes"][0]["mode"] == "bm25", "Output option writes a usable JSON report without stdout noise")
    corpus = json.loads(fixture.read_text())
    corpus["queries"] = []
    custom = folder / "invalid.json"
    custom.write_text(json.dumps(corpus))
    result = run("--corpus", str(custom))
    check(result.returncode != 0 and "1–200 queries" in result.stderr, "Empty custom evaluations fail before producing misleading reports")
    # The first document contributes more than 12 highly ranked passages. A
    # passage-limited candidate pool would hide all the other relevant documents.
    corpus["documents"] = corpus["documents"][:6]
    for index, document in enumerate(corpus["documents"]):
        document["pages"] = [{"number": 1, "text": "needle " * 3000 if index == 0 else "needle supporting"}]
    corpus["queries"] = [{"id": "many-passages", "text": "needle", "relevance": {document["id"]: 3 for document in corpus["documents"]}}]
    custom.write_text(json.dumps(corpus))
    long_document = report("--corpus", str(custom), "--mode", "bm25", "--disable-semantics", "--repetitions", "1", "--warmups", "0")
    query = long_document["modes"][0]["queries"][0]
    check(len(query["rankedDocumentIDs"]) == 5 and abs(query["recallAt5"] - 5 / 6) < 1e-12, "Long-document passages cannot exhaust the top-five document candidate pool")

print(f"\n{checks}/{checks} benchmark CLI checks passed.")
