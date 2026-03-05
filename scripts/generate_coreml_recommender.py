#!/usr/bin/env python3
"""Train and export the Waypoint CoreML recommendation model.

Usage:
  source /tmp/waypoint-coreml-venv/bin/activate
  python scripts/generate_coreml_recommender.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import random

import coremltools as ct
import numpy as np
from sklearn.ensemble import RandomForestRegressor


INPUT_FEATURES = [
    "budget_center",
    "destination_cost",
    "season_match",
    "style_match",
    "eco_score",
    "climate_match",
    "normalized_co2",
    "crowding_effect",
    "local_sustainability",
]
OUTPUT_FEATURE = "predictedScore"


@dataclass(frozen=True)
class Sample:
    budget_center: float
    destination_cost: float
    season_match: float
    style_match: float
    eco_score: float
    climate_match: float
    normalized_co2: float
    crowding_effect: float
    local_sustainability: float
    target_score: float


def clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def generate_sample(rng: random.Random) -> Sample:
    budget_center = rng.uniform(0.12, 1.0)
    destination_cost = rng.uniform(0.1, 1.0)
    season_match = rng.uniform(0.0, 1.0)
    style_match = rng.uniform(0.0, 1.0)
    eco_score = rng.uniform(0.2, 1.0)
    climate_match = rng.choice([0.7, 1.0])

    people = rng.randint(1, 6)
    distance_km = rng.uniform(180.0, 16000.0)
    co2 = distance_km * 0.18 * people
    normalized_co2 = clamp(co2 / 3500.0, 0.0, 1.0)

    crowding_index = rng.uniform(0.05, 0.95)
    eco_sensitivity = rng.uniform(0.0, 1.0)
    user_crowding_sensitivity = rng.uniform(0.1, 0.9)
    crowding_effect = crowding_index * ((user_crowding_sensitivity + eco_sensitivity) / 2.0)

    local_sustainability = rng.uniform(0.2, 1.0)

    # Mirrors production-style heuristics for ground-truth labels.
    budget_component = clamp(1.0 - abs(destination_cost - budget_center) / max(budget_center, 0.05), 0.0, 1.0)
    preference = clamp(
        (budget_component * 0.30)
        + (season_match * 0.20)
        + (style_match * 0.30)
        + (eco_score * 0.10)
        + (climate_match * 0.10),
        0.0,
        1.0,
    )

    environmental_penalty = clamp((normalized_co2 * 0.60) + (crowding_effect * 0.40), 0.0, 0.9)

    local_approval = clamp(0.8 + (local_sustainability * 0.4), 0.75, 1.3)
    score = clamp(preference * (1.0 - environmental_penalty) * local_approval, 0.0, 1.0)

    return Sample(
        budget_center=budget_center,
        destination_cost=destination_cost,
        season_match=season_match,
        style_match=style_match,
        eco_score=eco_score,
        climate_match=climate_match,
        normalized_co2=normalized_co2,
        crowding_effect=crowding_effect,
        local_sustainability=local_sustainability,
        target_score=score,
    )


def build_dataset(seed: int = 42, size: int = 7000) -> tuple[np.ndarray, np.ndarray]:
    rng = random.Random(seed)
    rows = [generate_sample(rng) for _ in range(size)]

    x = np.array([[getattr(row, name) for name in INPUT_FEATURES] for row in rows], dtype=np.float32)
    y = np.array([row.target_score for row in rows], dtype=np.float32)

    return x, y


def export_model(output_path: Path) -> None:
    x, y = build_dataset()

    model = RandomForestRegressor(
        n_estimators=220,
        max_depth=9,
        min_samples_leaf=4,
        random_state=42,
    )
    model.fit(x, y)

    coreml_model = ct.converters.sklearn.convert(
        model,
        input_features=INPUT_FEATURES,
        output_feature_names=OUTPUT_FEATURE,
    )

    coreml_model.short_description = "Waypoint destination recommendation score model"
    for feature in INPUT_FEATURES:
        coreml_model.input_description[feature] = f"Feature '{feature}' normalized in [0, 1]"
    coreml_model.output_description[OUTPUT_FEATURE] = "Predicted normalized recommendation score"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    coreml_model.save(str(output_path))


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    output_path = repo_root / "Waypoint" / "Resources" / "WaypointRecommender.mlmodel"
    export_model(output_path)
    print(f"Saved CoreML model to: {output_path}")


if __name__ == "__main__":
    main()
