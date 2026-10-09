#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
validation_dir=$(mktemp -d /tmp/CookOut-organization.XXXXXX)
trap 'rm -rf "$validation_dir"' EXIT
xcrun swiftc CookOut/CookingNote.swift CookOut/RecipeLibrarySearch.swift CookOut/RecipeOrganization.swift CookOut/RecipeFilesystem.swift CookOut/NotesStore.swift Tests/RecipeOrganizationTests.swift -o "$validation_dir/RecipeOrganizationTests"
"$validation_dir/RecipeOrganizationTests"
