#!/bin/bash

set -euo pipefail

name="iCanHazRepose"
shortName="iCHR"
loc="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
logFile="$loc/build.log"
logMark=1

# The ad-hoc signing requirement is pinned to the bundle identifier, and both
# Sparkle's installer and the updater compare that requirement across
# versions. Read it from Info.plist so there is exactly one place to change it
# (the Swift side mirrors it in core/BundleIdentity.swift, and a unit test
# keeps the two in sync).
ident=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$loc/Info.plist" 2>/dev/null || true)
if [ -z "$ident" ]; then
    echo "could not read CFBundleIdentifier from Info.plist" >&2
    exit 1
fi

# Load .env if present
if [ -f "$loc/.env" ]; then
    set -a
    source "$loc/.env"
    set +a
fi

bold='\033[1m'
dimColor='\033[2m'
greenColor='\033[32m'
redColor='\033[31m'
noColor='\033[0m'

cd "$loc"

# Progress / error output goes to the terminal when there is one, and to
# stderr otherwise (CI runners have no controlling terminal).
if [ -c /dev/tty ] && { true > /dev/tty; } 2>/dev/null; then
    TTY=/dev/tty
else
    TTY=/dev/stderr
fi

# ── Determine build mode ─────────────────────────────────────────────
#   dev         debug build, ad-hoc signed, launches the app
#   dev-release release build, universal, zipped, uploaded to the dev channel
#   release     release build, universal, zipped + DMG (for a GitHub release)
#   ci          same artifacts as `release`, never uploads, never launches
mode="dev"
case "${1:-}" in
    dev-release) mode="dev-release" ;;
    release)     mode="release" ;;
    ci)          mode="ci" ;;
    *)           mode="dev" ;;
esac

if [ "$mode" = "release" ] || [ "$mode" = "ci" ]; then
    buildConfig="release"
else
    buildConfig="debug"
fi

# Optional: inject the version into the bundle (used by CI, where the
# version comes from the git tag instead of Info.plist).
ICHR_VERSION="${ICHR_VERSION:-}"
ICHR_VERSION="${ICHR_VERSION#v}"

# Extra flags for every `swift` invocation. Set `ICHR_SWIFT_FLAGS=--disable-sandbox`
# where SwiftPM's manifest sandbox cannot run (nested sandboxes, some CI
# containers); it is not needed on a normal machine or on GitHub's runners.
swiftExtra="${ICHR_SWIFT_FLAGS:-}"

# ── Toolchain ────────────────────────────────────────────────────────
# SwiftUI macros (@State and friends) only resolve against a full Xcode.
# Command Line Tools alone fails with "external macro implementation type
# 'SwiftUIMacros.StateMacro' could not be found", and `xcode-select` often still
# points at CLT right after Xcode is installed. Pick the newest full Xcode here
# rather than failing with that message.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    if xcode-select -p 2>/dev/null | grep -q "CommandLineTools"; then
        fullXcode=""
        for candidate in /Applications/Xcode*.app/Contents/Developer; do
            [ -d "$candidate" ] && fullXcode="$candidate"
        done
        if [ -n "$fullXcode" ]; then
            DEVELOPER_DIR="$fullXcode"
            export DEVELOPER_DIR
            echo -e "  ${dimColor}toolchain: $DEVELOPER_DIR (xcode-select points at CLT)${noColor}" > "$TTY"
        else
            echo -e "  ${redColor}warning: only Command Line Tools found — SwiftUI macros need a full Xcode${noColor}" > "$TTY"
        fi
    fi
fi

# ── Determine signing & notarization ─────────────────────────────────
can_sign=false
can_notarize=false

# The `dev-release` channel uploads through a helper that lives outside this
# repository. Without it the build still produces a usable zip, so treat it as
# optional instead of failing at the last step.
can_upload=false
if command -v share >/dev/null 2>&1; then
    can_upload=true
fi

