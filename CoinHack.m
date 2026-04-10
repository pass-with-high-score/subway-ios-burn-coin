#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>
#import "libs/dobby.h"

// ============================================================
//  Subway City - Coin Multiplier with In-Game Player Menu
//  Standalone dylib (Dobby), inject into IPA
// ============================================================

static int g_multiplier = 1; // default: no multiply (safe start)

// Offsets from UnityFramework base (version 2.1.1)
#define OFF_ADD_CURRENCY     0x6A6FF30
#define OFF_GET_COIN_WORTH   0x68E4000
#define OFF_CURRENCY_CLAIM   0x67E4E6C

// ============================================================
//  Hooks
// ============================================================

static void (*orig_AddCurrency)(void *svc, void *type, int amount, void *mi);
static void hook_AddCurrency(void *svc, void *type, int amount, void *mi) {
    if (amount > 0 && g_multiplier > 1) {
        amount *= g_multiplier;
    }
    orig_AddCurrency(svc, type, amount, mi);
}

static int (*orig_GetCoinWorth)(void *self, void *mi);
static int hook_GetCoinWorth(void *self, void *mi) {
    int val = orig_GetCoinWorth(self, mi);
    if (val > 0 && g_multiplier > 1) {
        val *= g_multiplier;
    }
    return val;
}

static void (*orig_CurrencyClaim)(void *self, void *reward, void *mi);
static void hook_CurrencyClaim(void *self, void *reward, void *mi) {
    orig_CurrencyClaim(self, reward, mi);
}

// ============================================================
//  PlayerMenu - Floating overlay UI
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

    // ---- Toggle button (floating) ----
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

    // Drag gesture on toggle button
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.toggleButton addGestureRecognizer:drag];

    // ---- Panel (hidden by default) ----
    self.panelView = [[UIView alloc] initWithFrame:CGRectMake(0, 58, 200, 0)];
    self.panelView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.95];
    self.panelView.layer.cornerRadius = 16;
    self.panelView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.4].CGColor;
    self.panelView.layer.borderWidth = 1;
    self.panelView.clipsToBounds = YES;
    self.panelView.alpha = 0;
    self.panelView.hidden = YES;
    [self addSubview:self.panelView];

    // Title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 176, 24)];
    self.titleLabel.text = @"Coin Multiplier";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.panelView addSubview:self.titleLabel];

    // Current multiplier label
    self.currentLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 32, 176, 18)];
    self.currentLabel.text = @"Current: x1 (OFF)";
    self.currentLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.currentLabel.font = [UIFont systemFontOfSize:12];
    self.currentLabel.textAlignment = NSTextAlignmentCenter;
    [self.panelView addSubview:self.currentLabel];

    // Multiplier buttons
    NSArray *options = @[@1, @2, @5, @10, @25, @50, @100, @999];
    CGFloat btnW = 86;
    CGFloat btnH = 36;
    CGFloat padX = 10;
    CGFloat padY = 6;
    CGFloat startY = 56;

    for (NSInteger i = 0; i < options.count; i++) {
        NSInteger row = i / 2;
        NSInteger col = i % 2;
        CGFloat x = 12 + col * (btnW + padX);
        CGFloat y = startY + row * (btnH + padY);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(x, y, btnW, btnH);
        btn.layer.cornerRadius = 10;
        btn.tag = [options[i] integerValue];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        NSString *title;
        if ([options[i] intValue] == 1) {
            title = @"OFF";
        } else {
            title = [NSString stringWithFormat:@"x%@", options[i]];
        }
        [btn setTitle:title forState:UIControlStateNormal];

        if ([options[i] intValue] == g_multiplier) {
            btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.65 blue:0.85 alpha:1.0];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
            [btn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1.0] forState:UIControlStateNormal];
        }

        [btn addTarget:self action:@selector(multiplierTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.panelView addSubview:btn];
    }

    NSInteger rows = (options.count + 1) / 2;
    CGFloat panelHeight = startY + rows * (btnH + padY) + 8;
    self.panelView.frame = CGRectMake(0, 58, 200, panelHeight);

    self.panelOpen = NO;
    return self;
}

- (void)multiplierTapped:(UIButton *)sender {
    g_multiplier = (int)sender.tag;

    // Update toggle button text
    if (g_multiplier <= 1) {
        [self.toggleButton setTitle:@"x1" forState:UIControlStateNormal];
        self.currentLabel.text = @"Current: x1 (OFF)";
    } else {
        NSString *txt = [NSString stringWithFormat:@"x%d", g_multiplier];
        [self.toggleButton setTitle:txt forState:UIControlStateNormal];
        self.currentLabel.text = [NSString stringWithFormat:@"Current: x%d", g_multiplier];
    }

    // Update button styles
    for (UIView *sub in self.panelView.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)sub;
            if (btn.tag == g_multiplier) {
                btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.65 blue:0.85 alpha:1.0];
                [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            } else {
                btn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
                [btn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1.0] forState:UIControlStateNormal];
            }
        }
    }

    // Close panel after selection
    [self togglePanel];
}

