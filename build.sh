#!/bin/sh
# ______________________________________________________________________________
#
#  Compile raylib project for Android (Arch Linux / Modern SDK version)
# ______________________________________________________________________________

set -e # Exit immediately if a command exits with a non-zero status

# --- Configuration -----------------------------------------------------------

# Use the environment variables we set up in .zshrc, or fallback to Arch defaults
ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk}
NDK_HOME=${ANDROID_NDK_HOME:-/opt/android-ndk}

# Build Config
API_VERSION=34     # The platform you installed (android-34)
MIN_API_VERSION=23 # Matches your AndroidManifest.xml
BUILD_TOOLS_VER=34.0.0

# Paths to tools
BUILD_TOOLS=$ANDROID_HOME/build-tools/$BUILD_TOOLS_VER
TOOLCHAIN=$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
NATIVE_APP_GLUE=$NDK_HOME/sources/android/native_app_glue
ANDROID_JAR=$ANDROID_HOME/platforms/android-$API_VERSION/android.jar

# ABIs to build
# Removed x86/x86_64 to save build time (most phones are arm64 or armv7)
ABIS="arm64-v8a armeabi-v7a"

# Compiler Flags
FLAGS="-ffunction-sections -funwind-tables -fstack-protector-strong -fPIC -Wall \
	-Wformat -Werror=format-security -no-canonical-prefixes \
	-DANDROID -DPLATFORM_ANDROID -D__ANDROID_API__=$MIN_API_VERSION"

INCLUDES="-I. -Iinclude -I../include -I$NATIVE_APP_GLUE -I$TOOLCHAIN/sysroot/usr/include"

# ______________________________________________________________________________
#
#  1. Prepare Assets
# ______________________________________________________________________________
echo "-> Copying assets..."
mkdir -p android/build/res/drawable-ldpi android/build/res/drawable-mdpi \
  android/build/res/drawable-hdpi android/build/res/drawable-xhdpi \
  android/build/assets android/build/lib android/build/obj android/build/dex

cp assets/icon_ldpi.png android/build/res/drawable-ldpi/icon.png
cp assets/icon_mdpi.png android/build/res/drawable-mdpi/icon.png
cp assets/icon_hdpi.png android/build/res/drawable-hdpi/icon.png
cp assets/icon_xhdpi.png android/build/res/drawable-xhdpi/icon.png
cp -r assets/* android/build/assets/ || true

# ______________________________________________________________________________
#
#  2. Compile Native Code (C/C++)
# ______________________________________________________________________________
for ABI in $ABIS; do
  echo "-> Compiling for $ABI..."

  mkdir -p android/build/lib/$ABI android/build/obj/$ABI

  case "$ABI" in
  "armeabi-v7a")
    CCTYPE="armv7a-linux-androideabi"
    ARCH="arm"
    LIBPATH="arm-linux-androideabi"
    ABI_FLAGS="-std=c99 -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
    ;;
  "arm64-v8a")
    CCTYPE="aarch64-linux-android"
    ARCH="aarch64"
    LIBPATH="aarch64-linux-android"
    ABI_FLAGS="-std=c99 -target aarch64 -mfix-cortex-a53-835769"
    ;;
  esac

  # Use the compiler specific to the Min SDK version
  CC="$TOOLCHAIN/bin/${CCTYPE}${MIN_API_VERSION}-clang"

  # 1. Compile Native App Glue
  $CC -c $NATIVE_APP_GLUE/android_native_app_glue.c -o android/build/obj/$ABI/native_app_glue.o \
    $INCLUDES $FLAGS $ABI_FLAGS

  # 2. Archive Glue into a static library
  $TOOLCHAIN/bin/llvm-ar rcs android/build/lib/$ABI/libnative_app_glue.a android/build/obj/$ABI/native_app_glue.o

  # 3. Compile Project Source
  # Note: Adjust src/*.c if your files are elsewhere
  for file in src/*.c; do
    filename=$(basename "$file")
    $CC -c $file -o android/build/obj/$ABI/"$filename".o \
      $INCLUDES $FLAGS $ABI_FLAGS
  done

  # 4. Link Shared Library (.so)
  # Note: We link against libraylib.a. Make sure you have the Android version of libraylib.a compiled!
  # If you don't have precompiled raylib android libs, you need to compile them first or include raylib source here.
  # Assuming libraylib.a exists in lib/$ABI/

  $TOOLCHAIN/bin/ld.lld android/build/obj/$ABI/*.o -o android/build/lib/$ABI/libmain.so -shared \
    --exclude-libs libatomic.a --build-id \
    -z noexecstack -z relro -z now \
    --warn-shared-textrel --fatal-warnings -u ANativeActivity_onCreate \
    -L$TOOLCHAIN/sysroot/usr/lib/$LIBPATH/$MIN_API_VERSION \
    -L. -Landroid/build/obj/$ABI -Llib/$ABI \
    -lraylib -lnative_app_glue -llog -landroid -lEGL -lGLESv2 -lOpenSLES -latomic -lc -lm -ldl
done

# ______________________________________________________________________________
#
#  3. Build APK (Java/Dex)
# ______________________________________________________________________________
echo "-> Generaring R.java..."
$BUILD_TOOLS/aapt package -f -m \
  -S android/build/res -J android/build/src -M android/build/AndroidManifest.xml \
  -I $ANDROID_JAR

echo "-> Compiling Java..."
# Removed bootclasspath (deprecated/removed in Java 9+)
javac -verbose -source 1.8 -target 1.8 -d android/build/obj \
  -classpath $ANDROID_JAR:android/build/obj \
  -sourcepath src android/build/src/com/raylib/game/R.java \
  android/build/src/com/raylib/game/NativeLoader.java

echo "-> Dexing (d8)..."
# Switched from dx (removed in API 31) to d8
$BUILD_TOOLS/d8 --output android/build/dex \
  --lib $ANDROID_JAR \
  $(find android/build/obj -name "*.class")

echo "-> Packaging APK..."
$BUILD_TOOLS/aapt package -f \
  -M android/build/AndroidManifest.xml -S android/build/res -A assets \
  -I $ANDROID_JAR -F game-unsigned.apk android/build/dex

echo "-> Adding Native Libraries..."
cd android/build
for ABI in $ABIS; do
  ../../$BUILD_TOOLS/aapt add ../../game-unsigned.apk lib/$ABI/libmain.so
done
cd ../..

# ______________________________________________________________________________
#
#  4. Sign and Align
# ______________________________________________________________________________
echo "-> Signing APK..."

# 1. Align
$BUILD_TOOLS/zipalign -f -p 4 game-unsigned.apk game-aligned.apk

# 2. Generate Key (If missing)
if [ ! -f android/debug.keystore ]; then
  echo "Generating debug key..."
  keytool -genkey -v -keystore android/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

# 3. Sign (Using system apksigner)
apksigner sign --ks android/debug.keystore --ks-pass pass:android --key-pass pass:android --out game.apk game-aligned.apk

echo "Build Complete: game.apk"

# Install if device connected
# adb install -r game.apk
