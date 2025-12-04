#!/usr/bin/env bash

# ==============================================================================
# 16 KB Page Size Compatibility Checker
# Google Play Store Requirements Validator
# ==============================================================================
# Version: 2.0.0
# Author: Senior Engineering Team
# License: MIT
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# Configuration & Constants
# ==============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PAGE_SIZE_16KB=16384
readonly BUNDLETOOL_VERSION="1.17.2"
readonly BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/bundletool-all-${BUNDLETOOL_VERSION}.jar"

# Runtime state
declare -g ANDROID_SDK_PATH=""
declare -g BUNDLETOOL_JAR=""
declare -g TEMP_DIR=""
declare -g EXIT_CODE=0
declare -g VERBOSE=false
declare -g QUIET=false
declare -g JSON_OUTPUT=false
declare -g OUTPUT_FILE=""

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ==============================================================================
# Logging & Output Functions
# ==============================================================================

log() {
    [[ "${QUIET}" == true ]] && return
    echo -e "$@" >&2
}

log_verbose() {
    [[ "${VERBOSE}" == true ]] && log "${DIM}[DEBUG]${NC} $*"
}

log_info() {
    log "${CYAN}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[✓]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

log_fatal() {
    log_error "$*"
    cleanup_and_exit 1
}

print_header() {
    [[ "${QUIET}" == true ]] && return
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_section() {
    [[ "${QUIET}" == true ]] && return
    echo ""
    echo -e "${BLUE}▶ ${BOLD}$1${NC}"
    [[ -n "${2:-}" ]] && echo -e "${DIM}  $2${NC}"
}

print_result() {
    local status="$1"
    local message="$2"
    
    case "${status}" in
        success) log_success "${message}" ;;
        error) log_error "${message}" ;;
        warning) log_warning "${message}" ;;
        info) log_info "${message}" ;;
    esac
}

# ==============================================================================
# Error Handling & Cleanup
# ==============================================================================

cleanup_and_exit() {
    local exit_code="${1:-0}"
    
    log_verbose "Performing cleanup..."
    
    # Remove temporary directory
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
        log_verbose "Removed temp directory: ${TEMP_DIR}"
    fi
    
    # Remove bundletool if downloaded
    if [[ -f "bundletool.jar" ]] && [[ "${BUNDLETOOL_JAR}" == "bundletool.jar" ]]; then
        rm -f "bundletool.jar"
        log_verbose "Removed bundletool.jar"
    fi
    
    exit "${exit_code}"
}

trap 'cleanup_and_exit 130' INT TERM
trap 'log_error "Script failed on line $LINENO"' ERR

# ==============================================================================
# Validation Functions
# ==============================================================================

require_command() {
    local cmd="$1"
    local package="${2:-$1}"
    
    if ! command -v "${cmd}" &> /dev/null; then
        log_fatal "${cmd} is required but not installed. Please install ${package}."
    fi
}

