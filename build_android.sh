#!/bin/sh
set -e

# --- 1. Environment & Config ---
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH

# Define Output Directory
OUTPUT_DIR="build/android"
mkdir -p $OUTPUT_DIR

ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk}
NDK_HOME=${ANDROID_NDK_HOME:-/opt/android-ndk}
API_VERSION=34
MIN_API_VERSION=23
BUILD_TOOLS_VER=34.0.0

# Paths
BUILD_TOOLS=$ANDROID_HOME/build-tools/$BUILD_TOOLS_VER
TOOLCHAIN=$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
NATIVE_APP_GLUE=$NDK_HOME/sources/android/native_app_glue
ANDROID_JAR=$ANDROID_HOME/platforms/android-$API_VERSION/android.jar
SYSROOT=$TOOLCHAIN/sysroot

# Architectures
ABIS="arm64-v8a" # Add "armeabi-v7a" here if needed

# Flags
FLAGS="-ffunction-sections -funwind-tables -fstack-protector-strong -fPIC -Wall \
	-Wformat -Werror=format-security -no-canonical-prefixes \
	--sysroot=$SYSROOT -DANDROID -DPLATFORM_ANDROID -D__ANDROID_API__=$MIN_API_VERSION"
INCLUDES="-I. -I$NATIVE_APP_GLUE"

# --- 2. Assets & Resources ---
echo "-> Preparing Build Directory..."
# Create build directories
mkdir -p android/build/res/drawable-ldpi android/build/res/drawable-mdpi \
  android/build/res/drawable-hdpi android/build/res/drawable-xhdpi \
  android/build/assets android/build/lib android/build/obj android/build/dex \
  android/build/src/com/raylib/game

# Copy Assets
cp assets/icon_ldpi.png android/build/res/drawable-ldpi/icon.png
cp assets/icon_mdpi.png android/build/res/drawable-mdpi/icon.png
cp assets/icon_hdpi.png android/build/res/drawable-hdpi/icon.png
cp assets/icon_xhdpi.png android/build/res/drawable-xhdpi/icon.png
cp -r assets/* android/build/assets/ || true

# Copy Manifest (Use local if exists, otherwise default)
if [ -f android/AndroidManifest.xml ]; then
  cp android/AndroidManifest.xml android/build/AndroidManifest.xml
fi

# Copy Java Source (Fixing the scaffold issue)
cp android/src/com/raylib/game/NativeLoader.java android/build/src/com/raylib/game/

# --- 3. Compile Native Code ---
for ABI in $ABIS; do
  echo "-> Compiling for $ABI..."
  mkdir -p android/build/lib/$ABI android/build/obj/$ABI

  case "$ABI" in
  "arm64-v8a")
    CCTYPE="aarch64-linux-android"
    LIBPATH="aarch64-linux-android"
    ODIN_TARGET="linux_arm64"
    ABI_FLAGS="-std=c99 -target aarch64 -mfix-cortex-a53-835769"
    ;;
  "armeabi-v7a")
    CCTYPE="armv7a-linux-androideabi"
    LIBPATH="arm-linux-androideabi"
    ODIN_TARGET="linux_arm32"
    ABI_FLAGS="-std=c99 -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
    ;;
  esac

  CC="$TOOLCHAIN/bin/${CCTYPE}${MIN_API_VERSION}-clang"
  ARCH_INCLUDES="-I$SYSROOT/usr/include/$LIBPATH"

  # A. Compile Glue
  $CC -c $NATIVE_APP_GLUE/android_native_app_glue.c -o android/build/obj/$ABI/native_app_glue.o \
    $INCLUDES $ARCH_INCLUDES $FLAGS $ABI_FLAGS

  # B. Build Odin
  echo "   (Odin Build)"
  odin build src -target:$ODIN_TARGET -build-mode:obj -out:android/build/obj/$ABI/game.o \
    -reloc-mode:pic -disable-red-zone -no-entry-point -define:ANDROID=true

  # C. Link
  echo "   (Linking)"
  $CC android/build/obj/$ABI/*.o -o android/build/lib/$ABI/libmain.so -shared \
    -Wl,--exclude-libs,libatomic.a \
    -Wl,--build-id \
    -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now \
    -Wl,--warn-shared-textrel -Wl,--fatal-warnings \
    -Wl,--allow-multiple-definition \
    -Wl,-u,ANativeActivity_onCreate \
    -Wl,--defsym=main=android_entry \
    -L$TOOLCHAIN/sysroot/usr/lib/$LIBPATH/$MIN_API_VERSION \
    -Llib/$ABI \
    -lraylib -llog -landroid -lEGL -lGLESv2 -lOpenSLES -latomic -lc -lm -ldl
done

# --- 4. Build APK ---
echo "-> Packaging APK..."
# Generate R.java
$BUILD_TOOLS/aapt package -f -m -S android/build/res -J android/build/src -M android/build/AndroidManifest.xml -I $ANDROID_JAR

# Compile Java
javac --release 8 -d android/build/obj -classpath $ANDROID_JAR:android/build/obj -sourcepath android/build/src android/build/src/com/raylib/game/R.java android/build/src/com/raylib/game/NativeLoader.java

# Convert to Dex
$BUILD_TOOLS/d8 --output android/build/dex --lib $ANDROID_JAR $(find android/build/obj -name "*.class")

# Package
$BUILD_TOOLS/aapt package -f -M android/build/AndroidManifest.xml -S android/build/res -A assets -I $ANDROID_JAR -F android/build/game-unsigned.apk android/build/dex

echo "-> Adding Native Libraries..."
cd android/build
for ABI in $ABIS; do
  $BUILD_TOOLS/aapt add game-unsigned.apk lib/$ABI/libmain.so
done
cd ../..

echo "-> Signing..."
$BUILD_TOOLS/zipalign -f -p 4 android/build/game-unsigned.apk android/build/game-aligned.apk

if [ ! -f android/debug.keystore ]; then
  echo "Generating Keystore..."
  keytool -genkey -v -keystore android/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

# Output to the main build/ folder
apksigner sign --ks android/debug.keystore --ks-pass pass:android --key-pass pass:android --out $OUTPUT_DIR/game.apk android/build/game-aligned.apk

echo "Build Complete: $OUTPUT_DIR/game.apk"