if [ -n "${ICHR_SIGNING_IDENTITY:-}" ] && [ "$mode" != "dev" ]; then
    can_sign=true
    if [ -n "${ICHR_NOTARY_PROFILE:-}" ]; then
        can_notarize=true
    elif [ -n "${ICHR_APPLE_ID:-}" ] && [ -n "${ICHR_TEAM_ID:-}" ] && [ -n "${ICHR_APP_PASSWORD:-}" ]; then
        can_notarize=true
    fi
fi

# ── Helpers ──────────────────────────────────────────────────────────

die() {
    echo -e "${redColor}[FAILED]${noColor}" > "$TTY"
    echo -e "  ${redColor}$1${noColor}" > "$TTY"
    echo -e "  ${dimColor}--- error output ---${noColor}" > "$TTY"
    tail -n +"$logMark" "$logFile" > "$TTY" 2>&1
    echo -e "  ${dimColor}--- end error output ---${noColor}" > "$TTY"

    # On GitHub Actions, also turn the compiler errors into annotations so
    # they show up on the PR / commit without opening the raw log.
    if [ -n "${GITHUB_ACTIONS:-}" ] && [ -f "$logFile" ]; then
        tail -n +"$logMark" "$logFile" 2>/dev/null \
            | grep -m 20 -E "error:|fatal error|Error:|No such file|not found|unable to find|command not found" \
            | sed -e 's/%/%25/g' -e 's/\r//g' 2>/dev/null \
            | while IFS= read -r line; do
                echo "::error::$line"
              done >&2 || true
    fi

    exit 1
}

stepNum=0
totalSteps=0

step() {
    stepNum=$((stepNum + 1))
    printf "  ${dimColor}[%d/%d]${noColor} ${bold}%-36s${noColor} " "$stepNum" "$totalSteps" "$1"
}

ok() {
    echo -e "${greenColor}[OK]${noColor}"
}

run_step() {
    local label="$1"
    local error_msg="$2"
    shift 2
    local func="$1"
    shift

    step "$label"
    echo "--- $label ---" >> "$logFile"
    logMark=$(($(wc -l < "$logFile") + 1))
    # Only the command output is captured: die() runs outside the redirect
    # below, so the error summary still reaches the console in CI (where
    # build.log is never read by a human).
    if ! "$func" "$@" >> "$logFile" 2>&1; then
        die "$error_msg"
    fi
    ok
}

# ── Step functions ───────────────────────────────────────────────────

do_init_log() {
    echo "=== iCanHazRepose build log ===" > "$logFile"
    echo "Date: $(date)" >> "$logFile"
    echo "Mode: $mode" >> "$logFile"
    echo "Signing: $can_sign" >> "$logFile"
    echo "Notarizing: $can_notarize" >> "$logFile"
    echo "" >> "$logFile"

    # Toolchain fingerprint. SwiftUI macros (@State and friends) only resolve
    # against a full Xcode; Command Line Tools alone fails with
    # "external macro implementation type 'SwiftUIMacros.StateMacro' could not
    # be found". Recording this makes that failure obvious after the fact.
    echo "--- toolchain ---" >> "$logFile"
    echo "DEVELOPER_DIR: ${DEVELOPER_DIR:-<unset>}" >> "$logFile"
    echo "xcode-select: $(xcode-select -p 2>&1)" >> "$logFile"
    echo "swiftc: $(xcrun --find swiftc 2>&1)" >> "$logFile"
    echo "swift: $(swift --version 2>&1 | head -2 | tr '\n' ' ')" >> "$logFile"
    echo "uname: $(uname -m) / $(sw_vers -productVersion 2>&1)" >> "$logFile"
    echo "" >> "$logFile"
}

do_clean_dist() {
    rm -rf "$loc/dist/$name.app"
    rm -rf "$loc/dist/$shortName.zip"
    rm -rf "$loc/dist/$shortName-dev.zip"
    rm -rf "$loc/dist/$shortName.dmg"
    rm -rf "$loc/dist/$name"
    mkdir -p "$loc/dist"
}

do_resolve_deps() {
    swift package resolve $swiftExtra
}

do_clean_build() {
    swift package clean $swiftExtra
}

do_compile_arm64() {
    compile_arch arm64
}

do_compile_x86_64() {
    compile_arch x86_64
}

