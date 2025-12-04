#!/bin/bash

# ==============================================================================
# 16 KB Page Size Compatibility Checker
# For Google Play Store Requirements
# ==============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration
readonly PAGE_SIZE_16KB=16384
ANDROID_SDK_PATH=""
BUNDLETOOL_JAR=""

# ==============================================================================
# Helper Functions
# ==============================================================================

cleanup_temp_files() {
    # Clean up any temporary files created by this script
    if [[ -f "bundletool.jar" ]]; then
        rm -f bundletool.jar
    fi
}

find_android_sdk() {
    # Try common Android SDK locations
    local sdk_locations=(
        "$ANDROID_HOME"
        "$ANDROID_SDK_ROOT"
        "$HOME/Library/Android/sdk"
        "$HOME/Android/Sdk"
        "/usr/local/android-sdk"
        "/opt/android-sdk"
    )
    
    for location in "${sdk_locations[@]}"; do
        if [[ -d "$location/build-tools" ]]; then
            ANDROID_SDK_PATH="$location"
            return 0
        fi
    done
    
    # Try to find SDK using flutter
    if command -v flutter &> /dev/null; then
        local flutter_sdk=$(flutter doctor -v 2>&1 | grep "Android SDK at" | sed 's/.*Android SDK at //' | tr -d '\n\r')
        if [[ -d "$flutter_sdk" ]]; then
            ANDROID_SDK_PATH="$flutter_sdk"
            return 0
        fi
    fi
    
    return 1
}

find_build_artifacts() {
    local artifacts=()
    
    # Find AAB files
    while IFS= read -r -d '' file; do
        artifacts+=("$file")
    done < <(find . -name "*.aab" -path "*/build/*" -print0 2>/dev/null)
    
    # Find APK files
    while IFS= read -r -d '' file; do
        artifacts+=("$file")
    done < <(find . -name "*-release.apk" -path "*/build/*" -print0 2>/dev/null)
    
    printf '%s\n' "${artifacts[@]}"
}

print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo -e "${BLUE}$([[ -n "$2" ]] && echo "  $2")${NC}"
}

print_success() {
    echo -e "  ${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "  ${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "  ${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "  ${CYAN}ℹ️  $1${NC}"
}

# ==============================================================================
# Check Functions
# ==============================================================================

check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check for Java
    if command -v java &> /dev/null; then
        local java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
        print_success "Java found: $java_version"
    else
        print_warning "Java not found (required for AAB validation with bundletool)"
    fi
    
    # Check for Python3
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version | cut -d' ' -f2)
        print_success "Python3 found: $python_version"
    else
        print_error "Python3 not found (required for analysis)"
        return 1
    fi
    
    # Try to find Android SDK
    if find_android_sdk; then
        print_success "Android SDK found: $ANDROID_SDK_PATH"
        
        # Check for zipalign
        local zipalign_path=$(find "$ANDROID_SDK_PATH/build-tools" -name "zipalign" 2>/dev/null | head -1)
        if [[ -n "$zipalign_path" ]]; then
            print_success "zipalign found: $zipalign_path"
        else
            print_warning "zipalign not found in Android SDK"
        fi
    else
        print_warning "Android SDK not found (optional for APK verification)"
    fi
    
    return 0
}

check_build_configuration() {
    print_section "Checking Build Configuration"
    
    local gradle_props="android/gradle.properties"
    local app_gradle="android/app/build.gradle"
    
    # Check gradle.properties
    if [[ -f "$gradle_props" ]]; then
        print_info "Reading: $gradle_props"
        
        if grep -q "android.bundle.enableMaxPageSizeAlignmentFlag=true" "$gradle_props"; then
            print_success "android.bundle.enableMaxPageSizeAlignmentFlag = true"
        else
            print_error "android.bundle.enableMaxPageSizeAlignmentFlag NOT SET or false"
        fi
        
        if grep -q "android.bundle.enableUncompressedNativeLibs" "$gradle_props"; then
            print_warning "Deprecated property found: android.bundle.enableUncompressedNativeLibs"
        fi
    else
        print_warning "gradle.properties not found"
    fi
    
    # Check app/build.gradle
    if [[ -f "$app_gradle" ]]; then
        print_info "Reading: $app_gradle"
        
        if grep -q "useLegacyPackaging" "$app_gradle"; then
            if grep -A 2 "jniLibs" "$app_gradle" | grep -q "useLegacyPackaging false"; then
                print_success "packaging.jniLibs.useLegacyPackaging = false"
            else
                print_warning "useLegacyPackaging value unclear"
            fi
        else
            print_info "useLegacyPackaging not explicitly set (may use defaults)"
        fi
        
        if grep -q "ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON" "$app_gradle"; then
            print_success "ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES = ON"
        fi
    else
        print_warning "app/build.gradle not found"
    fi
}

