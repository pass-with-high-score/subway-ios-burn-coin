# Subway City - Coin Hack

Reverse engineering Subway City (Subway Surfers) using Frida + IL2CPP API to find and hook coin functions, then package as both a jailbreak tweak (Theos) and a standalone IPA injection (Dobby).

## Game Info

| Key | Value |
|-----|-------|
| App Name | Subway City (Subway Surfers) |
| Bundle ID | `com.sybogames.subway.surfers.game` |
| Engine | Unity (IL2CPP backend) |
| Main Module | `UnityFramework` (~138MB) |
| Game Version | 2.1.1 |
| Assembly | `SYBO.Subway2.dll` |

## Project Structure

```
SubwayCoinHack/
├── README.md
│
├── # --- Frida Scripts ---
├── detect_engine.js          # Step 1: Detect game engine
├── coin_hook.js              # Step 3: First coin hook attempt (failed)
├── coin_hook_v2.js           # Step 5: Working coin hook (AddCurrency x10)
│
├── # --- Theos Tweak (jailbreak) ---
├── Makefile                  # THEOS_PACKAGE_SCHEME = rootless (Dopamine)
├── Tweak.x                   # MSHookFunction at base + offset
├── SubwayCoinHack.plist      # Bundle filter
├── control                   # Debian package metadata
├── packages/                 # Built .deb files
│
├── # --- Standalone IPA Injection (no jailbreak) ---
├── CoinHack.m                # Dobby-based dylib source
├── libs/
│   ├── libdobby.a            # Dobby static library (iOS arm64)
│   └── dobby.h               # Dobby header
├── build_inject.sh           # Build dylib + inject into IPA
├── ipa/                      # Dumped original IPA
├── inject/                   # Extracted app + built dylib
└── SubwayCity-CoinHack.ipa   # Final modded IPA
```

---

## Step-by-Step Frida Guide

### Prerequisites

```bash
# Mac
pip3 install frida-tools
npm install -g bagbak          # for IPA dumping

# iPhone (jailbroken)
# Install frida-server from Cydia/Sileo
```

---

### Step 1: List Processes & Detect Engine

Find the game process:

```bash
frida-ps -U | grep -i subway
# PID    Name
# 50042  Subway City
```

Detect what engine the game uses by checking loaded modules and ObjC classes:

```bash
frida -U -p <PID> -e '
var result = { engine: "Unknown", details: [], modules: [] };
var modules = Process.enumerateModules();

var sigs = {
    "Unity": ["UnityFramework", "libil2cpp", "libmono"],
    "Unreal": ["libUE4", "UE4Game"],
    "Cocos2d": ["libcocos2d", "cocos2d"],
    "SpriteKit": ["SpriteKit"],
    "SceneKit": ["SceneKit"],
    "Godot": ["libgodot"]
};

modules.forEach(function(m) {
    for (var e in sigs) {
        sigs[e].forEach(function(s) {
            if (m.name.toLowerCase().indexOf(s.toLowerCase()) !== -1) {
                result.engine = e;
                result.details.push(e + " => " + m.name + " @ " + m.base + " sz:" + m.size);
            }
        });
    }
});

if (ObjC.available) {
    ["UnityAppController", "UnityView", "UnityFramework"].forEach(function(cls) {
        if (ObjC.classes[cls]) {
            result.engine = "Unity";
            result.details.push("ObjC: " + cls);
        }
    });
}

send(result);
' --no-auto-reload
```

**Result**: Unity engine with IL2CPP backend. `UnityFramework` module at ~144MB. ObjC bridge classes `UnityAppController`, `UnityView`, `UnityFramework` all present.

**Key insight**: IL2CPP strips all C# symbol names from the binary. You cannot use `enumerateExports()` to find game methods. Must use the IL2CPP C API which is exported by UnityFramework.

---

### Step 2: Search for Coin Functions via IL2CPP API

IL2CPP exports a C API that lets you enumerate all classes and methods by name at runtime. This is the core technique for reversing any Unity IL2CPP game.

#### IL2CPP API Functions Used

| Function | Purpose |
|----------|---------|
| `il2cpp_domain_get()` | Get the IL2CPP domain |
| `il2cpp_domain_get_assemblies()` | List all loaded assemblies (.dll) |
| `il2cpp_assembly_get_image()` | Get image from assembly |
| `il2cpp_image_get_class_count()` | Number of classes in image |
| `il2cpp_image_get_class()` | Get class by index |
| `il2cpp_class_get_name()` | Get class name string |
| `il2cpp_class_get_methods()` | Iterate methods of a class |
| `il2cpp_method_get_name()` | Get method name string |
| `MethodInfo->methodPointer` | First field of MethodInfo = native function pointer |

