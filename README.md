# 16KB Page Size Compatibility Checker

A professional-grade tool for validating Android apps against Google Play Store's 16KB page size requirements.

## 🎯 Purpose

Google Play requires all apps to support 16KB page size starting in 2025. This tool validates your AAB/APK files to ensure compliance with this requirement.

## ✨ Features

### Core Capabilities
- **Automated Discovery**: Auto-detects AAB and APK files in your project
- **Deep Analysis**: Inspects native library alignment and bundle structure
- **Bundletool Integration**: Uses Google's official validation tool
- **Multiple Formats**: Supports both AAB (recommended) and APK files
- **Detailed Reports**: Provides actionable feedback and recommendations

### Advanced Features
- **Error Handling**: Comprehensive error detection and recovery
- **Verbose Mode**: Debug output for troubleshooting
- **JSON Output**: Machine-readable results for CI/CD integration
- **Parallel Processing**: Handles multiple artifacts efficiently
- **Clean UI**: Beautiful terminal output with progress indicators

## 📋 Prerequisites

### Required
- **Python 3.6+** with `zipfile` module (usually pre-installed)
- **Bash 4.0+**

### Optional
- **Java 8+** (for bundletool validation)
- **Android SDK** (for zipalign verification)
- **curl or wget** (for downloading bundletool)

## 🚀 Installation

### Quick Start
```bash
# Make executable
chmod +x check_16kb_compatibility.sh

# Run the checker
./check_16kb_compatibility.sh
```

### System-wide Installation
```bash
# Copy to system binary directory
sudo cp check_16kb_compatibility.sh /usr/local/bin/check-16kb

# Make it executable
sudo chmod +x /usr/local/bin/check-16kb

# Run from anywhere
check-16kb
```

## 📖 Usage

### Basic Usage

```bash
# Auto-detect and check all artifacts
./check_16kb_compatibility.sh

# Check specific file
./check_16kb_compatibility.sh app-release.aab

# Verbose output for debugging
./check_16kb_compatibility.sh -v

# Quiet mode (errors only)
./check_16kb_compatibility.sh -q
```

### Advanced Usage

```bash
# Generate JSON report
./check_16kb_compatibility.sh -j -o report.json

# Check specific APK with verbose output
./check_16kb_compatibility.sh -v build/app/outputs/apk/release/app-release.apk

# Pipe to other tools
./check_16kb_compatibility.sh -j | jq '.is_compatible'
```

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Check 16KB Compatibility
  run: |
    chmod +x scripts/check_16kb_compatibility.sh
    ./scripts/check_16kb_compatibility.sh -j -o 16kb-report.json
    
- name: Upload Report
  uses: actions/upload-artifact@v3
  with:
    name: compatibility-report
    path: 16kb-report.json
```

## 🔧 Configuration

### Build Configuration (Flutter/Gradle)

**android/gradle.properties**:
```properties
# Required for 16KB page size support
android.bundle.enableMaxPageSizeAlignmentFlag=true

# Optional: Flexible page sizes
android.bundle.enableUncompressedNativeLibs=false
```

**android/app/build.gradle**:
```gradle
android {
    packagingOptions {
        jniLibs {
            useLegacyPackaging = false
        }
    }
    
    defaultConfig {
        ndk {
            // Enable flexible page sizes
            abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'
        }
        externalNativeBuild {
            cmake {
                arguments "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
            }
        }
    }
}
```

## 📊 Output Examples

### Successful AAB Check
```
═══════════════════════════════════════════════════════════════
16 KB PAGE SIZE COMPATIBILITY CHECKER v2.0.0
═══════════════════════════════════════════════════════════════

[INFO] Purpose: Verify Google Play Store 16KB page size requirement
[INFO] Date: 2024-12-04 10:30:45

▶ Checking Prerequisites
[✓] Python3: 3.11.5
[✓] Java: 17.0.8
[✓] Android SDK: /Users/dev/Library/Android/sdk