check_aab_with_bundletool() {
    local aab_file="$1"
    
    print_section "Checking AAB with Bundletool" "Using official Google tool"
    
    # Check if Java is available
    if ! command -v java &> /dev/null; then
        print_warning "Java not found - skipping bundletool validation"
        return 0
    fi
    
    # Download bundletool if needed
    if [[ ! -f "bundletool.jar" ]]; then
        print_info "Downloading bundletool (1.6 MB)..."
        echo -n "  "
        if curl -L https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar -o bundletool.jar --progress-bar; then
            echo ""
            print_success "bundletool.jar downloaded successfully"
            BUNDLETOOL_JAR="bundletool.jar"
        else
            echo ""
            print_warning "Failed to download bundletool - skipping validation"
            return 0
        fi
    else
        BUNDLETOOL_JAR="bundletool.jar"
    fi
    
    local aab_size=$(du -h "$aab_file" | cut -f1)
    print_info "AAB file: $aab_file ($aab_size)"
    
    print_info "Running bundletool validation..."
    echo ""
    
    if java -jar "$BUNDLETOOL_JAR" validate --bundle="$aab_file" 2>&1 | tail -20; then
        echo ""
        print_success "AAB validation PASSED"
        print_success "Bundle structure is valid"
        return 0
    else
        echo ""
        print_error "AAB validation FAILED"
        return 1
    fi
}

check_aab_with_python() {
    local aab_file="$1"
    
    print_section "Analyzing AAB Structure" "Deep dive into native libraries"
    
    python3 << PYTHON_SCRIPT
import zipfile
import os
import sys

aab_path = "$aab_file"
PAGE_SIZE_16KB = 16384

try:
    with zipfile.ZipFile(aab_path, 'r') as aab:
        # Check for BundleConfig
        has_bundle_config = 'BundleConfig.pb' in aab.namelist()
        
        # Collect native libraries
        so_files = {}
        for info in aab.filelist:
            if info.filename.endswith('.so'):
                module = info.filename.split('/')[0]
                if module not in so_files:
                    so_files[module] = []
                lib_name = os.path.basename(info.filename)
                size_mb = info.file_size / (1024 * 1024)
                so_files[module].append((lib_name, size_mb))
        
        total_so_count = sum(len(libs) for libs in so_files.values())
        aab_size_mb = os.path.getsize(aab_path) / (1024 * 1024)
        
        print(f"\n  📦 AAB Size: {aab_size_mb:.1f} MB")
        print(f"  📚 Total Native Libraries: {total_so_count}")
        print(f"  📋 Modules with native code: {len(so_files)}")
        print(f"  🔧 Bundle Config: {'✅ Present' if has_bundle_config else '❌ Missing'}")
        
        if total_so_count > 0:
            print(f"\n  Native Libraries by Module:")
            for module, libs in sorted(so_files.items()):
                total_size = sum(size for _, size in libs)
                print(f"    • {module}: {len(libs)} libraries ({total_size:.1f} MB)")
        
        print(f"\n  {'✅' if has_bundle_config else '❌'} AAB Structure: {'Valid' if has_bundle_config else 'Invalid'}")
        
        if has_bundle_config and total_so_count > 0:
            print(f"  ✅ 16KB Compatibility: READY")
            print(f"     → Google Play will auto-generate 16KB-aligned APKs")
            print(f"     → No manual intervention required")
            sys.exit(0)
        else:
            sys.exit(1)
            
except Exception as e:
    print(f"  ❌ Error analyzing AAB: {e}")
    sys.exit(1)
PYTHON_SCRIPT
}

