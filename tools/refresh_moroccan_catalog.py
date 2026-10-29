"""Refresh the bundled Morocco catalog from Open Food Facts Search-a-licious.

The snapshot contains products listed for Morocco with a 611 barcode and
complete energy/protein/carbohydrate/fat values per 100 g or mL. Product data
is contributed by the Open Food Facts community under ODbL; labels remain
the source of truth.
"""

import json
import math
import re
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


OUTPUT = Path(__file__).resolve().parents[1] / "Daywell" / "MoroccanFoods.json"
QUERY = 'countries_tags:"en:morocco" code:611*'
NAMESPACE = uuid.UUID("07cb9a65-07f5-43d6-a9e5-b428fc99dd80")
USER_AGENT = "NAGISEN/0.16.0 (iOS; com.daywell.nutrition; local Morocco catalog)"


def fetch_page(page: int) -> dict:
    url = "https://search.openfoodfacts.org/search?" + urlencode(
        {"q": QUERY, "page": page, "page_size": 500, "langs": "fr,ar,en"}
    )
    for attempt in range(3):
        try:
            with urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=35) as response:
                return json.load(response)
        except Exception:
            if attempt == 2:
                raise
            time.sleep(1 + attempt * 2)
    raise AssertionError("unreachable")


def number(value):
    if isinstance(value, (int, float)) and math.isfinite(value):
        return float(value)
    return None


def as_food(product: dict):
    code = str(product.get("code") or "")
    if not (code.startswith("611") and code.isdigit() and 8 <= len(code) <= 14):
        return None
    countries = product.get("countries_tags") or []
    if "en:morocco" not in countries:
        return None
    name = next(
        (v.strip() for v in (product.get("product_name_fr"), product.get("product_name"),
                             product.get("product_name_ar")) if isinstance(v, str) and v.strip()),
        None,
    )
    if not name or not 3 <= len(name) <= 90 or name.lower() in {"unknown", "product", "produit"}:
        return None
    nutrients = product.get("nutriments") or {}
    kcal = number(nutrients.get("energy-kcal_100g"))
    protein = number(nutrients.get("proteins_100g"))
    carbs = number(nutrients.get("carbohydrates_100g"))
    fat = number(nutrients.get("fat_100g"))
    if any(v is None for v in (kcal, protein, carbs, fat)):
        return None
    if not (0 < kcal <= 900 and all(0 <= v <= 100 for v in (protein, carbs, fat))):
        return None
    macro_kcal = 4 * protein + 4 * carbs + 9 * fat
    if macro_kcal > 0 and abs(macro_kcal - kcal) > max(45, kcal * 0.5):
        return None
    brands = product.get("brands") or []
    brand = ", ".join(brands) if isinstance(brands, list) else str(brands)
    serving_text = str(product.get("serving_size") or "")
    serving = "100 mL" if re.search(r"\bml\b", serving_text, re.I) else "100 g"
    fiber = number(nutrients.get("fiber_100g"))
    sodium = number(nutrients.get("sodium_100g"))
    return {
        "id": str(uuid.uuid5(NAMESPACE, code)).upper(),
        "name": name,
        "brand": brand[:90],
        "serving": serving,
        "calories": round(kcal),
        "protein": protein,
        "carbs": carbs,
        "fat": fat,
        "fiber": fiber if fiber is not None and fiber >= 0 else None,
        "sodium": sodium if sodium is not None and sodium >= 0 else None,
        "barcode": code,
        "source": "Open Food Facts · Morocco catalog",
        "missingMacros": [],
    }


def main():
    first = fetch_page(1)
    total = int(first.get("count") or 0)
    pages = min(20, math.ceil(total / 500))
    by_code = {}
    for page in range(1, pages + 1):
        response = first if page == 1 else fetch_page(page)
        for product in response.get("hits") or []:
            food = as_food(product)
            if food:
                by_code[food["barcode"]] = food
        print(f"page {page}/{pages}: {len(by_code)} usable products")
        time.sleep(0.2)
    foods = sorted(by_code.values(), key=lambda f: (f["brand"].casefold(), f["name"].casefold()))
    snapshot = {
        "source": "Open Food Facts",
        "sourceURL": "https://world.openfoodfacts.org/country/morocco",
        "license": "Open Database License (ODbL)",
        "retrievedAtUTC": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "foods": foods,
    }
    OUTPUT.write_text(json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"saved {len(foods)} foods to {OUTPUT}")


if __name__ == "__main__":
    main()