▶ Analyzing AAB Structure
  📦 AAB Size: 45.2 MB
  📚 Native Libraries: 12
  📋 Modules: 2
  🔧 Bundle Config: ✅ Present

  ✅ 16KB Compatibility: READY
     → Google Play will auto-generate 16KB-aligned APKs

═══════════════════════════════════════════════════════════════
RESULT: ✅ PASSED
═══════════════════════════════════════════════════════════════
```

### Failed APK Check
```
▶ Analyzing APK Alignment

  Total .so files: 8
  ✅ 16KB aligned: 0
  ❌ NOT aligned: 8

  ❌ APK is NOT compatible with 16KB page size
  ⚠️  Recommendation: Use AAB for Google Play Store

  Misaligned libraries:
    • libflutter.so: offset alignment = 4096 bytes
    • libapp.so: offset alignment = 8192 bytes

═══════════════════════════════════════════════════════════════
RESULT: ❌ FAILED
═══════════════════════════════════════════════════════════════
```

## 🐛 Troubleshooting

### Common Issues

**Issue**: "Python3 not found"
```bash
# Install Python 3
# macOS
brew install python3

# Ubuntu/Debian
sudo apt-get install python3

# Windows (WSL)
sudo apt-get install python3
```

**Issue**: "No AAB or APK files found"
```bash
# Build your Flutter app first
flutter build appbundle --release  # For AAB
flutter build apk --release        # For APK
```

**Issue**: "Java not found" (optional warning)
```bash
# Install Java for bundletool validation
# macOS
brew install openjdk@17

# Ubuntu/Debian
sudo apt-get install openjdk-17-jdk
```

### Debug Mode

Enable verbose output to see detailed execution:
```bash
./check_16kb_compatibility.sh -v app-release.aab
```

## 🔒 Security

- No data is sent to external servers (except bundletool download from GitHub)
- All processing is local
- Temporary files are automatically cleaned up
- No API keys or credentials required

## 🎯 Best Practices

### For Flutter Developers

1. **Always use AAB for Play Store uploads**
   ```bash
   flutter build appbundle --release
   ```

2. **Configure gradle.properties correctly**
   ```properties
   android.bundle.enableMaxPageSizeAlignmentFlag=true
   ```

3. **Test on 16KB devices** (or emulators with 16KB page size)

4. **Run checker before every release**
   ```bash
   ./check_16kb_compatibility.sh -v
   ```

### For CI/CD Pipelines

1. **Integrate into build pipeline**
   ```yaml
   - run: ./scripts/check_16kb_compatibility.sh -j
   - run: test $(jq -r '.is_compatible' report.json) = "true"
   ```

2. **Archive reports**
   ```yaml
   - uses: actions/upload-artifact@v3
     with:
       name: 16kb-report
       path: 16kb-report.json
   ```

3. **Fail fast on incompatibility**
   ```bash
   ./check_16kb_compatibility.sh || exit 1
   ```

## 📚 Additional Resources

- [Google Play 16KB Page Size Requirements](https://developer.android.com/guide/practices/page-sizes)
- [Android App Bundle Documentation](https://developer.android.com/guide/app-bundle)
- [Bundletool Documentation](https://developer.android.com/studio/command-line/bundletool)

## 🤝 Contributing

This tool follows enterprise-grade coding standards:
- Comprehensive error handling
- Modular architecture
- Clean separation of concerns
- Extensive documentation
- Type-safe operations

## 📝 License

MIT License - feel free to use and modify for your needs.

## 🔄 Version History

### v2.0.0 (Current)
- Complete refactor with modern Bash practices
- Enhanced error handling and recovery
- JSON output support
- Improved UX with better formatting
- CI/CD integration support
- Modular architecture
- Comprehensive documentation

### v1.0.0
- Initial release
- Basic AAB/APK checking
- Simple terminal output

---

**Made with ❤️ for the Android development community**