# Recent SwiftPM releases changed the output layout: products now land in
# `.build/out/Products/<Config>` instead of `.build/<arch>-apple-macosx/<config>`.
# Both `--arch` runs also write to the *same* product path, so the arm64 binary
# is gone by the time the x86_64 build finishes. Ask SwiftPM for the real path
# and keep a per-arch copy, which works on old and new toolchains alike.
compile_arch() {
    local arch="$1"
    swift build -c "$buildConfig" --arch "$arch" $swiftExtra
    local binDir
    binDir=$(swift build -c "$buildConfig" --arch "$arch" --show-bin-path $swiftExtra)
    mkdir -p "$loc/.build/stage/$arch"
    cp "$binDir/$name" "$loc/.build/stage/$arch/$name"
}

arch_binary() {
    local arch="$1"
    local staged="$loc/.build/stage/$arch/$name"
    if [ -f "$staged" ]; then
        printf '%s' "$staged"
    else
        # Fallback for older layouts, in case `--show-bin-path` was skipped.
        printf '%s' "$loc/.build/$arch-apple-macosx/$buildConfig/$name"
    fi
}

do_create_universal() {
    lipo -create \
        "$(arch_binary arm64)" \
        "$(arch_binary x86_64)" \
        -output "$loc/dist/$name"
}

do_create_bundle() {
    mkdir -p "$loc/dist/$name.app/Contents/MacOS"
    mkdir -p "$loc/dist/$name.app/Contents/Resources"

    if [ "$mode" = "dev" ]; then
        cp "$(arch_binary arm64)" "$loc/dist/$name.app/Contents/MacOS/$name"
    else
        cp "$loc/dist/$name" "$loc/dist/$name.app/Contents/MacOS/$name"
        rm "$loc/dist/$name"
    fi

    cp "$loc/Info.plist" "$loc/dist/$name.app/Contents/Info.plist"
    cp "$loc/res/main.icns" "$loc/dist/$name.app/Contents/Resources/"
    cp "$loc/res/ui/"*.png "$loc/dist/$name.app/Contents/Resources/"
    cp "$loc/LICENSE" "$loc/dist/$name.app/Contents/Resources/"

    # Override the version when the caller supplies one (git tag in CI).
    if [ -n "$ICHR_VERSION" ]; then
        local plist="$loc/dist/$name.app/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ICHR_VERSION" "$plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ICHR_VERSION" "$plist"
        echo "version set to $ICHR_VERSION"
    fi
}

# Sparkle ships as an XCFramework through SwiftPM. SwiftPM links the executable
# against `@rpath/Sparkle.framework/...` and only adds its own build directory to
# the rpath, so the framework has to be copied into the bundle and the app's
# rpath pointed at it — otherwise the app dies at launch with a dyld error on
# every machine except the one that built it.
do_embed_sparkle() {
    local source
    source=$(find "$loc/.build/artifacts" -maxdepth 6 -type d \
        -path "*/Sparkle.xcframework/macos-*/Sparkle.framework" | head -1)
    if [ -z "$source" ]; then
        echo "Sparkle.framework not found under .build/artifacts — run 'swift package resolve'"
        return 1
    fi
    echo "embedding: $source"

    local frameworks="$loc/dist/$name.app/Contents/Frameworks"
    mkdir -p "$frameworks"
    ditto "$source" "$frameworks/Sparkle.framework"

    local binary="$loc/dist/$name.app/Contents/MacOS/$name"
    if ! otool -l "$binary" | grep -q "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$binary"
    fi
    echo "rpath: @executable_path/../Frameworks"

    # The app must not rely on the rpath alone: prove the dependency resolves.
    if ! otool -L "$binary" | grep -q "@rpath/Sparkle.framework"; then
        echo "executable is not linked against Sparkle"
        return 1
    fi
}

