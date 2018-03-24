#import "Headers.h"
#import "DDNotificationToolsManager.h"

#define kStatusBarSettingsChanged @"DynasticDevelopmentiNDTStatusBarSettingsChangedNotificationName"

static NSDate *getOverrideDate() {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    
    NSDateComponents *components = [[NSCalendar currentCalendar] components: NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    components.hour = 9;
    components.minute = 41;
    
    return [[NSCalendar currentCalendar] dateFromComponents:components];
}

static DDNotificationToolsManager *manager;
static NSMutableArray *notificationRequests = [NSMutableArray array];

static BOOL spoofsCarrier = NO;
static BOOL spoofsTime = NO;
static NSString *carrierName = @"";

@interface NotificationToolsManagerDelegate: NSObject <DDNotificationToolsManagerDelegate>
@end

@implementation NotificationToolsManagerDelegate

- (void)receivedNotifications:(NSArray *)notifications {
    for (NSDictionary *info in notifications) {
        NSTimeInterval start = [info[@"start"] doubleValue];
        NSDictionary *notif = info[@"notification"];
        NSString *title = notif[@"title"];
        NSString *content = notif[@"content"];
        NSString *appID = notif[@"bundleIdentifier"];
        
        NCNotificationRequest *request = [%c(NCNotificationRequest) notificationRequestWithSectionId:appID notificationId:[NSString stringWithFormat:@"debug-notif-req-%@", [NSUUID UUID].UUIDString] threadId:[NSString stringWithFormat:@"debug-thread-req-%@", [NSUUID UUID].UUIDString] title:title message:content timestamp:[NSDate date] destinations:[NSSet setWithObjects:@"BulletinDestinationCoverSheet", @"BulletinDestinationBanner", @"BulletinDestinationNotificationCenter", @"BulletinDestinationLockScreen", nil]];
        SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:appID];
        if (app) {
            [request.content setValue:app.displayName forKey:@"header"];
            [request.content setValue:[[[%c(SBApplicationIcon) alloc] initWithApplication:app] generateIconImage:5] forKey:@"_icon"];
        } else {
            [request.content setValue:appID forKey:@"header"];
        }
        [request.content setValue:[NSDate date] forKey:@"_date"];
        [request.options setValue:@(1) forKey:@"_canPlaySound"];
        [request.options setValue:@(1) forKey:@"_canTurnOnDisplay"];
        [request.options setValue:@(1) forKey:@"_alertsWhenLocked"];
        
        [request setValue:[[%c(NCNotificationSound) alloc] init] forKey:@"_sound"];
        [request.sound setValue:@(2) forKey:@"_soundType"];
        [request.sound setValue:[(TLAlertConfiguration *)[%c(TLAlertConfiguration) alloc] initWithType:17] forKey:@"_alertConfiguration"];
        
        [NSTimer scheduledTimerWithTimeInterval:start repeats:NO block:^(NSTimer *timer) {
            [((SpringBoard *)[UIApplication sharedApplication]).notificationDispatcher.dispatcher postNotificationWithRequest:request];
            [notificationRequests addObject:request];
        }];
    }
}

- (void)settingNamed:(NSString *)name changedTo:(NSString *)value {
    if ([name isEqualToString:@"spoofsCarrier"]) {
        spoofsCarrier = [value isEqualToString:@"1"];
    } else if ([name isEqualToString:@"spoofsTime"]) {
        spoofsTime = [value isEqualToString:@"1"];
    } else if ([name isEqualToString:@"carrierName"]) {
        carrierName = value;
    }
    StatusBarOverrideData *overrides = [%c(UIStatusBarServer) getStatusBarOverrideData];
    
    if (spoofsCarrier) strcpy(overrides->values.serviceString, [carrierName cStringUsingEncoding:NSUTF8StringEncoding]);
    overrides->overrideServiceString = spoofsCarrier ? 1 : 0;
    
    [[[UIApplication sharedApplication] statusBar] setLocalDataOverrides:overrides];
    [[[UIApplication sharedApplication] statusBar] forceUpdateData:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:kStatusBarSettingsChanged object:nil];
    
    ((SBDateTimeController *)[%c(SBDateTimeController) sharedInstance]).overrideDate = spoofsTime ? getOverrideDate() : nil;
}

- (void)triggeredActionNamed:(NSString *)name {
    if ([name isEqualToString:@"respring"]) {
        SBSRelaunchAction *restartAction = [%c(SBSRelaunchAction) actionWithReason:@"RestartRenderServer" options:4 targetURL:nil];
        [[%c(FBSSystemService) sharedService] sendActions:[NSSet setWithObject:restartAction] withResult:nil];
    } else if ([name isEqualToString:@"clearAll"]) {
        for (NCNotificationRequest *request in notificationRequests) {
            [((SpringBoard *)[UIApplication sharedApplication]).notificationDispatcher.dispatcher withdrawNotificationWithRequest:request];
        }
        notificationRequests = [NSMutableArray array];
    }
}

- (NSDictionary *)getConnectedPayload {
    return @{@"type": @"settings", @"settings": @{@"carrierName": carrierName, @"spoofsCarrier": spoofsCarrier ? @"1" : @"0", @"spoofsTime": spoofsTime ? @"1" : @"0"}};
}

@end

%hook NCNotificationListViewController

- (void)notificationListCellRequestsDismissAction:(NCNotificationListCell *)cell completion:(/*^block*/id)completion {
    %orig;
    NCNotificationRequest *request = cell.contentViewController.notificationRequest;
    if (request && [[request notificationIdentifier] rangeOfString:@"debug-notif-req-"].location != NSNotFound) {
        [((SpringBoard *)[UIApplication sharedApplication]).notificationDispatcher.dispatcher withdrawNotificationWithRequest:request];
    }
}

%end

%ctor {
    manager = [[DDNotificationToolsManager alloc] init];
    manager.delegate = [[NotificationToolsManagerDelegate alloc] init];
}
