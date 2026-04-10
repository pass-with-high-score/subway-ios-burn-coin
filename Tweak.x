#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>

// ============================================================
//  Subway City - Coin Multiplier Tweak with Player Menu
//  Bundle: com.sybogames.subway.surfers.game
// ============================================================

static int g_multiplier = 1;

#define OFF_ADD_CURRENCY     0x6A6FF30
#define OFF_GET_COIN_WORTH   0x68E4000
#define OFF_CURRENCY_CLAIM   0x67E4E6C

// ============================================================
//  Hooks
// ============================================================

static void (*orig_AddCurrency)(void *svc, void *type, int amount, void *mi);
static void hook_AddCurrency(void *svc, void *type, int amount, void *mi) {
    if (amount > 0 && g_multiplier > 1) amount *= g_multiplier;
    orig_AddCurrency(svc, type, amount, mi);
}

static int (*orig_GetCoinWorth)(void *self, void *mi);
static int hook_GetCoinWorth(void *self, void *mi) {
    int val = orig_GetCoinWorth(self, mi);
    if (val > 0 && g_multiplier > 1) val *= g_multiplier;
    return val;
}

static void (*orig_CurrencyClaim)(void *self, void *reward, void *mi);
static void hook_CurrencyClaim(void *self, void *reward, void *mi) {
    orig_CurrencyClaim(self, reward, mi);
}

// ============================================================
//  PlayerMenu
// ============================================================

@interface PlayerMenuView : UIView
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *currentLabel;
@property (nonatomic, assign) BOOL panelOpen;
@property (nonatomic, assign) CGPoint lastCenter;
@end

@implementation PlayerMenuView

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 52, 52)];
    if (!self) return nil;

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleButton.frame = CGRectMake(0, 0, 52, 52);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.75];
    self.toggleButton.layer.cornerRadius = 26;
    self.toggleButton.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.8].CGColor;
    self.toggleButton.layer.borderWidth = 2;
    self.toggleButton.clipsToBounds = YES;
    [self.toggleButton setTitle:@"x1" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.toggleButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.toggleButton];

    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.toggleButton addGestureRecognizer:drag];

    self.panelView = [[UIView alloc] initWithFrame:CGRectMake(0, 58, 200, 0)];
    self.panelView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.95];
    self.panelView.layer.cornerRadius = 16;
    self.panelView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.4].CGColor;
    self.panelView.layer.borderWidth = 1;
    self.panelView.clipsToBounds = YES;
    self.panelView.alpha = 0;
    self.panelView.hidden = YES;
    [self addSubview:self.panelView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 176, 24)];
    self.titleLabel.text = @"Coin Multiplier";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.panelView addSubview:self.titleLabel];

    self.currentLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 32, 176, 18)];
    self.currentLabel.text = @"Current: x1 (OFF)";
    self.currentLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.currentLabel.font = [UIFont systemFontOfSize:12];
    self.currentLabel.textAlignment = NSTextAlignmentCenter;
    [self.panelView addSubview:self.currentLabel];

    NSArray *options = @[@1, @2, @5, @10, @25, @50, @100, @999];
    CGFloat btnW = 86, btnH = 36, padX = 10, padY = 6, startY = 56;

    for (NSInteger i = 0; i < options.count; i++) {
        NSInteger row = i / 2, col = i % 2;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(12 + col * (btnW + padX), startY + row * (btnH + padY), btnW, btnH);
        btn.layer.cornerRadius = 10;
        btn.tag = [options[i] integerValue];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [btn setTitle:([options[i] intValue] == 1 ? @"OFF" : [NSString stringWithFormat:@"x%@", options[i]]) forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        [btn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(multiplierTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.panelView addSubview:btn];
    }

    NSInteger rows = (options.count + 1) / 2;
    self.panelView.frame = CGRectMake(0, 58, 200, startY + rows * (btnH + padY) + 8);
    self.panelOpen = NO;
    return self;
}

- (void)multiplierTapped:(UIButton *)sender {
    g_multiplier = (int)sender.tag;

    NSString *txt = (g_multiplier <= 1) ? @"x1" : [NSString stringWithFormat:@"x%d", g_multiplier];
    [self.toggleButton setTitle:txt forState:UIControlStateNormal];
    self.currentLabel.text = (g_multiplier <= 1)
        ? @"Current: x1 (OFF)"
        : [NSString stringWithFormat:@"Current: x%d", g_multiplier];

    for (UIView *sub in self.panelView.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)sub;
            BOOL active = (b.tag == g_multiplier);
            b.backgroundColor = active
                ? [UIColor colorWithRed:0.0 green:0.65 blue:0.85 alpha:1.0]
                : [UIColor colorWithWhite:0.18 alpha:1.0];
            [b setTitleColor:(active ? [UIColor whiteColor] : [UIColor colorWithWhite:0.75 alpha:1.0])
                    forState:UIControlStateNormal];
        }
    }
    [self togglePanel];
}