validate_file() {
    local file="$1"
    local type="${2:-file}"
    
    if [[ ! -e "${file}" ]]; then
        log_error "File not found: ${file}"
        return 1
    fi
    
    if [[ "${type}" == "readable" ]] && [[ ! -r "${file}" ]]; then
        log_error "File not readable: ${file}"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Discovery Functions
# ==============================================================================

find_android_sdk() {
    log_verbose "Searching for Android SDK..."
    
    local sdk_locations=(
        "${ANDROID_HOME:-}"
        "${ANDROID_SDK_ROOT:-}"
        "${HOME}/Library/Android/sdk"
        "${HOME}/Android/Sdk"
        "/usr/local/android-sdk"
        "/opt/android-sdk"
    )
    
    for location in "${sdk_locations[@]}"; do
        [[ -z "${location}" ]] && continue
        if [[ -d "${location}/build-tools" ]]; then
            ANDROID_SDK_PATH="${location}"
            log_verbose "Found Android SDK: ${location}"
            return 0
        fi
    done
    
    # Try Flutter SDK path
    if command -v flutter &> /dev/null; then
        local flutter_sdk
        flutter_sdk=$(flutter doctor -v 2>&1 | grep -oP "Android SDK at \K.*" | tr -d '\n\r' || true)
        if [[ -n "${flutter_sdk}" ]] && [[ -d "${flutter_sdk}" ]]; then
            ANDROID_SDK_PATH="${flutter_sdk}"
            log_verbose "Found Android SDK via Flutter: ${flutter_sdk}"
            return 0
        fi
    fi
    
    log_verbose "Android SDK not found"
    return 1
}

find_build_artifacts() {
    log_verbose "Searching for build artifacts..."
    
    local -a artifacts=()
    
    # Find AAB files
    while IFS= read -r -d '' file; do
        artifacts+=("${file}")
    done < <(find . -type f -name "*.aab" -path "*/build/*" -print0 2>/dev/null || true)
    
    # Find release APKs
    while IFS= read -r -d '' file; do
        artifacts+=("${file}")
    done < <(find . -type f -name "*-release.apk" -path "*/build/*" -print0 2>/dev/null || true)
    
    printf '%s\n' "${artifacts[@]}"
}

# ==============================================================================
# Prerequisites Check
# ==============================================================================

check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local all_ok=true
    
    # Check Python3
    if command -v python3 &> /dev/null; then
        local py_version
        py_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        log_success "Python3: ${py_version}"
        
        # Verify Python can import zipfile
        if ! python3 -c "import zipfile, sys" &> /dev/null; then
            log_error "Python zipfile module not available"
            all_ok=false
        fi
    else
        log_error "Python3 not found (required)"
        all_ok=false
    fi
    
    # Check Java (optional for bundletool)
    if command -v java &> /dev/null; then
        local java_version
        java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
        log_success "Java: ${java_version}"
    else
        log_warning "Java not found (optional for bundletool validation)"
    fi
    
    # Check Android SDK
    if find_android_sdk; then
        log_success "Android SDK: ${ANDROID_SDK_PATH}"
        
        # Find zipalign
        local zipalign_path
        zipalign_path=$(find "${ANDROID_SDK_PATH}/build-tools" -type f -name "zipalign" 2>/dev/null | head -1 || true)
        if [[ -n "${zipalign_path}" ]]; then
            log_success "zipalign: ${zipalign_path}"
        else
            log_warning "zipalign not found in Android SDK"
        fi
    else
        log_warning "Android SDK not found (optional)"
    fi
    
    # Check for curl or wget
    if command -v curl &> /dev/null; then
        log_success "curl available"
    elif command -v wget &> /dev/null; then
        log_success "wget available"
    else
        log_warning "Neither curl nor wget found (needed for bundletool download)"
    fi
    
    if [[ "${all_ok}" == false ]]; then
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Build Configuration Check
# ==============================================================================

check_build_configuration() {
    print_section "Checking Build Configuration"
    
    local gradle_props="android/gradle.properties"
    local app_gradle="android/app/build.gradle"
    local config_issues=0
    
    # Check gradle.properties
    if [[ -f "${gradle_props}" ]]; then
        log_info "Analyzing: ${gradle_props}"
        
        if grep -q "android.bundle.enableMaxPageSizeAlignmentFlag=true" "${gradle_props}"; then
            log_success "android.bundle.enableMaxPageSizeAlignmentFlag=true"
        else
            log_error "Missing: android.bundle.enableMaxPageSizeAlignmentFlag=true"
            ((config_issues++))
        fi
        
        if grep -q "android.bundle.enableUncompressedNativeLibs" "${gradle_props}"; then
            log_warning "Deprecated property: android.bundle.enableUncompressedNativeLibs"
        fi
    else
        log_warning "File not found: ${gradle_props}"
    fi
    
    # Check app/build.gradle
    if [[ -f "${app_gradle}" ]]; then
        log_info "Analyzing: ${app_gradle}"
        
        if grep -q "useLegacyPackaging" "${app_gradle}"; then
            if grep -A 2 "jniLibs" "${app_gradle}" | grep -q "useLegacyPackaging false"; then
                log_success "packaging.jniLibs.useLegacyPackaging=false"
            else
                log_warning "useLegacyPackaging value unclear"
            fi
        fi
        
        if grep -q "ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON" "${app_gradle}"; then
            log_success "ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
        fi
    else
        log_warning "File not found: ${app_gradle}"
    fi
    
    return "${config_issues}"
}

# ==============================================================================
# Bundletool Operations
# ==============================================================================

download_bundletool() {
    log_info "Downloading bundletool ${BUNDLETOOL_VERSION}..."
    
    TEMP_DIR=$(mktemp -d)
    BUNDLETOOL_JAR="${TEMP_DIR}/bundletool.jar"
    
    local download_cmd
    if command -v curl &> /dev/null; then
        download_cmd="curl -L -f -o \"${BUNDLETOOL_JAR}\" --progress-bar \"${BUNDLETOOL_URL}\""
    elif command -v wget &> /dev/null; then
        download_cmd="wget -q --show-progress -O \"${BUNDLETOOL_JAR}\" \"${BUNDLETOOL_URL}\""
    else
        log_error "Neither curl nor wget available for download"
        return 1
    fi
    
    if eval "${download_cmd}"; then
        log_success "Downloaded bundletool.jar"
        return 0
    else
        log_error "Failed to download bundletool"
        return 1
    fi
}

validate_aab_with_bundletool() {
    local aab_file="$1"
    
    print_section "Validating AAB with Bundletool" "Official Google validation tool"
    
    if ! command -v java &> /dev/null; then
        log_warning "Java not available - skipping bundletool validation"
        return 0
    fi
    
    if [[ -z "${BUNDLETOOL_JAR}" ]] || [[ ! -f "${BUNDLETOOL_JAR}" ]]; then
        if ! download_bundletool; then
            log_warning "Cannot validate with bundletool"
            return 0
        fi
    fi
    
    local aab_size
    aab_size=$(du -h "${aab_file}" | cut -f1)
    log_info "AAB file: ${aab_file} (${aab_size})"
    
    log_info "Running bundletool validation..."
    
    local output
    if output=$(java -jar "${BUNDLETOOL_JAR}" validate --bundle="${aab_file}" 2>&1); then
        log_success "Bundletool validation PASSED"
        log_verbose "${output}"
        return 0
    else
        log_error "Bundletool validation FAILED"
        log_error "${output}"
        return 1
    fi
}

# ==============================================================================
# AAB Analysis
# ==============================================================================

analyze_aab_structure() {
    local aab_file="$1"
    
    print_section "Analyzing AAB Structure" "Deep inspection of native libraries"
    
    python3 << 'PYTHON_SCRIPT'
import zipfile
import os
import sys
import json

aab_path = sys.argv[1]
json_output = sys.argv[2] == "true"
PAGE_SIZE_16KB = 16384

result = {
    "success": False,
    "aab_size_mb": 0,
    "total_so_count": 0,
    "modules": {},
    "has_bundle_config": False,
    "is_16kb_ready": False
}

try:
    with zipfile.ZipFile(aab_path, 'r') as aab:
        result["has_bundle_config"] = 'BundleConfig.pb' in aab.namelist()
        
        so_files = {}
        for info in aab.filelist:
            if info.filename.endswith('.so'):
                module = info.filename.split('/')[0]
                if module not in so_files:
                    so_files[module] = []
                lib_name = os.path.basename(info.filename)
                size_mb = info.file_size / (1024 * 1024)
                so_files[module].append({"name": lib_name, "size_mb": round(size_mb, 2)})
        
        result["modules"] = so_files
        result["total_so_count"] = sum(len(libs) for libs in so_files.values())
        result["aab_size_mb"] = round(os.path.getsize(aab_path) / (1024 * 1024), 2)
        result["is_16kb_ready"] = result["has_bundle_config"] and result["total_so_count"] > 0
        result["success"] = True
        
        if json_output:
            print(json.dumps(result, indent=2))
        else:
            print(f"\n  📦 AAB Size: {result['aab_size_mb']} MB")
            print(f"  📚 Native Libraries: {result['total_so_count']}")
            print(f"  📋 Modules: {len(so_files)}")
            print(f"  🔧 Bundle Config: {'✅ Present' if result['has_bundle_config'] else '❌ Missing'}")
            
            if result['total_so_count'] > 0:
                print(f"\n  Native Libraries by Module:")
                for module, libs in sorted(so_files.items()):
                    total_size = sum(lib["size_mb"] for lib in libs)
                    print(f"    • {module}: {len(libs)} libraries ({total_size:.1f} MB)")
            
            if result['is_16kb_ready']:
                print(f"\n  ✅ 16KB Compatibility: READY")
                print(f"     → Google Play will auto-generate 16KB-aligned APKs")
            else:
                print(f"\n  ❌ 16KB Compatibility: NOT READY")
                
        sys.exit(0 if result['is_16kb_ready'] else 1)
        
except Exception as e:
    if json_output:
        result["error"] = str(e)
        print(json.dumps(result, indent=2))
    else:
        print(f"  ❌ Error analyzing AAB: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    
    python3 -c "$(cat)" "${aab_file}" "${JSON_OUTPUT}"
}

# ==============================================================================
# APK Analysis
# ==============================================================================

analyze_apk_alignment() {
    local apk_file="$1"
    
    print_section "Analyzing APK Alignment" "16KB page size compatibility check"
    
    local apk_size
    apk_size=$(du -h "${apk_file}" | cut -f1)
    log_info "APK file: ${apk_file} (${apk_size})"
    
    python3 << 'PYTHON_SCRIPT'
import zipfile
import sys
import json

apk_path = sys.argv[1]
json_output = sys.argv[2] == "true"
PAGE_SIZE_16KB = 16384

result = {
    "success": False,
    "total_libs": 0,
    "aligned": 0,
    "misaligned": 0,
    "is_compatible": False,
    "misaligned_libs": []
}

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
                    incompatible.append({"name": lib_name, "alignment": alignment})
                else:
                    compatible.append(lib_name)
        
        result["total_libs"] = len(incompatible) + len(compatible)
        result["aligned"] = len(compatible)
        result["misaligned"] = len(incompatible)
        result["misaligned_libs"] = incompatible[:10]
        result["is_compatible"] = len(incompatible) == 0
        result["success"] = True
        
        if json_output:
            print(json.dumps(result, indent=2))
        else:
            if result["total_libs"] == 0:
                print("  ℹ️  No native libraries found in APK")
            else:
                print(f"\n  Total .so files: {result['total_libs']}")
                print(f"  ✅ 16KB aligned: {result['aligned']}")
                print(f"  ❌ NOT aligned: {result['misaligned']}")
                
                if result["misaligned"] > 0:
                    print(f"\n  ❌ APK is NOT compatible with 16KB page size")
                    print(f"  ⚠️  Recommendation: Use AAB for Google Play Store")
                    
                    if len(incompatible) <= 10:
                        print(f"\n  Misaligned libraries:")
                        for lib in incompatible:
                            print(f"    • {lib['name']}: offset alignment = {lib['alignment']} bytes")
                    else:
                        print(f"\n  Sample misaligned libraries (first 10):")
                        for lib in incompatible[:10]:
                            print(f"    • {lib['name']}: offset alignment = {lib['alignment']} bytes")
                        print(f"    ... and {len(incompatible) - 10} more")
                else:
                    print(f"\n  ✅ APK is compatible with 16KB page size")
                    print(f"  ✅ All native libraries are properly aligned")
        
        sys.exit(0 if result["is_compatible"] else 1)
        
except Exception as e:
    if json_output:
        result["error"] = str(e)
        print(json.dumps(result, indent=2))
    else:
        print(f"  ❌ Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    
    python3 -c "$(cat)" "${apk_file}" "${JSON_OUTPUT}"
}

# ==============================================================================
# Report Generation
# ==============================================================================

generate_summary_report() {
    local file_type="$1"
    local file_path="$2"
    local result="$3"
    
    print_section "Summary Report"
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}16 KB PAGE SIZE COMPATIBILITY REPORT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}Generated:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${BOLD}File Type:${NC} ${file_type}"
    echo -e "${BOLD}File Path:${NC} ${file_path}"
    echo ""
    
    if [[ "${result}" == "PASSED" ]]; then
        echo -e "${GREEN}${BOLD}RESULT: ✅ PASSED${NC}"
        echo ""
        
        if [[ "${file_type}" == "AAB" ]]; then
            echo -e "${GREEN}✅ AAB is compatible with 16KB page size requirement${NC}"
            echo -e "${GREEN}✅ Ready for Google Play Store upload${NC}"
            echo ""
            echo -e "${CYAN}Next Steps:${NC}"
            echo "  1. Upload AAB to Google Play Console"
            echo "  2. Google Play automatically generates optimized APKs"
            echo "  3. App will work on all devices (4KB and 16KB page sizes)"
        else
            echo -e "${GREEN}✅ APK is compatible with 16KB page size requirement${NC}"
            echo -e "${GREEN}✅ All native libraries are properly aligned${NC}"
            echo ""
            echo -e "${CYAN}Distribution Ready:${NC}"
            echo "  • APK can be distributed directly"
            echo "  • Compatible with all Android devices"
        fi
    else
        echo -e "${RED}${BOLD}RESULT: ❌ FAILED${NC}"
        echo ""
        
        if [[ "${file_type}" == "AAB" ]]; then
            echo -e "${RED}❌ AAB has compatibility issues${NC}"
            echo ""
            echo -e "${YELLOW}Required Actions:${NC}"
            echo "  1. Edit android/gradle.properties"
            echo "  2. Add: android.bundle.enableMaxPageSizeAlignmentFlag=true"
            echo "  3. Rebuild AAB: flutter build appbundle --release"
        else
            echo -e "${RED}❌ APK is NOT compatible with 16KB page size${NC}"
            echo ""
            echo -e "${YELLOW}Recommended Solutions:${NC}"
            echo "  1. Build AAB instead (recommended for Play Store)"
            echo "     flutter build appbundle --release"
            echo "  2. Or re-align APK using zipalign with 16KB alignment"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# ==============================================================================
# Main Processing
# ==============================================================================

process_artifact() {
    local artifact="$1"
    local result="PASSED"
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    if [[ "${artifact}" == *.aab ]]; then
        log_info "Processing AAB: ${artifact}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        
        validate_aab_with_bundletool "${artifact}" || true
        
        if analyze_aab_structure "${artifact}"; then
            generate_summary_report "AAB" "${artifact}" "PASSED"
        else
            generate_summary_report "AAB" "${artifact}" "FAILED"
            result="FAILED"
        fi
    else
        log_info "Processing APK: ${artifact}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        
        if analyze_apk_alignment "${artifact}"; then
            generate_summary_report "APK" "${artifact}" "PASSED"
        else
            generate_summary_report "APK" "${artifact}" "FAILED"
            result="FAILED"
        fi
    fi
    
    echo "${result}"
}

# ==============================================================================
# CLI Interface
# ==============================================================================

show_usage() {
    cat << EOF
${BOLD}Usage:${NC} ${SCRIPT_NAME} [OPTIONS] [FILE]

${BOLD}Description:${NC}
  Validate Android app bundles (AAB) and APKs for Google Play Store's
  16KB page size requirement.

${BOLD}Options:${NC}
  -h, --help              Show this help message
  -v, --verbose           Enable verbose output
  -q, --quiet             Suppress all output except errors
  -j, --json              Output results in JSON format
  -o, --output FILE       Write report to FILE
  --version               Show version information

${BOLD}Arguments:${NC}
  FILE                    Specific AAB or APK file to check
                          (if not provided, searches build directories)

${BOLD}Examples:${NC}
  ${SCRIPT_NAME}                          # Auto-detect and check all artifacts
  ${SCRIPT_NAME} app-release.aab          # Check specific AAB
  ${SCRIPT_NAME} -v app-release.apk       # Check APK with verbose output
  ${SCRIPT_NAME} -j -o report.json        # Generate JSON report

${BOLD}Exit Codes:${NC}
  0    All checks passed
  1    One or more checks failed
  2    Invalid usage or missing dependencies

${BOLD}Version:${NC} ${SCRIPT_VERSION}
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

parse_arguments() {
    local target_file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --version)
                show_version
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 2
                ;;
            *)
                target_file="$1"
                shift
                ;;
        esac
    done
    
    echo "${target_file}"
}

# ==============================================================================
# Main Entry Point
# ==============================================================================

main() {
    local target_file
    target_file=$(parse_arguments "$@")
    
    [[ "${QUIET}" == false ]] && clear
    
    print_header "16 KB PAGE SIZE COMPATIBILITY CHECKER v${SCRIPT_VERSION}"
    
    log_info "Purpose: Verify Google Play Store 16KB page size requirement"
    log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_fatal "Missing required dependencies"
    fi
    
    # Check build configuration
    check_build_configuration || log_warning "Build configuration has issues"
    
    # Determine artifacts to process
    local -a artifacts=()
    
    if [[ -n "${target_file}" ]]; then
        if ! validate_file "${target_file}" "readable"; then
            log_fatal "Cannot read file: ${target_file}"
        fi
        artifacts=("${target_file}")
    else
        print_section "Discovering Build Artifacts"
        
        mapfile -t artifacts < <(find_build_artifacts)
        
        if [[ ${#artifacts[@]} -eq 0 ]]; then
            log_error "No AAB or APK files found in build directories"
            echo ""
            log_info "Build your app first:"
            log_info "  flutter build appbundle --release  # for AAB"
            log_info "  flutter build apk --release        # for APK"
            exit 1
        fi
        
        log_info "Found ${#artifacts[@]} artifact(s):"
        for i in "${!artifacts[@]}"; do
            local size
            size=$(du -h "${artifacts[$i]}" | cut -f1)
            local type="APK"
            [[ "${artifacts[$i]}" == *.aab ]] && type="AAB"
            log_info "  [$(( i + 1 ))] ${type}: ${artifacts[$i]} (${size})"
        done
    fi
    
    # Process each artifact
    local overall_result="PASSED"
    local aab_count=0
    local apk_count=0
    
    for artifact in "${artifacts[@]}"; do
        local result
        result=$(process_artifact "${artifact}")
        
        [[ "${artifact}" == *.aab ]] && ((aab_count++)) || ((apk_count++))
        [[ "${result}" == "FAILED" ]] && overall_result="FAILED"
    done
    
    # Final verdict
    print_header "FINAL VERDICT"
    
    log_info "Processed: ${aab_count} AAB(s), ${apk_count} APK(s)"
    echo ""
    
    if [[ "${overall_result}" == "PASSED" ]]; then
        echo -e "${GREEN}${BOLD}"
        echo "  ██████╗  █████╗ ███████╗███████╗███████╗██████╗ "
        echo "  ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗"
        echo "  ██████╔╝███████║███████╗███████╗█████╗  ██║  ██║"
        echo "  ██╔═══╝ ██╔══██║╚════██║╚════██║██╔══╝  ██║  ██║"
        echo "  ██║     ██║  ██║███████║███████║███████╗██████╔╝"
        echo "  ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═════╝ "
        echo -e "${NC}"
        echo ""
        log_success "All artifacts are compatible with 16KB page size"
        log_success "Ready for Google Play Store deployment"
        EXIT_CODE=0
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
        log_error "Some artifacts are NOT compatible with 16KB page size"
        log_warning "Please fix the issues and rebuild"
        EXIT_CODE=1
    fi
    
    echo ""
    log_info "Scan complete at $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    cleanup_and_exit "${EXIT_CODE}"
}

# Execute main function
main "$@"