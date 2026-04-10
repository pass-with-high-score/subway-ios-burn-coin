#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>
#import "libs/dobby.h"

// ============================================================
//  Subway City - Coin Multiplier (Standalone dylib, no jailbreak)
//  Inject vào IPA, dùng Dobby thay Substrate
// ============================================================

#define COIN_MULTIPLIER 10

// Offsets from UnityFramework base (version 2.1.1)
#define OFF_ADD_CURRENCY     0x6A6FF30
#define OFF_GET_COIN_WORTH   0x68E4000
#define OFF_CURRENCY_CLAIM   0x67E4E6C

// ============================================================
//  Hook: AddCurrency(service, currencyType, amount, methodInfo)
// ============================================================
static void (*orig_AddCurrency)(void *service, void *currencyType, int amount, void *methodInfo);
static void hook_AddCurrency(void *service, void *currencyType, int amount, void *methodInfo) {
    if (amount > 0) {
        amount *= COIN_MULTIPLIER;
    }
    orig_AddCurrency(service, currencyType, amount, methodInfo);
}

// ============================================================
//  Hook: get_CoinWorth(self, methodInfo)
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
//  Hook: CurrencyRewardClaimStrategy.Claim(self, reward, methodInfo)
// ============================================================
static void (*orig_CurrencyClaim)(void *self, void *reward, void *methodInfo);
static void hook_CurrencyClaim(void *self, void *reward, void *methodInfo) {
    NSLog(@"[CoinHack] CurrencyRewardClaim triggered");
    orig_CurrencyClaim(self, reward, methodInfo);
}

// ============================================================
//  Callback khi UnityFramework load
// ============================================================
static void onImageLoaded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    if (!strstr(info.dli_fname, "UnityFramework")) return;

    uintptr_t base = (uintptr_t)mh;
    NSLog(@"[CoinHack] UnityFramework @ %p, hooking (x%d)...", (void *)base, COIN_MULTIPLIER);

    DobbyHook(
        (void *)(base + OFF_ADD_CURRENCY),
        (void *)hook_AddCurrency,
        (void **)&orig_AddCurrency
    );

    DobbyHook(
        (void *)(base + OFF_GET_COIN_WORTH),
        (void *)hook_GetCoinWorth,
        (void **)&orig_GetCoinWorth
    );

    DobbyHook(
        (void *)(base + OFF_CURRENCY_CLAIM),
        (void *)hook_CurrencyClaim,
        (void **)&orig_CurrencyClaim
    );

    NSLog(@"[CoinHack] All hooks installed! Coin x%d", COIN_MULTIPLIER);
}

// ============================================================
//  Constructor - auto run khi dylib load
// ============================================================
__attribute__((constructor))
static void init(void) {
    NSLog(@"[CoinHack] Loaded! Registering image callback...");
    _dyld_register_func_for_add_image(onImageLoaded);
}