#### Script: Enumerate all coin-related classes and methods

```bash
frida -U -p <PID> -e '
var uf = Process.getModuleByName("UnityFramework");
var il2cpp = {
    domain_get: new NativeFunction(uf.getExportByName("il2cpp_domain_get"), "pointer", []),
    domain_get_assemblies: new NativeFunction(uf.getExportByName("il2cpp_domain_get_assemblies"), "pointer", ["pointer", "pointer"]),
    assembly_get_image: new NativeFunction(uf.getExportByName("il2cpp_assembly_get_image"), "pointer", ["pointer"]),
    image_get_class_count: new NativeFunction(uf.getExportByName("il2cpp_image_get_class_count"), "uint32", ["pointer"]),
    image_get_class: new NativeFunction(uf.getExportByName("il2cpp_image_get_class"), "pointer", ["pointer", "uint32"]),
    class_get_name: new NativeFunction(uf.getExportByName("il2cpp_class_get_name"), "pointer", ["pointer"]),
    class_get_namespace: new NativeFunction(uf.getExportByName("il2cpp_class_get_namespace"), "pointer", ["pointer"]),
    class_get_methods: new NativeFunction(uf.getExportByName("il2cpp_class_get_methods"), "pointer", ["pointer", "pointer"]),
    method_get_name: new NativeFunction(uf.getExportByName("il2cpp_method_get_name"), "pointer", ["pointer"]),
    method_get_param_count: new NativeFunction(uf.getExportByName("il2cpp_method_get_param_count"), "uint32", ["pointer"]),
    image_get_name: new NativeFunction(uf.getExportByName("il2cpp_image_get_name"), "pointer", ["pointer"]),
};

var domain = il2cpp.domain_get();
var sizePtr = Memory.alloc(4);
var assemblies = il2cpp.domain_get_assemblies(domain, sizePtr);
var asmCount = sizePtr.readU32();

var coinClasses = [];
var coinMethods = [];

for (var i = 0; i < asmCount; i++) {
    var asm = assemblies.add(i * Process.pointerSize).readPointer();
    var image = il2cpp.assembly_get_image(asm);
    var imgName = il2cpp.image_get_name(image).readUtf8String();
    if (imgName.indexOf("SYBO") === -1) continue;

    var classCount = il2cpp.image_get_class_count(image);
    for (var j = 0; j < classCount; j++) {
        var klass = il2cpp.image_get_class(image, j);
        var className = il2cpp.class_get_name(klass).readUtf8String();
        var ns = il2cpp.class_get_namespace(klass).readUtf8String();
        var fullName = ns ? ns + "." + className : className;

        if (className.toLowerCase().indexOf("coin") !== -1) {
            coinClasses.push({ image: imgName, class: fullName });
        }

        var iter = Memory.alloc(Process.pointerSize);
        iter.writePointer(ptr(0));
        var method;
        while (!(method = il2cpp.class_get_methods(klass, iter)).isNull()) {
            var methodName = il2cpp.method_get_name(method).readUtf8String();
            if (methodName.toLowerCase().indexOf("coin") !== -1) {
                coinMethods.push({ image: imgName, class: fullName, method: methodName });
            }
        }
    }
}

send({ coin_classes: coinClasses, coin_methods: coinMethods });
' --no-auto-reload
```

**Result**: 46 classes and 42 methods containing "coin" in `SYBO.Subway2.dll`.

#### Coin Classes Found

| Class | Description |
|-------|-------------|
| `CoinPickupComponent` | Individual coin pickup |
| `CoinDoublerComponent` | Coin doubler powerup |
| `CoinSackPickupComponent` | Coin sack pickup |
| `CoinSackProcessSystem` | Coin sack processing logic |
| `CoinsPickupSystem` | Main coin pickup system (called every frame) |
| `CoinRewardStrategy` | Coin reward strategy |
| `CoinPurchaseProductsProvider` | IAP coin products |

#### Coin Methods Found

| Class | Method |
|-------|--------|
| `CoinSackPickupConfig` | `get_CoinWorth` |
| `QuestTriggerContext` | `get_Coins` / `set_Coins` |
| `CoinSackProcessSystem` | `GetExtraCoinsFromPerk`, `ActivateCoinSack` |
| `ScreenRunOver` | `UpdateCoinBonusMultiplier` |
| `TerminalOutcome` | `Coins` |