do_codesign() {
    xattr -cr "$loc/dist/$name.app"

    # Sign from the inside out: Sparkle's helper apps and XPC services first, then
    # the framework that contains them, then the app. `--deep` would attempt the
    # same order but is deprecated and quietly skips nested code it does not
    # recognise — which leaves a Sparkle that cannot install an update.
    local frameworks="$loc/dist/$name.app/Contents/Frameworks"
    if [ -d "$frameworks" ]; then
        while IFS= read -r -d '' nested; do
            echo "signing nested: $nested"
            sign_code "$nested" "no"
        done < <(find "$frameworks" -depth -type d \( -name "*.app" -o -name "*.xpc" \) -print0)
        # `Autoupdate` is a bare executable, not a bundle, so the loop above misses
        # it. Leaving it signed by Sparkle's own team breaks notarization ("not
        # signed with a valid Developer ID certificate") the first time a real
        # certificate is configured.
        local autoupdate="$frameworks/Sparkle.framework/Versions/B/Autoupdate"
        if [ -x "$autoupdate" ]; then
            echo "signing nested: $autoupdate"
            sign_code "$autoupdate" "no"
        fi
        sign_code "$frameworks/Sparkle.framework" "no"
    fi

    sign_code "$loc/dist/$name.app" "yes"
}

# $1 = path, $2 = "yes" to pin the ad-hoc designated requirement.
sign_code() {
    local target="$1"
    local pin="$2"
    if [ "$can_sign" = true ]; then
        codesign --force --sign "$ICHR_SIGNING_IDENTITY" --options runtime --timestamp "$target"
    elif [ "$pin" = "yes" ]; then
        # Without a stable designated requirement the ad-hoc signature degrades to
        # a cdhash, which changes on every build.
        codesign --force --sign - -r="designated => identifier \"$ident\"" "$target"
    else
        # Nested Sparkle code keeps its own identifier — pinning ours onto it
        # would make the XPC services indistinguishable from the app.
        codesign --force --sign - "$target"
    fi
}

do_create_zip() {
    local zipName="$1"
    cd "$loc/dist"
    zip -r9 "$zipName" "$name.app"
    cd "$loc"
}

do_create_dmg() {
    local dmgStaging="$loc/dist/dmg_staging"
    local dmgPath="$loc/dist/$shortName.dmg"
    rm -rf "$dmgStaging"
    mkdir -p "$dmgStaging"
    cp -R "$loc/dist/$name.app" "$dmgStaging/"

    local created=false
    if command -v create-dmg >/dev/null 2>&1; then
        # create-dmg drives Finder over AppleScript to lay the window out, which
        # fails on headless CI runners. Fall back to a plain (layout-less) image
        # so a release build never dies on cosmetics.
        if create-dmg \
            --volname "$name" \
            --volicon "$loc/res/main.icns" \
            --background "$loc/res/dmg/bg.png" \
            --window-pos 200 120 \
            --window-size 640 520 \
            --icon-size 128 \
            --icon "$name.app" 192 350 \
            --app-drop-link 448 350 \
            "$dmgPath" \
            "$dmgStaging"; then
            created=true
        else
            echo "create-dmg failed — falling back to hdiutil"
            echo "create-dmg failed, using hdiutil" > "$TTY"
            rm -f "$dmgPath"
        fi
    else
        # Missing create-dmg is not a reason to ship a release without a DMG:
        # the release page links to it.
        echo "create-dmg not installed — using hdiutil"
        echo "create-dmg not installed, using hdiutil" > "$TTY"
    fi

    if [ "$created" = false ]; then
        # The fallback has no window layout, so give it the one thing a plain
        # image still needs: a drop target next to the app.
        ln -sfn /Applications "$dmgStaging/Applications"
        hdiutil create -volname "$name" -srcfolder "$dmgStaging" \
            -ov -format UDZO "$dmgPath"
    fi
    rm -rf "$dmgStaging"
}

do_sign_dmg() {
    codesign --force --sign "$ICHR_SIGNING_IDENTITY" --timestamp "$loc/dist/$shortName.dmg"
}

