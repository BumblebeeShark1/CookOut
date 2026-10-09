#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
validation_dir=$(mktemp -d /tmp/CookOut-recipe-filesystem.XXXXXX)
trap 'rm -rf "$validation_dir"' EXIT
xcrun swiftc CookOut/CookingNote.swift CookOut/RecipeLibrarySearch.swift CookOut/RecipeOrganization.swift CookOut/RecipeFilesystem.swift CookOut/NotesStore.swift Tests/RecipeFilesystemTests.swift -o "$validation_dir/RecipeFilesystemTests"
"$validation_dir/RecipeFilesystemTests"