---

### Step 3: First Hook Attempt (FAILED)

Hooked `get_CoinWorth`, `set_Coins`, `GetExtraCoinsFromPerk` with `Interceptor.attach` to multiply return values.

**Result**: Only `CoinsPickupSystem.Run` fired (every frame) and `UpdateCoinBonusMultiplier` at end of run. The coin value hooks **never triggered**.

```
[CoinsPickup] Run called    <- fires every frame
[CoinsPickup] Run called
[CoinBonusMultiplier] arg1 = 0x6   <- only at end of run
```

**Lesson learned**: The obvious "coin" functions are not the actual code path that adds coins to the player wallet. The real currency system uses a separate inventory/wallet service.

---

### Step 4: Find the Real Currency System

Broadened the search to include keywords: `currency`, `wallet`, `balance`, `inventory`, `reward`, `add`, `grant`, `spend`.

```bash
# Search all classes/methods matching currency/wallet/inventory patterns
# Filter for methods named Add*, Set*, Grant*, Spend*, Update*, Claim*
```

**Found the real currency system in `SYBO.Subway2.Inventory`**:

| Class | Method | Params | Role |
|-------|--------|--------|------|
| **`InventoryServiceExtensions`** | **`AddCurrency`** | 3 | **THE function that adds coins to wallet** |
| `InventoryService` | `UpdateCurrency` | 1 | Persists wallet update |
| `InventoryService` | `SpendCurrency` | 2 | Deducts coins on purchase |
| `InventoryServiceExtensions` | `GetCurrency` | 2 | Reads current coin count |
| `CurrencyRewardClaimStrategy` | `Claim` | 1 | Claims currency rewards |
| `CurrencyRewardItemClaimStrategy` | `Claim` | 1 | Claims currency item rewards |

---

### Step 5: Hook AddCurrency (SUCCESS)

Full working script: `coin_hook_v2.js`

```bash
frida -U -p <PID> -l coin_hook_v2.js
```

The script:
1. Uses IL2CPP API to resolve `InventoryServiceExtensions.AddCurrency` method
2. Reads the native function pointer from `MethodInfo->methodPointer` (first field)
3. Hooks with `Interceptor.attach`, multiplies `args[2]` (amount) by 10

**IL2CPP calling convention for static extension methods**:
```
AddCurrency(IInventoryService service, CurrencyType type, int amount)
  -> Native: void fn(void* service, void* type, int amount, MethodInfo* method)
  -> args[0] = service, args[1] = currencyType, args[2] = amount, args[3] = methodInfo
```

**Result**:
```
[+] Hooked InventoryServiceExtensions.AddCurrency @ 0x114ba7f30
[+] Hooked InventoryService.UpdateCurrency @ 0x114ba76ec
[+] Hooked InventoryServiceExtensions.GetCurrency @ 0x114ba81dc
[+] Hooked InventoryService.SpendCurrency @ 0x114ba7d70

[AddCurrency] 10 -> 100         <- WORKING! 10 coins became 100
[UpdateCurrency] called          <- wallet persisted
[GetCurrency] returned: 100      <- confirmed x10
```

---

### Step 6: Calculate Offsets for Binary Patching

For a permanent tweak/dylib, we need offsets that are stable across ASLR randomization.

```
offset = runtime_function_address - runtime_module_base
```

```bash
frida -U -p <PID> -e '
var uf = Process.getModuleByName("UnityFramework");
var base = uf.base;

// ... resolve methods using il2cpp API ...

// For each method:
var offset = fnPtr.sub(base);
console.log("offset = 0x" + offset.toString(16));
' --no-auto-reload
```

**Offsets (game version 2.1.1)**:

| Method | Offset | Verified |
|--------|--------|----------|
| `AddCurrency` | `0x6A6FF30` | MATCH across restarts |
| `get_CoinWorth` | `0x68E4000` | MATCH |
| `CurrencyRewardClaim` | `0x67E4E6C` | MATCH |
| `UpdateCurrency` | `0x6A6F6EC` | MATCH |
| `GetCurrency` | `0x6A701DC` | MATCH |
| `SpendCurrency` | `0x6A6FD70` | MATCH |

**WARNING**: Offsets change when the game updates. Re-run Step 2 + 6 to find new offsets.

---

## Method A: Theos Tweak (Jailbreak)

Uses `MSHookFunction` (Substrate/ElleKit) to hook at `base + offset`.

### Key Code (Tweak.x)

