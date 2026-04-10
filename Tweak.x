#import <Foundation/Foundation.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>

// ============================================================
//  Subway City (Subway Surfers) - Coin Multiplier Tweak
//  Bundle: com.sybogames.subway.surfers.game
//  Target: UnityFramework (IL2CPP)
//
//  LƯU Ý: Offset có thể thay đổi khi game update.
//  Dùng Frida để tìm lại offset nếu cần.
// ============================================================

#define COIN_MULTIPLIER 10

// Offsets from UnityFramework base
// InventoryServiceExtensions.AddCurrency(IInventoryService, CurrencyType, int)
#define OFF_ADD_CURRENCY     0x6A6FF30

// CoinSackPickupConfig.get_CoinWorth()
#define OFF_GET_COIN_WORTH   0x68E4000

// CurrencyRewardClaimStrategy.Claim(reward)
#define OFF_CURRENCY_CLAIM   0x67E4E6C

// ============================================================
//  Hook: AddCurrency
//  IL2CPP sig: void AddCurrency(void* service, void* currencyType, int amount, void* methodInfo)
//  Đây là hàm chính cộng coin vào wallet
// ============================================================
static void (*orig_AddCurrency)(void *service, void *currencyType, int amount, void *methodInfo);
static void hook_AddCurrency(void *service, void *currencyType, int amount, void *methodInfo) {
    if (amount > 0) {
        amount *= COIN_MULTIPLIER;
    }
    orig_AddCurrency(service, currencyType, amount, methodInfo);
}

// ============================================================
//  Hook: get_CoinWorth
//  IL2CPP sig: int get_CoinWorth(void* self, void* methodInfo)
//  Giá trị mỗi coin sack pickup
// ============================================================
static int (*orig_GetCoinWorth)(void *self, void *methodInfo);
static int hook_GetCoinWorth(void *self, void *methodInfo) {
    int val = orig_GetCoinWorth(self, methodInfo);
    if (val > 0) {
        val *= COIN_MULTIPLIER;
    }
    return val;
}

// ============================================================
//  Hook: CurrencyRewardClaimStrategy.Claim
//  IL2CPP sig: void Claim(void* self, void* reward, void* methodInfo)
//  Hook reward claim để log (có thể mở rộng)
// ============================================================
static void (*orig_CurrencyClaim)(void *self, void *reward, void *methodInfo);
static void hook_CurrencyClaim(void *self, void *reward, void *methodInfo) {
    NSLog(@"[SubwayCoinHack] CurrencyRewardClaim triggered");
    orig_CurrencyClaim(self, reward, methodInfo);
}

// ============================================================
//  Callback khi image được load - hook khi UnityFramework sẵn sàng
// ============================================================
static void onImageLoaded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    if (!strstr(info.dli_fname, "UnityFramework")) return;

    uintptr_t base = (uintptr_t)mh;
    NSLog(@"[SubwayCoinHack] UnityFramework loaded @ %p, installing hooks (x%d)...", (void *)base, COIN_MULTIPLIER);

    MSHookFunction(
        (void *)(base + OFF_ADD_CURRENCY),
        (void *)hook_AddCurrency,
        (void **)&orig_AddCurrency
    );

    MSHookFunction(
        (void *)(base + OFF_GET_COIN_WORTH),
        (void *)hook_GetCoinWorth,
        (void **)&orig_GetCoinWorth
    );

    MSHookFunction(
        (void *)(base + OFF_CURRENCY_CLAIM),
        (void *)hook_CurrencyClaim,
        (void **)&orig_CurrencyClaim
    );

    NSLog(@"[SubwayCoinHack] All hooks installed! Coin x%d active.", COIN_MULTIPLIER);
}

%ctor {
    _dyld_register_func_for_add_image(onImageLoaded);
}
