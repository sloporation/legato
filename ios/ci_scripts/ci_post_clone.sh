#!/bin/sh
# Xcode Cloud runs this after cloning. Legato.xcodeproj isn't in git (XcodeGen makes it from project.yml), so make it here, as the
# GitHub workflow does; cmake builds TagLib for the Mac app. Xcode Cloud doesn't resolve packages itself and wants Package.resolved,
# which lives inside the project, so resolve them here too (Tether is pinned to a commit in project.yml).
set -eu

brew install xcodegen cmake
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate
xcodebuild -resolvePackageDependencies -project Legato.xcodeproj -scheme Legato