do_notarize() {
    local file="$1"
    if [ -n "${ICHR_NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$file" --keychain-profile "$ICHR_NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$file" \
            --apple-id "$ICHR_APPLE_ID" \
            --team-id "$ICHR_TEAM_ID" \
            --password "$ICHR_APP_PASSWORD" \
            --wait
    fi
}

do_staple_app() {
    xcrun stapler staple "$loc/dist/$name.app"
}

do_staple_dmg() {
    xcrun stapler staple "$loc/dist/$shortName.dmg"
}

do_verify() {
    codesign --verify --deep --strict --verbose=2 "$loc/dist/$name.app"
    if [ "$can_notarize" = true ]; then
        xcrun stapler validate "$loc/dist/$name.app"
    fi
    if [ "$mode" = "release" ]; then
        spctl -a -vvv "$loc/dist/$shortName.dmg"
        if [ "$can_notarize" = true ]; then
            xcrun stapler validate "$loc/dist/$shortName.dmg"
        fi
    fi
}

do_upload() {
    share "$1"
}

# ── Calculate total steps per mode ───────────────────────────────────
case "$mode" in
    dev)         totalSteps=6 ;;
    dev-release)
        totalSteps=9
        if [ "$can_upload" = true ]; then
            totalSteps=$((totalSteps + 1))
        fi
        if [ "$can_notarize" = true ]; then
            totalSteps=$((totalSteps + 2))
        fi
        if [ "$can_sign" = true ]; then
            totalSteps=$((totalSteps + 1))
        fi
        ;;
    release)
        totalSteps=10
        if [ "$can_sign" = true ]; then
            totalSteps=$((totalSteps + 1))  # sign the DMG
        fi
        if [ "$can_notarize" = true ]; then
            totalSteps=$((totalSteps + 3))  # notarize + staple app + staple DMG
        fi
        if [ "$can_sign" = true ]; then
            # `release` always runs `spctl`, so a certificate is enough here.
            totalSteps=$((totalSteps + 1))  # verify signatures
        fi
        ;;
    ci)
        # `ci` builds the same artifacts as `release`, but `spctl` only passes
        # for a notarized build, so the verification step needs both a
        # certificate and notarization. Counting it on `can_sign` alone made the
        # progress line stop at "12/13" — a step count that never adds up is the
        # kind of detail that makes people distrust the whole output.
        totalSteps=10
        if [ "$can_sign" = true ]; then
            totalSteps=$((totalSteps + 1))  # sign the DMG
        fi
        if [ "$can_notarize" = true ]; then
            totalSteps=$((totalSteps + 3))  # notarize + staple app + staple DMG
            totalSteps=$((totalSteps + 1))  # verify signatures
        fi
        ;;
esac

# ── Build ────────────────────────────────────────────────────────────

do_init_log
do_clean_dist

run_step "Resolving dependencies..."            "failed to resolve dependencies"           do_resolve_deps
run_step "Cleaning build artifacts..."           "failed to clean build artifacts"          do_clean_build
run_step "Compiling Swift sources (arm64)..."    "failed to compile $shortName for arm64"   do_compile_arm64

if [ "$mode" != "dev" ]; then
    run_step "Compiling Swift sources (x86_64)..." "failed to compile $shortName for x86_64" do_compile_x86_64
    run_step "Creating universal binary..."        "failed to create universal binary"        do_create_universal
fi

run_step "Creating APP bundle..."                 "failed to create app bundle"              do_create_bundle
run_step "Embedding Sparkle framework..."         "failed to embed Sparkle.framework"        do_embed_sparkle
run_step "Code-signing APP bundle..."             "failed to code-sign app bundle"           do_codesign