```objc
#import <substrate.h>
#import <mach-o/dyld.h>

#define COIN_MULTIPLIER 10
#define OFF_ADD_CURRENCY 0x6A6FF30

static void (*orig_AddCurrency)(void *, void *, int, void *);
static void hook_AddCurrency(void *svc, void *type, int amount, void *mi) {
    if (amount > 0) amount *= COIN_MULTIPLIER;
    orig_AddCurrency(svc, type, amount, mi);
}

static void onImageLoaded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !strstr(info.dli_fname, "UnityFramework")) return;
    uintptr_t base = (uintptr_t)mh;
    MSHookFunction((void *)(base + OFF_ADD_CURRENCY),
                   (void *)hook_AddCurrency, (void **)&orig_AddCurrency);
}

%ctor { _dyld_register_func_for_add_image(onImageLoaded); }
```

### Build

```bash
# Makefile must have: THEOS_PACKAGE_SCHEME = rootless  (for Dopamine)
make clean && make package
# Output: packages/com.local.subwaycoinhack_*.deb
```

### Install

```bash
# Via SSH (iproxy 2222 22 for USB)
scp -P 2222 packages/*.deb mobile@localhost:/tmp/
ssh -P 2222 mobile@localhost 'sudo dpkg -i /tmp/com.local.subwaycoinhack*.deb'
# Kill and reopen the game
```

### Troubleshooting

Check if tweak is loaded:
```bash
frida -U -p <PID> -e '
var found = false;
Process.enumerateModules().forEach(function(m) {
    if (m.name.indexOf("SubwayCoinHack") !== -1) {
        found = true;
        console.log("LOADED: " + m.path);
    }
});
if (!found) console.log("NOT LOADED");
' --no-auto-reload
```

Dopamine rootless tweak path:
```
/private/preboot/.../dopamine-.../procursus/usr/lib/TweakInject/
```

---

## Method B: IPA Injection (No Jailbreak)

Injects a standalone dylib into the decrypted IPA. Uses **Dobby** instead of Substrate for hooking (no jailbreak dependency).

### 1. Dump Decrypted IPA

```bash
# Requires frida-server on jailbroken device
npm install -g bagbak
bagbak -U -o ./ipa com.sybogames.subway.surfers.game
# Output: ipa/com.sybogames.subway.surfers.game-2.1.1.ipa
```

### 2. Build Dobby (iOS arm64)

```bash
git clone https://github.com/jmpews/Dobby.git /tmp/Dobby
cd /tmp/Dobby && mkdir build_ios && cd build_ios
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_SYSTEM_PROCESSOR=arm64
make -j$(sysctl -n hw.ncpu)
# Output: libdobby.a
```

### 3. Compile CoinHack.dylib

See `CoinHack.m` - same hook logic but uses `DobbyHook()` instead of `MSHookFunction()`:

```objc
DobbyHook(
    (void *)(base + OFF_ADD_CURRENCY),
    (void *)hook_AddCurrency,
    (void **)&orig_AddCurrency
);
```

```bash
xcrun -sdk iphoneos clang \
    -arch arm64 -shared \
    -framework Foundation \
    -miphoneos-version-min=15.0 \
    -o CoinHack.dylib \
    CoinHack.m libs/libdobby.a \
    -I libs -lstdc++
```

### 4. Inject into IPA

```bash
# Extract IPA
unzip game.ipa -d extracted/

# Copy dylib into app bundle
cp CoinHack.dylib extracted/Payload/SubwayCity.app/Frameworks/

# Add LC_LOAD_DYLIB to main binary
insert_dylib --strip-codesig --inplace \
    "@executable_path/Frameworks/CoinHack.dylib" \
    extracted/Payload/SubwayCity.app/SubwayCity

# Remove old signatures
find extracted/Payload -name "_CodeSignature" -exec rm -rf {} +
rm -f extracted/Payload/SubwayCity.app/embedded.mobileprovision

# Repackage
cd extracted && zip -r ../SubwayCity-CoinHack.ipa Payload/
```

Or use the all-in-one script:
```bash
bash build_inject.sh
```

### 5. Sign & Install

| Method | Command |
|--------|---------|
| **TrollStore** | Copy IPA to device, open with TrollStore (no signing needed) |
| **Sideloadly** | Drag IPA into Sideloadly app |
| **AltStore** | Import IPA into AltStore |
| **zsign** | `zsign -k cert.p12 -p pass -m profile.mobileprovision -o signed.ipa SubwayCity-CoinHack.ipa` |

---

## Updating Offsets After Game Update

When the game updates, offsets will change. Re-run these steps:

