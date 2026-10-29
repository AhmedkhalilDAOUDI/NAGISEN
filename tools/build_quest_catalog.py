"""Validate and bundle NAGISEN's original side quest catalog."""

import csv
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "quest_catalog.tsv"
OUTPUT = ROOT / "Daywell" / "QuestCatalog.json"


def main():
    with SOURCE.open(newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file, delimiter="|"))
    assert len(rows) == 100, f"Expected 100 quests, got {len(rows)}"
    assert len({row["id"] for row in rows}) == 100, "Duplicate quest ID"
    assert len({row["title"].casefold() for row in rows}) == 100, "Duplicate quest title"
    assert len({row["detail"].casefold() for row in rows}) == 100, "Duplicate quest task"
    assert Counter(row["category"] for row in rows) == {
        "cardio": 25, "strength": 25, "skill": 25, "hybrid": 25
    }
    symbols = {
        "cardio": "figure.run",
        "strength": "dumbbell",
        "skill": "figure.boxing",
        "hybrid": "bolt.heart",
    }
    quests = []
    for row in rows:
        minutes = int(row["minutes"])
        assert 5 <= minutes <= 40, row
        quests.append({
            "id": row["id"],
            "category": row["category"],
            "title": row["title"],
            "detail": row["detail"],
            "estimatedMinutes": minutes,
            "symbol": symbols[row["category"]],
        })
    OUTPUT.write_text(json.dumps({"quests": quests}, ensure_ascii=False, indent=2) + "\n")
    print(f"Wrote {len(quests)} distinct quests to {OUTPUT}")


if __name__ == "__main__":
    main()
