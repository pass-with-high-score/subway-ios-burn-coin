var result = {
    engine: "Unknown",
    details: [],
    game_modules: []
};

var modules = Process.enumerateModules();

var engineSignatures = {
    "Unity": ["UnityFramework", "libunity", "libil2cpp", "libmono", "libMonoPosixHelper"],
    "Unreal Engine": ["libUE4", "UE4Game", "libUnreal"],
    "Cocos2d-x": ["libcocos2d", "libcocos2dcpp", "cocos2d"],
    "SpriteKit": ["SpriteKit"],
    "SceneKit": ["SceneKit"],
    "Godot": ["libgodot", "godot_ios"],
    "LayaAir": ["libLayaAir", "laya"],
};

modules.forEach(function(mod) {
    for (var engine in engineSignatures) {
        engineSignatures[engine].forEach(function(sig) {
            if (mod.name.toLowerCase().indexOf(sig.toLowerCase()) !== -1) {
                result.engine = engine;
                result.details.push(engine + " => " + mod.name + " @ " + mod.base + " (size: " + mod.size + ")");
            }
        });
    }
});

modules.forEach(function(mod) {
    var name = mod.name.toLowerCase();
    if (name.indexOf("game") !== -1 || name.indexOf("unity") !== -1 || name.indexOf("il2cpp") !== -1 ||
        name.indexOf("mono") !== -1 || name.indexOf("cocos") !== -1 || name.indexOf("unreal") !== -1 ||
        name.indexOf("metal") !== -1 || name.indexOf("gpu") !== -1 || name.indexOf("opengl") !== -1 ||
        name.indexOf("sprite") !== -1 || name.indexOf("scene") !== -1 || name.indexOf("godot") !== -1 ||
        name.indexOf("libmain") !== -1 || name.indexOf("libnative") !== -1) {
        result.game_modules.push(mod.name + " @ " + mod.base + " (size: " + mod.size + ")");
    }
});

if (ObjC.available) {
    ["UnityAppController", "UnityView", "UnityFramework", "UnityDefaultViewController"].forEach(function(cls) {
        if (ObjC.classes[cls]) {
            result.engine = "Unity";
            result.details.push("ObjC class found: " + cls);
        }
    });
}

send(result);
