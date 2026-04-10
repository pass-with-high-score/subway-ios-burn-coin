# Subway City (Subway Surfers) - Coin Hack

## Thong tin game
- **Bundle ID**: `com.sybogames.subway.surfers.game`
- **Engine**: Unity (IL2CPP backend)
- **Module chinh**: `UnityFramework` (~138MB)
- **Jailbreak**: Dopamine (rootless) + ElleKit

---

## Quy trinh Reverse Engineering bang Frida

### Buoc 1: Xac dinh game engine

```bash
frida-ps -U | grep -i subway
# PID  Name
# 50042  Subway City
```

Hook vao process, enum modules va ObjC classes de xac dinh engine:

```javascript
frida -U -p <PID> -e '
var uf = Process.getModuleByName("UnityFramework");
send({
    name: uf.name,
    base: uf.base.toString(),
    size: uf.size
});

if (ObjC.available) {
    ["UnityAppController", "UnityView", "UnityFramework"].forEach(function(cls) {
        if (ObjC.classes[cls]) {
            console.log("ObjC class found: " + cls);
        }
    });
}
'
```

**Ket qua**: Unity engine, co `UnityFramework` (144MB), ObjC classes: `UnityAppController`, `UnityView`, `UnityFramework`. Su dung IL2CPP backend (symbols bi strip).

---

### Buoc 2: Tim cac ham lien quan den coin bang IL2CPP API

Vi IL2CPP strip het symbol names, khong the dung `enumerateExports()`. Phai dung IL2CPP API de enum metadata:

```javascript
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
            coinClasses.push({image: imgName, class: fullName});
        }

        var iter = Memory.alloc(Process.pointerSize);
        iter.writePointer(ptr(0));
        var method;
        while (!(method = il2cpp.class_get_methods(klass, iter)).isNull()) {
            var methodName = il2cpp.method_get_name(method).readUtf8String();
            if (methodName.toLowerCase().indexOf("coin") !== -1) {
                coinMethods.push({image: imgName, class: fullName, method: methodName});
            }
        }
    }
}

send({coin_classes: coinClasses, coin_methods: coinMethods});
'
```

**Ket qua**: Tim thay 46 classes va 42 methods lien quan den coin trong `SYBO.Subway2.dll`.

#### Coin Classes chinh:
| Class | Mo ta |
|-------|-------|
| `CoinPickupComponent` | Nhat coin |
| `CoinDoublerComponent` | Nhan doi coin |
| `CoinSackPickupComponent` | Nhat tui coin |
| `CoinRewardStrategy` | Chien luoc thuong coin |
| `CoinsPickupSystem` | He thong nhat coin (goi moi frame) |
| `CoinSackProcessSystem` | Xu ly tui coin |

#### Coin Methods chinh:
| Class | Method | Mo ta |
|-------|--------|-------|
| `CoinSackPickupConfig` | `get_CoinWorth` | Gia tri moi coin sack |
| `QuestTriggerContext` | `get_Coins` / `set_Coins` | Get/Set so coin |
| `CoinSackProcessSystem` | `GetExtraCoinsFromPerk` | Coin bonus tu perk |
| `ScreenRunOver` | `UpdateCoinBonusMultiplier` | He so coin bonus cuoi run |
| `TerminalOutcome` | `Coins` | Coin tu mystery box |

---

### Buoc 3: Hook thu cac ham coin (lan 1 - that bai)

Hook `get_CoinWorth`, `set_Coins`, `GetExtraCoinsFromPerk` nhung **khong thay coin tang**. Chi thay:
```
[CoinsPickup] Run called    ← goi lien tuc moi frame
[CoinBonusMultiplier] arg1 = 0x6
```

**Ket luan**: Cac ham coin gameplay (pickup, sack) KHONG di qua `set_Coins` hay `get_CoinWorth`. Can tim ham thuc su add coin vao wallet.

---

### Buoc 4: Tim ham wallet/currency thuc su

Mo rong tim kiem voi keywords: `currency`, `wallet`, `balance`, `reward`, `inventory`, `add`, `grant`, `spend`:

```javascript
// Tim tat ca methods trong cac class co ten chua "currency", "wallet", "inventory"...
// va cac methods co ten "Add", "Grant", "Spend", "Update"...
```

**Ket qua quan trong**: Tim thay he thong currency chinh:

| Class | Method | Params | Mo ta |
|-------|--------|--------|-------|
| `InventoryServiceExtensions` | **`AddCurrency`** | 3 | **Ham chinh cong coin vao wallet** |
| `InventoryService` | `UpdateCurrency` | 1 | Cap nhat wallet |
| `InventoryService` | `SpendCurrency` | 2 | Tru coin khi mua |
| `InventoryServiceExtensions` | `GetCurrency` | 2 | Doc so coin |
| `CurrencyRewardClaimStrategy` | `Claim` | 1 | Nhan reward coin |
| `CurrencyRewardItemClaimStrategy` | `Claim` | 1 | Nhan reward item coin |

---

### Buoc 5: Hook AddCurrency (lan 2 - thanh cong)

```javascript
// File: /tmp/coin_hook_v2.js
var MULTIPLIER = 10;

// ... (setup il2cpp API + findMethods helper) ...

// Hook AddCurrency(IInventoryService, CurrencyType, int amount)
// IL2CPP calling convention: args[0]=service, args[1]=type, args[2]=amount
var addCurrency = findMethods("InventoryServiceExtensions", "AddCurrency");
addCurrency.forEach(function(m) {
    Interceptor.attach(m.fn, {
        onEnter: function(args) {
            var amount = args[2].toInt32();
            if (amount > 0) {
                var modified = amount * MULTIPLIER;
                args[2] = ptr(modified);
                console.log("[AddCurrency] " + amount + " -> " + modified);
            }
        }
    });
});
```

**Ket qua**:
```
[AddCurrency] 10 -> 100        ← THANH CONG! Coin x10
[UpdateCurrency] called         ← Wallet cap nhat
[GetCurrency] returned: 100     ← Doc lai = 100
```

---

### Buoc 6: Tinh offset cho tweak

```javascript
var uf = Process.getModuleByName("UnityFramework");
var base = uf.base;
// offset = runtime_address - module_base (stable across ASLR)
```

| Method | Runtime Address | Offset |
|--------|----------------|--------|
| `AddCurrency` | `0x114ba7f30` | **`0x6A6FF30`** |
| `get_CoinWorth` | `0x114a1c000` | **`0x68E4000`** |
| `CurrencyRewardClaim` | `0x11491ce6c` | **`0x67E4E6C`** |
| `UpdateCurrency` | `0x114ba76ec` | `0x6A6F6EC` |
| `GetCurrency` | `0x114ba81dc` | `0x6A701DC` |
| `SpendCurrency` | `0x114ba7d70` | `0x6A6FD70` |

Offset da verify qua nhieu lan restart game - **tat ca MATCH**.

---

## Tweak Theos

### Cau truc project
```
SubwayCoinHack/
├── Makefile                  # THEOS_PACKAGE_SCHEME = rootless (Dopamine)
├── Tweak.x                   # MSHookFunction tai base + offset
├── SubwayCoinHack.plist      # Filter: com.sybogames.subway.surfers.game
└── control                   # Package metadata
```

### Cach hook trong tweak (khong co symbol, chi co offset)
```objc
// Khi UnityFramework load, tinh address = base + offset, roi hook
static void onImageLoaded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !strstr(info.dli_fname, "UnityFramework")) return;
    uintptr_t base = (uintptr_t)mh;

    MSHookFunction((void *)(base + 0x6A6FF30), (void *)hook_AddCurrency, (void **)&orig_AddCurrency);
    MSHookFunction((void *)(base + 0x68E4000), (void *)hook_GetCoinWorth, (void **)&orig_GetCoinWorth);
}

%ctor { _dyld_register_func_for_add_image(onImageLoaded); }
```

### Build & Install
```bash
make clean && make package

# Copy sang iPhone va install
scp -P 2222 packages/*.deb mobile@localhost:/tmp/
ssh -P 2222 mobile@localhost 'sudo dpkg -i /tmp/com.local.subwaycoinhack*.deb'

# Restart game (khong can respring)
```

---

## Luu y

- **Offset thay doi khi game update** - phai dung Frida chay lai Buoc 2 + 6 de tim offset moi
- **Dopamine rootless**: tweak install vao `/var/jailbreak/usr/lib/TweakInject/`, dung ElleKit (tuong thich MSHookFunction)
- **IL2CPP calling convention**: instance methods co `this` o args[0], static methods khong co. Tat ca methods co them `MethodInfo*` o argument cuoi
- `AddCurrency` la static extension method: `args[0]=service, args[1]=currencyType, args[2]=amount, args[3]=methodInfo`