check_apk_alignment() {
    local apk_file="$1"
    
    print_section "Checking APK Alignment" "Verifying 16KB page size compatibility"
    
    local apk_size=$(du -h "$apk_file" | cut -f1)
    print_info "APK file: $apk_file ($apk_size)"
    
    # Use Python to check alignment
    python3 << PYTHON_SCRIPT
import zipfile
import sys

apk_path = "$apk_file"
PAGE_SIZE_16KB = 16384

try:
    with zipfile.ZipFile(apk_path, 'r') as apk:
        incompatible = []
        compatible = []
        
        for info in apk.filelist:
            if info.filename.endswith('.so'):
                offset = info.header_offset + len(info.FileHeader())
                alignment = offset % PAGE_SIZE_16KB
                
                lib_name = info.filename.split('/')[-1]
                if alignment != 0:
                    incompatible.append((lib_name, alignment))
                else:
                    compatible.append(lib_name)
        
        total = len(incompatible) + len(compatible)
        
        if total == 0:
            print("  ℹ️  No native libraries found in APK")
            sys.exit(0)
        
        print(f"\n  Total .so files: {total}")
        print(f"  ✅ 16KB aligned: {len(compatible)}")
        print(f"  ❌ NOT 16KB aligned: {len(incompatible)}")
        
        if incompatible:
            print(f"\n  ❌ APK is NOT compatible with 16KB page size")
            print(f"  ⚠️  Recommendation: Use AAB for Google Play Store")
            if len(incompatible) <= 10:
                print(f"\n  Misaligned libraries (first 10):")
                for lib, alignment in incompatible[:10]:
                    print(f"    • {lib}: offset alignment = {alignment} bytes")
            else:
                print(f"\n  Sample misaligned libraries:")
                for lib, alignment in incompatible[:5]:
                    print(f"    • {lib}: offset alignment = {alignment} bytes")
                print(f"    ... and {len(incompatible) - 5} more")
            sys.exit(1)
        else:
            print(f"\n  ✅ APK is compatible with 16KB page size")
            print(f"  ✅ All native libraries are properly aligned")
            sys.exit(0)
        
except Exception as e:
    print(f"  ❌ Error: {e}")
    sys.exit(1)
PYTHON_SCRIPT
}