- (void)togglePanel {
    self.panelOpen = !self.panelOpen;
    if (self.panelOpen) {
        CGRect sb = [UIScreen mainScreen].bounds;
        CGFloat px = 0, py = 58;
        CGFloat panelW = 200, panelH = self.panelView.frame.size.height;
        if (self.frame.origin.x + panelW > sb.size.width - 10) px = 52 - panelW;
        if (self.frame.origin.y + 58 + panelH > sb.size.height - 40) py = -panelH - 6;
        self.panelView.frame = CGRectMake(px, py, panelW, panelH);
        self.panelView.hidden = NO;
        CGRect f = self.frame;
        f.size = CGSizeMake(MAX(52, px + panelW + 10), MAX(52, py + panelH + 58 + 10));
        self.frame = f;
        [UIView animateWithDuration:0.2 animations:^{ self.panelView.alpha = 1.0; }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{
            self.panelView.alpha = 0;
        } completion:^(BOOL d) {
            self.panelView.hidden = YES;
            CGRect f = self.frame;
            f.size = CGSizeMake(52, 52);
            self.frame = f;
        }];
    }
}

- (void)handleDrag:(UIPanGestureRecognizer *)g {
    if (self.panelOpen) return;
    UIView *w = self.superview;
    CGPoint t = [g translationInView:w];
    if (g.state == UIGestureRecognizerStateBegan) self.lastCenter = self.center;
    CGPoint nc = CGPointMake(self.lastCenter.x + t.x, self.lastCenter.y + t.y);
    CGRect b = w.bounds;
    nc.x = MAX(26, MIN(nc.x, b.size.width - 26));
    nc.y = MAX(60, MIN(nc.y, b.size.height - 26));
    self.center = nc;
    if (g.state == UIGestureRecognizerStateEnded) {
        CGFloat sx = (nc.x < b.size.width / 2) ? 36 : b.size.width - 36;
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            self.center = CGPointMake(sx, nc.y);
        } completion:nil];
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(self.toggleButton.frame, point)) return self.toggleButton;
    if (self.panelOpen && !self.panelView.hidden) {
        CGPoint pp = [self convertPoint:point toView:self.panelView];
        UIView *hit = [self.panelView hitTest:pp withEvent:event];
        if (hit) return hit;
    }
    return nil;
}

@end

// ============================================================
//  Menu injection
// ============================================================

static PlayerMenuView *g_menu = nil;

static void injectMenu(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (g_menu) return;
        UIWindow *window = nil;
        if (@available(iOS 15.0, *)) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *w in ((UIWindowScene *)s).windows) {
                        if (w.isKeyWindow) { window = w; break; }
                    }
                    if (window) break;
                }
            }
        }
        if (!window) window = [UIApplication sharedApplication].keyWindow;
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (window) {
            g_menu = [[PlayerMenuView alloc] init];
            [window addSubview:g_menu];
            NSLog(@"[SubwayCoinHack] PlayerMenu injected");
        }
    });
}

// ============================================================
//  Hook installation
// ============================================================

static void onImageLoaded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    if (!strstr(info.dli_fname, "UnityFramework")) return;

    uintptr_t base = (uintptr_t)mh;
    NSLog(@"[SubwayCoinHack] UnityFramework @ %p", (void *)base);

    MSHookFunction((void *)(base + OFF_ADD_CURRENCY), (void *)hook_AddCurrency, (void **)&orig_AddCurrency);
    MSHookFunction((void *)(base + OFF_GET_COIN_WORTH), (void *)hook_GetCoinWorth, (void **)&orig_GetCoinWorth);
    MSHookFunction((void *)(base + OFF_CURRENCY_CLAIM), (void *)hook_CurrencyClaim, (void **)&orig_CurrencyClaim);

    NSLog(@"[SubwayCoinHack] Hooks installed, loading menu...");
    injectMenu();
}

%ctor {
    _dyld_register_func_for_add_image(onImageLoaded);
}