```bash
# 1. Open updated game on device
# 2. Find PID
frida-ps -U | grep -i subway

# 3. Run offset finder
frida -U -p <PID> -e '
var uf = Process.getModuleByName("UnityFramework");
var il2cpp = {
    domain_get: new NativeFunction(uf.getExportByName("il2cpp_domain_get"), "pointer", []),
    domain_get_assemblies: new NativeFunction(uf.getExportByName("il2cpp_domain_get_assemblies"), "pointer", ["pointer", "pointer"]),
    assembly_get_image: new NativeFunction(uf.getExportByName("il2cpp_assembly_get_image"), "pointer", ["pointer"]),
    image_get_class_count: new NativeFunction(uf.getExportByName("il2cpp_image_get_class_count"), "uint32", ["pointer"]),
    image_get_class: new NativeFunction(uf.getExportByName("il2cpp_image_get_class"), "pointer", ["pointer", "uint32"]),
    class_get_name: new NativeFunction(uf.getExportByName("il2cpp_class_get_name"), "pointer", ["pointer"]),
    class_get_methods: new NativeFunction(uf.getExportByName("il2cpp_class_get_methods"), "pointer", ["pointer", "pointer"]),
    method_get_name: new NativeFunction(uf.getExportByName("il2cpp_method_get_name"), "pointer", ["pointer"]),
    image_get_name: new NativeFunction(uf.getExportByName("il2cpp_image_get_name"), "pointer", ["pointer"]),
};

function findMethod(cls, method) {
    var domain = il2cpp.domain_get();
    var sizePtr = Memory.alloc(4);
    var asms = il2cpp.domain_get_assemblies(domain, sizePtr);
    var cnt = sizePtr.readU32();
    for (var i = 0; i < cnt; i++) {
        var a = asms.add(i * Process.pointerSize).readPointer();
        var img = il2cpp.assembly_get_image(a);
        var imgName = il2cpp.image_get_name(img).readUtf8String();
        if (imgName.indexOf("SYBO") === -1) continue;
        var cc = il2cpp.image_get_class_count(img);
        for (var j = 0; j < cc; j++) {
            var k = il2cpp.image_get_class(img, j);
            if (il2cpp.class_get_name(k).readUtf8String() !== cls) continue;
            var iter = Memory.alloc(Process.pointerSize);
            iter.writePointer(ptr(0));
            var m;
            while (!(m = il2cpp.class_get_methods(k, iter)).isNull()) {
                if (il2cpp.method_get_name(m).readUtf8String() === method)
                    return m.readPointer();
            }
        }
    }
    return null;
}

var base = uf.base;
var targets = [
    ["InventoryServiceExtensions", "AddCurrency"],
    ["CoinSackPickupConfig", "get_CoinWorth"],
    ["CurrencyRewardClaimStrategy", "Claim"],
];

targets.forEach(function(t) {
    var fn = findMethod(t[0], t[1]);
    if (fn) {
        console.log(t[0] + "." + t[1] + " offset = 0x" + fn.sub(base).toString(16));
    }
});
' --no-auto-reload

# 4. Update offsets in Tweak.x / CoinHack.m
# 5. Rebuild
```

---

## Technical Notes

### IL2CPP Calling Convention (arm64)

```
Instance method:  ReturnType Method(void* this, args..., MethodInfo* method)
Static method:    ReturnType Method(args..., MethodInfo* method)
Extension method: ReturnType Method(void* thisArg, args..., MethodInfo* method)
```

`AddCurrency` is a static extension method on `IInventoryService`:
```
C#:     static void AddCurrency(this IInventoryService svc, CurrencyType type, int amount)
Native: void AddCurrency(void* svc, void* type, int amount, MethodInfo* mi)
                          x0          x1          w2          x3
```

### How MethodInfo->functionPointer works

In IL2CPP, `il2cpp_class_get_methods()` returns a `MethodInfo*`. The **first field** of this struct is the native function pointer:

```c
struct MethodInfo {
    void* methodPointer;    // <-- this is what we read with m.readPointer()
    // ... other fields
};
```

### MSHookFunction vs DobbyHook

| | MSHookFunction (Substrate) | DobbyHook (Dobby) |
|---|---|---|
| Requires JB | Yes (Substrate/ElleKit) | No (standalone) |
| Usage | `MSHookFunction(target, hook, &orig)` | `DobbyHook(target, hook, &orig)` |
| Library | `libsubstrate.dylib` (on device) | `libdobby.a` (linked statically) |
| Use case | Theos tweak (.deb) | IPA injection |
