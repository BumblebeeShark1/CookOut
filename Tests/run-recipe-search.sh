#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
validation_dir=$(mktemp -d /tmp/CookOut-recipe-search.XXXXXX)
trap 'rm -rf "$validation_dir"' EXIT
xcrun swiftc CookOut/CookingNote.swift CookOut/RecipeLibrarySearch.swift CookOut/RecipeOrganization.swift CookOut/RecipeFilesystem.swift Tests/RecipeLibrarySearchTests.swift -o "$validation_dir/RecipeLibrarySearchTests"
"$validation_dir/RecipeLibrarySearchTests"
