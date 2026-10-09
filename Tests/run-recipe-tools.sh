#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
validation_dir=$(mktemp -d /tmp/CookOut-recipe-tools.XXXXXX)
trap 'rm -rf "$validation_dir"' EXIT
xcrun swiftc CookOut/CookingNote.swift CookOut/RecipeQuantity.swift CookOut/RecipeBank.swift CookOut/MealPlanningEngine.swift CookOut/MealPlanStore.swift Tests/RecipeToolsTests.swift -o "$validation_dir/RecipeToolsTests"
"$validation_dir/RecipeToolsTests"