if [ "$mode" != "dev" ]; then
    if [ "$mode" = "release" ] || [ "$mode" = "ci" ]; then
        run_step "Creating distribution ZIP..."    "failed to pack $shortName.zip"            do_create_zip "$shortName.zip"
        run_step "Creating distribution DMG..."    "failed to create dmg"                     do_create_dmg
        if [ "$can_sign" = true ]; then
            run_step "Signing distribution DMG..." "failed to sign dmg"                       do_sign_dmg
        fi
        if [ "$can_notarize" = true ]; then
            run_step "Notarizing release build..." "failed to notarize release build"         do_notarize "$loc/dist/$shortName.dmg"
            run_step "Stapling APP bundle..."      "failed to staple app bundle"              do_staple_app
            run_step "Stapling release DMG..."     "failed to staple release DMG"             do_staple_dmg
        fi
        # `spctl` only passes for notarized builds, so don't gate CI on it
        # when no signing/notarization credentials are configured.
        if [ "$can_sign" = true ] && { [ "$mode" = "release" ] || [ "$can_notarize" = true ]; }; then
            run_step "Verifying signatures..."     "failed to verify signatures"              do_verify
        fi
    else
        run_step "Creating dev ZIP..."             "failed to pack $shortName-dev.zip"        do_create_zip "$shortName-dev.zip"
        if [ "$can_notarize" = true ]; then
            run_step "Notarizing dev build..."     "failed to notarize dev build"             do_notarize "$loc/dist/$shortName-dev.zip"
            run_step "Stapling APP bundle..."      "failed to staple app bundle"              do_staple_app
        fi
        if [ "$can_sign" = true ]; then
            run_step "Verifying signatures..."     "failed to verify signatures"              do_verify
        fi
        if [ "$can_upload" = true ]; then
            run_step "Uploading dev build..."      "failed to upload dev build"               do_upload "$loc/dist/$shortName-dev.zip"
        fi
    fi
fi

# ── Post-build ───────────────────────────────────────────────────────
echo ""
echo -e "  ${greenColor}${bold}Build complete!${noColor}"

case "$mode" in
    dev)
        echo -e "  ${dimColor}mode: development${noColor}"
        echo -e "  ${dimColor}signing: ${redColor}ad-hoc${noColor}"
        echo -e "  ${dimColor}artifacts: dist/$name.app${noColor}"
        echo -e "  ${dimColor}launching...${noColor}"
        "$loc/dist/$name.app/Contents/MacOS/$name"
        ;;
    dev-release)
        echo -e "  ${dimColor}mode: development release${noColor}"
        echo -e "  ${dimColor}signing: $(if [ "$can_sign" = true ]; then echo "${greenColor}Developer ID${noColor}"; else echo "${redColor}ad-hoc${noColor}"; fi)"
        echo -e "  ${dimColor}notarized: $(if [ "$can_notarize" = true ]; then echo "${greenColor}yes${noColor}"; else echo "${redColor}no${noColor}"; fi)"
        echo -e "  ${dimColor}artifacts: dist/$name.app  dist/$shortName-dev.zip${noColor}"
        if [ "$can_upload" = false ]; then
            echo -e "  ${dimColor}upload skipped: 'share' not installed${noColor}"
        fi
        ;;
    release)
        echo -e "  ${dimColor}mode: release${noColor}"
        echo -e "  ${dimColor}signing: $(if [ "$can_sign" = true ]; then echo "${greenColor}Developer ID${noColor}"; else echo "${redColor}ad-hoc${noColor}"; fi)"
        echo -e "  ${dimColor}notarized: $(if [ "$can_notarize" = true ]; then echo "${greenColor}yes${noColor}"; else echo "${redColor}no${noColor}"; fi)"
        echo -e "  ${dimColor}artifacts: dist/$name.app  dist/$shortName.zip  dist/$shortName.dmg${noColor}"
        ;;
    ci)
        ciArtifacts="dist/$name.app  dist/$shortName.zip"
        if [ -f "$loc/dist/$shortName.dmg" ]; then
            ciArtifacts="$ciArtifacts  dist/$shortName.dmg"
        fi
        echo -e "  ${dimColor}mode: ci${noColor}"
        echo -e "  ${dimColor}version: ${ICHR_VERSION:-<from Info.plist>}${noColor}"
        echo -e "  ${dimColor}signing: $(if [ "$can_sign" = true ]; then echo "${greenColor}Developer ID${noColor}"; else echo "${redColor}ad-hoc${noColor}"; fi)"
        echo -e "  ${dimColor}notarized: $(if [ "$can_notarize" = true ]; then echo "${greenColor}yes${noColor}"; else echo "${redColor}no${noColor}"; fi)"
        echo -e "  ${dimColor}artifacts: $ciArtifacts${noColor}"
        ;;
esac