- (void)togglePanel {
    self.panelOpen = !self.panelOpen;

    if (self.panelOpen) {
        // Reposition panel based on screen position
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat selfX = self.frame.origin.x;
        CGFloat selfY = self.frame.origin.y;
        CGFloat panelW = 200;
        CGFloat panelH = self.panelView.frame.size.height;

        // Default: below toggle
        CGFloat px = 0;
        CGFloat py = 58;

        // If too far right, shift panel left
        if (selfX + panelW > screenBounds.size.width - 10) {
            px = 52 - panelW;
        }
        // If too far down, show above
        if (selfY + 58 + panelH > screenBounds.size.height - 40) {
            py = -panelH - 6;
        }

        self.panelView.frame = CGRectMake(px, py, panelW, panelH);
        self.panelView.hidden = NO;

        // Expand self to contain panel
        CGRect f = self.frame;
        f.size = CGSizeMake(MAX(52, px + panelW + 10), MAX(52, py + panelH + 58 + 10));
        self.frame = f;

        [UIView animateWithDuration:0.2 animations:^{
            self.panelView.alpha = 1.0;
        }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{
            self.panelView.alpha = 0;
        } completion:^(BOOL done) {
            self.panelView.hidden = YES;
            // Shrink self back to toggle size
            CGRect f = self.frame;
            f.size = CGSizeMake(52, 52);
            self.frame = f;
        }];
    }
}

- (void)handleDrag:(UIPanGestureRecognizer *)gesture {
    if (self.panelOpen) return; // don't drag while panel is open

    UIView *window = self.superview;
    CGPoint translation = [gesture translationInView:window];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastCenter = self.center;
    }

    CGPoint newCenter = CGPointMake(
        self.lastCenter.x + translation.x,
        self.lastCenter.y + translation.y
    );

    // Keep within screen bounds
    CGRect bounds = window.bounds;
    newCenter.x = MAX(26, MIN(newCenter.x, bounds.size.width - 26));
    newCenter.y = MAX(60, MIN(newCenter.y, bounds.size.height - 26));

    self.center = newCenter;

    // Snap to edge when released
    if (gesture.state == UIGestureRecognizerStateEnded) {
        CGFloat snapX = (newCenter.x < bounds.size.width / 2) ? 36 : bounds.size.width - 36;
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            self.center = CGPointMake(snapX, newCenter.y);
        } completion:nil];
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Only intercept touches on visible subviews
    if (CGRectContainsPoint(self.toggleButton.frame, point)) {
        return self.toggleButton;
    }
    if (self.panelOpen && !self.panelView.hidden) {
        CGPoint panelPoint = [self convertPoint:point toView:self.panelView];
        UIView *hit = [self.panelView hitTest:panelPoint withEvent:event];
        if (hit) return hit;
    }
    return nil; // pass through to game
}

@end

// ============================================================
//  Menu injection into app window
// ============================================================

static PlayerMenuView *g_menu = nil;

static void injectMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_menu) return;

        // Wait for window to be ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *window = nil;
            if (@available(iOS 15.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        UIWindowScene *ws = (UIWindowScene *)scene;
                        for (UIWindow *w in ws.windows) {
                            if (w.isKeyWindow) { window = w; break; }
                        }
                        if (window) break;
                    }
                }
            }
            if (!window) {
                window = [UIApplication sharedApplication].keyWindow;
            }
            if (!window) {
                window = [UIApplication sharedApplication].windows.firstObject;
            }

            if (window) {
                g_menu = [[PlayerMenuView alloc] init];
                [window addSubview:g_menu];
                NSLog(@"[CoinHack] PlayerMenu injected into window");
            }
        });
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
    NSLog(@"[CoinHack] UnityFramework @ %p", (void *)base);

    DobbyHook((void *)(base + OFF_ADD_CURRENCY),
              (void *)hook_AddCurrency, (void **)&orig_AddCurrency);
    DobbyHook((void *)(base + OFF_GET_COIN_WORTH),
              (void *)hook_GetCoinWorth, (void **)&orig_GetCoinWorth);
    DobbyHook((void *)(base + OFF_CURRENCY_CLAIM),
              (void *)hook_CurrencyClaim, (void **)&orig_CurrencyClaim);

    NSLog(@"[CoinHack] Hooks installed, menu loading...");
    injectMenu();
}

__attribute__((constructor))
static void init(void) {
    NSLog(@"[CoinHack] Loaded");
    _dyld_register_func_for_add_image(onImageLoaded);
}
