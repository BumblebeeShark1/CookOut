#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
validation_dir=$(mktemp -d /tmp/CookOut-meal-planning.XXXXXX)
trap 'rm -rf "$validation_dir"' EXIT
xcrun swiftc CookOut/CookingNote.swift CookOut/RecipeLibrarySearch.swift CookOut/RecipeOrganization.swift CookOut/RecipeFilesystem.swift CookOut/RecipeQuantity.swift CookOut/RecipeBank.swift CookOut/MealPlanningEngine.swift CookOut/MealPlanStore.swift CookOut/CookingAssistantPolicy.swift CookOut/GroqChatService.swift CookOut/GroqMealPlanService.swift Tests/MealPlanningTests.swift -o "$validation_dir/MealPlanningTests"
"$validation_dir/MealPlanningTests"
