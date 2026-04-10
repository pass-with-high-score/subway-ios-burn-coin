/*
 * Subway City - Coin Hook v2
 * Target: InventoryService.AddCurrency / UpdateCurrency / CurrencyRewardClaimStrategy.Claim
 */

var MULTIPLIER = 10; // <=== Thay đổi hệ số nhân ở đây

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

function findMethods(className, methodName) {
    var domain = il2cpp.domain_get();
    var sizePtr = Memory.alloc(4);
    var assemblies = il2cpp.domain_get_assemblies(domain, sizePtr);
    var asmCount = sizePtr.readU32();
    var results = [];
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
                    var fnPtr = m.readPointer();
                    var params = il2cpp.method_get_param_count(m);
                    results.push({fn: fnPtr, params: params, methodInfo: m});
                }
            }
        }
    }
    return results;
}

var installed = 0;

// ============================================================
// 1. Hook AddCurrency(IInventoryService, CurrencyType, int amount)
//    static method: args[0]=service, args[1]=type, args[2]=amount
// ============================================================
var addCurrency = findMethods("InventoryServiceExtensions", "AddCurrency");
addCurrency.forEach(function(m) {
    if (m.fn.isNull()) return;
    Interceptor.attach(m.fn, {
        onEnter: function(args) {
            // args: this/service, currencyType, amount, methodInfo
            // For static extension method: args[0]=service, args[1]=type, args[2]=amount
            var amount = args[2].toInt32();
            if (amount > 0) {
                var modified = amount * MULTIPLIER;
                args[2] = ptr(modified);
                console.log("[AddCurrency] " + amount + " -> " + modified);
            }
        }
    });
    installed++;
    console.log("[+] Hooked InventoryServiceExtensions.AddCurrency @ " + m.fn + " (params:" + m.params + ")");
});

// ============================================================
// 2. Hook CurrencyRewardClaimStrategy.Claim(reward)
//    This is called when claiming currency rewards
// ============================================================
var currClaim = findMethods("CurrencyRewardClaimStrategy", "Claim");
currClaim.forEach(function(m) {
    if (m.fn.isNull()) return;
    Interceptor.attach(m.fn, {
        onEnter: function(args) {
            console.log("[CurrencyRewardClaim] Claim called, reward obj @ " + args[1]);
        }
    });
    installed++;
    console.log("[+] Hooked CurrencyRewardClaimStrategy.Claim @ " + m.fn);
});

// ============================================================
// 3. Hook CurrencyRewardItemClaimStrategy.Claim(reward)
// ============================================================
var currItemClaim = findMethods("CurrencyRewardItemClaimStrategy", "Claim");
currItemClaim.forEach(function(m) {
    if (m.fn.isNull()) return;
    Interceptor.attach(m.fn, {
        onEnter: function(args) {
            console.log("[CurrencyItemClaim] Claim called, reward obj @ " + args[1]);
        }
    });
    installed++;
    console.log("[+] Hooked CurrencyRewardItemClaimStrategy.Claim @ " + m.fn);
});

// ============================================================
// 4. Hook UpdateCurrency(currency) - updates wallet
// ============================================================
var updateCurrency = findMethods("InventoryService", "UpdateCurrency");
updateCurrency.forEach(function(m) {
    if (m.fn.isNull()) return;
    Interceptor.attach(m.fn, {
        onEnter: function(args) {
            console.log("[UpdateCurrency] called, currency obj @ " + args[1]);
        }
    });
    installed++;
    console.log("[+] Hooked InventoryService.UpdateCurrency @ " + m.fn);
});

// ============================================================
// 5. Hook GetCurrency - monitor reads
// ============================================================
var getCurrency = findMethods("InventoryServiceExtensions", "GetCurrency");
getCurrency.forEach(function(m) {
    if (m.fn.isNull()) return;
    Interceptor.attach(m.fn, {
        onLeave: function(retval) {
            console.log("[GetCurrency] returned: " + retval.toInt32());
        }
    });
    installed++;
    console.log("[+] Hooked InventoryServiceExtensions.GetCurrency @ " + m.fn);
});

// ============================================================
// 6. Hook SpendCurrency - log spending
// ============================================================
var spendCurrency = findMethods("InventoryService", "SpendCurrency");
spendCurrency.forEach(function(m) {
    if (m.fn.isNull()) return;
    Interceptor.attach(m.fn, {
        onEnter: function(args) {
            console.log("[SpendCurrency] type=" + args[1] + " amount=" + args[2].toInt32());
        }
    });
    installed++;
    console.log("[+] Hooked InventoryService.SpendCurrency @ " + m.fn);
});

console.log("\n========== Coin Hook v2 Active ==========");
console.log("Multiplier: x" + MULTIPLIER);
console.log("Hooks installed: " + installed);
console.log("Target: AddCurrency (nhan coin x" + MULTIPLIER + ")");
console.log("Choi game va nhat coin / nhan reward!");
console.log("==========================================\n");