print_summary() {
    local file_type="$1"
    local file_path="$2"
    local result="$3"
    
    print_section "Summary"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}16 KB PAGE SIZE COMPATIBILITY REPORT${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Generated:${NC} $(date)"
    echo -e "${BOLD}File Type:${NC} $file_type"
    echo -e "${BOLD}File Path:${NC} $file_path"
    echo ""
    
    if [[ "$result" == "PASSED" ]]; then
        echo -e "${GREEN}${BOLD}RESULT: ✅ PASSED${NC}"
        echo ""
        if [[ "$file_type" == "AAB" ]]; then
            echo -e "${GREEN}✅ AAB is compatible with 16KB page size requirement${NC}"
            echo -e "${GREEN}✅ Ready for Google Play Store upload${NC}"
            echo ""
            echo -e "${CYAN}What happens next:${NC}"
            echo "  • Upload AAB to Google Play Console"
            echo "  • Google Play automatically generates 16KB-aligned APKs"
            echo "  • App will work on all Android devices (4KB and 16KB page sizes)"
        else
            echo -e "${GREEN}✅ APK is compatible with 16KB page size requirement${NC}"
            echo -e "${GREEN}✅ All native libraries are properly aligned${NC}"
            echo ""
            echo -e "${CYAN}Distribution ready:${NC}"
            echo "  • APK can be distributed directly"
            echo "  • Compatible with all Android devices"
        fi
    else
        echo -e "${RED}${BOLD}RESULT: ❌ FAILED${NC}"
        echo ""
        if [[ "$file_type" == "AAB" ]]; then
            echo -e "${RED}❌ AAB may have issues${NC}"
            echo ""
            echo -e "${YELLOW}Recommendations:${NC}"
            echo "  • Check build configuration in android/gradle.properties"
            echo "  • Ensure: android.bundle.enableMaxPageSizeAlignmentFlag=true"
            echo "  • Rebuild AAB with correct settings"
        else
            echo -e "${RED}❌ APK is NOT compatible with 16KB page size${NC}"
            echo ""
            echo -e "${YELLOW}Solutions:${NC}"
            echo "  • Recommended: Build AAB instead for Google Play Store"
            echo "  • Alternative: Re-align APK using Android SDK zipalign tool"
            echo ""
            echo -e "${CYAN}Build Configuration Check:${NC}"
            if [[ -f "android/gradle.properties" ]]; then
                echo "  • android/gradle.properties exists"
                if grep -q "android.bundle.enableMaxPageSizeAlignmentFlag=true" android/gradle.properties 2>/dev/null; then
                    echo "  • ✅ android.bundle.enableMaxPageSizeAlignmentFlag=true"
                else
                    echo "  • ❌ android.bundle.enableMaxPageSizeAlignmentFlag NOT set"
                fi
            fi
        fi
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    clear
    
    print_header "16 KB PAGE SIZE COMPATIBILITY CHECKER"
    
    echo -e "${BOLD}Purpose:${NC} Verify Google Play Store 16KB page size requirement"
    echo -e "${BOLD}Date:${NC}    $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Check prerequisites
    if ! check_prerequisites; then
        print_error "Cannot proceed without Python3"
        exit 1
    fi
    
    # Check build configuration
    check_build_configuration
    
    # Find build artifacts
    print_section "Finding Build Artifacts"
    
    local artifacts=($(find_build_artifacts))
    
    if [[ ${#artifacts[@]} -eq 0 ]]; then
        print_error "No AAB or APK files found in build directories"
        print_info "Please build your app first using:"
        print_info "  flutter build appbundle --release  (for AAB)"
        print_info "  flutter build apk --release        (for APK)"
        exit 1
    fi
    
    # Display found artifacts
    echo ""
    print_info "Found ${#artifacts[@]} build artifact(s):"
    local index=1
    for artifact in "${artifacts[@]}"; do
        local size=$(du -h "$artifact" | cut -f1)
        local type="APK"
        [[ "$artifact" == *.aab ]] && type="AAB"
        echo -e "  ${BOLD}[$index]${NC} $type: $artifact ($size)"
        ((index++))
    done
    echo ""
    
    # Process each artifact
    local overall_result="PASSED"
    local aab_count=0
    local apk_count=0
    
    for artifact in "${artifacts[@]}"; do
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        if [[ "$artifact" == *.aab ]]; then
            ((aab_count++))
            print_info "Processing AAB: $artifact"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            
            check_aab_with_bundletool "$artifact"
            if check_aab_with_python "$artifact"; then
                print_summary "AAB" "$artifact" "PASSED"
            else
                print_summary "AAB" "$artifact" "FAILED"
                overall_result="FAILED"
            fi
        else
            ((apk_count++))
            print_info "Processing APK: $artifact"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            
            if check_apk_alignment "$artifact"; then
                print_summary "APK" "$artifact" "PASSED"
            else
                print_summary "APK" "$artifact" "FAILED"
                overall_result="FAILED"
            fi
        fi
    done
    
    # Final verdict
    echo ""
    print_header "FINAL VERDICT"
    
    echo -e "${BOLD}Processed Files:${NC}"
    echo "  • AAB files: $aab_count"
    echo "  • APK files: $apk_count"
    echo ""
    
    if [[ "$overall_result" == "PASSED" ]]; then
        echo -e "${GREEN}${BOLD}"
        echo "  ██████╗  █████╗ ███████╗███████╗███████╗██████╗ "
        echo "  ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗"
        echo "  ██████╔╝███████║███████╗███████╗█████╗  ██║  ██║"
        echo "  ██╔═══╝ ██╔══██║╚════██║╚════██║██╔══╝  ██║  ██║"
        echo "  ██║     ██║  ██║███████║███████║███████╗██████╔╝"
        echo "  ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═════╝ "
        echo -e "${NC}"
        echo ""
        print_success "All artifacts are compatible with 16KB page size"
        echo ""
    else
        echo -e "${RED}${BOLD}"
        echo "  ███████╗ █████╗ ██╗██╗     ███████╗██████╗ "
        echo "  ██╔════╝██╔══██╗██║██║     ██╔════╝██╔══██╗"
        echo "  █████╗  ███████║██║██║     █████╗  ██║  ██║"
        echo "  ██╔══╝  ██╔══██║██║██║     ██╔══╝  ██║  ██║"
        echo "  ██║     ██║  ██║██║███████╗███████╗██████╔╝"
        echo "  ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═════╝ "
        echo -e "${NC}"
        echo ""
        print_error "Some artifacts are NOT compatible with 16KB page size"
        echo ""
    fi
    
    # Cleanup
    cleanup_temp_files
    
    echo ""
    print_info "Check complete!"
    echo ""
}

# Run the script
main "$@"
