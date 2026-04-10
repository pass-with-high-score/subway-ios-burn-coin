/*
 * Subway City - Coin Value Modifier
 * Hook các hàm coin để nhân giá trị lên
 */

var MULTIPLIER = 10; // <== Thay đổi hệ số nhân ở đây

var uf = Process.getModuleByName("UnityFramework");

// ============ IL2CPP API ============
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

// ============ Resolve methods ============
function findMethod(className, methodName) {
    var domain = il2cpp.domain_get();
    var sizePtr = Memory.alloc(4);
    var assemblies = il2cpp.domain_get_assemblies(domain, sizePtr);
    var asmCount = sizePtr.readU32();

    for (var i = 0; i < asmCount; i++) {
        var asm = assemblies.add(i * Process.pointerSize).readPointer();
        var image = il2cpp.assembly_get_image(asm);
        var imgName = il2cpp.image_get_name(image).readUtf8String();
        if (imgName.indexOf("SYBO") === -1) continue;

        var classCount = il2cpp.image_get_class_count(image);
        for (var j = 0; j < classCount; j++) {
            var klass = il2cpp.image_get_class(image, j);
            var cName = il2cpp.class_get_name(klass).readUtf8String();
            if (cName !== className) continue;

            var iter = Memory.alloc(Process.pointerSize);
            iter.writePointer(ptr(0));
            var m;
            while (!(m = il2cpp.class_get_methods(klass, iter)).isNull()) {
                var mName = il2cpp.method_get_name(m).readUtf8String();
                if (mName === methodName) {
                    return m.readPointer(); // function pointer
                }
            }
        }
    }
    return null;
}

var hooks = [
    // ====================================
    // 1. get_CoinWorth - giá trị mỗi coin sack
    //    int get_CoinWorth(this)
    //    Return value x MULTIPLIER
    // ====================================
    {
        cls: "CoinSackPickupConfig",
        method: "get_CoinWorth",
        hook: function(fnPtr) {
            Interceptor.attach(fnPtr, {
                onLeave: function(retval) {
                    var original = retval.toInt32();
                    var modified = original * MULTIPLIER;
                    retval.replace(modified);
                    console.log("[CoinWorth] " + original + " -> " + modified);
                }
            });
        }
    },

    // ====================================
    // 2. get_Coins - đọc số coin hiện tại
    //    int get_Coins(this)
    //    Chỉ log để theo dõi
    // ====================================
    {
        cls: "QuestTriggerContext",
        method: "get_Coins",
        hook: function(fnPtr) {
            Interceptor.attach(fnPtr, {
                onLeave: function(retval) {
                    console.log("[get_Coins] current = " + retval.toInt32());
                }
            });
        }
    },

    // ====================================
    // 3. set_Coins - ghi số coin
    //    void set_Coins(this, int value)
    //    Nhân value lên MULTIPLIER lần
    // ====================================
    {
        cls: "QuestTriggerContext",
        method: "set_Coins",
        hook: function(fnPtr) {
            Interceptor.attach(fnPtr, {
                onEnter: function(args) {
                    var original = args[1].toInt32();
                    var modified = original * MULTIPLIER;
                    args[1] = ptr(modified);
                    console.log("[set_Coins] " + original + " -> " + modified);
                }
            });
        }
    },

    // ====================================
    // 4. GetExtraCoinsFromPerk - coin bonus từ perk
    //    int GetExtraCoinsFromPerk(this, arg1)
    //    Return value x MULTIPLIER
    // ====================================
    {
        cls: "CoinSackProcessSystem",
        method: "GetExtraCoinsFromPerk",
        hook: function(fnPtr) {
            Interceptor.attach(fnPtr, {
                onLeave: function(retval) {
                    var original = retval.toInt32();
                    var modified = original * MULTIPLIER;
                    retval.replace(modified);
                    console.log("[ExtraCoinsFromPerk] " + original + " -> " + modified);
                }
            });
        }
    },

    // ====================================
    // 5. UpdateCoinBonusMultiplier - hệ số bonus cuối run
    //    void UpdateCoinBonusMultiplier(this, float/int multiplier)
    //    Nhân multiplier lên
    // ====================================
    {
        cls: "ScreenRunOver",
        method: "UpdateCoinBonusMultiplier",
        hook: function(fnPtr) {
            Interceptor.attach(fnPtr, {
                onEnter: function(args) {
                    console.log("[CoinBonusMultiplier] arg1 = " + args[1]);
                }
            });
        }
    },

    // ====================================
    // 6. CoinsPickupSystem.Run - hệ thống nhặt coin chính
    //    Theo dõi khi nào coin được nhặt
    // ====================================
    {
        cls: "CoinsPickupSystem",
        method: "Run",
        hook: function(fnPtr) {
            Interceptor.attach(fnPtr, {
                onEnter: function(args) {
                    console.log("[CoinsPickup] Run called");
                }
            });
        }
    },

    // ====================================
    // 7. TerminalOutcome.Coins - coin từ mystery box
    //    Return value x MULTIPLIER
    // ====================================
    {
        cls: "TerminalOutcome",
        method: "Coins",
        hook: function(fnPtr) {
            Interceptor.attach(fnPtr, {
                onLeave: function(retval) {
                    var original = retval.toInt32();
                    if (original > 0) {
                        var modified = original * MULTIPLIER;
                        retval.replace(modified);
                        console.log("[TerminalCoins] " + original + " -> " + modified);
                    }
                }
            });
        }
    },
];

// ============ Install all hooks ============
var installed = 0;
hooks.forEach(function(h) {
    var fnPtr = findMethod(h.cls, h.method);
    if (fnPtr && !fnPtr.isNull()) {
        try {
            h.hook(fnPtr);
            installed++;
            console.log("[+] Hooked " + h.cls + "." + h.method + " @ " + fnPtr);
        } catch(e) {
            console.log("[-] Failed " + h.cls + "." + h.method + ": " + e);
        }
    } else {
        console.log("[-] Not found: " + h.cls + "." + h.method);
    }
});

console.log("\n=== Coin Hook Active ===");
console.log("Multiplier: x" + MULTIPLIER);
console.log("Hooks installed: " + installed + "/" + hooks.length);
console.log("Choi game di! Coin se duoc nhan x" + MULTIPLIER);
console.log("========================\n");
