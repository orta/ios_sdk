//
//  ADJActivityHandler.h
//  Adjust
//
//  Created by Christian Wellenbrock on 2013-07-01.
//  Copyright (c) 2013 adjust GmbH. All rights reserved.
//

#import "Adjust.h"
#import "ADJAttribution.h"

@protocol ADJActivityHandler <NSObject>

- (id)initWithConfig:(ADJConfig *)adjustConfig;

- (void)trackSubsessionStart;
- (void)trackSubsessionEnd;

- (void)trackEvent:(ADJEvent *)event;

- (void)finishedTracking:(NSDictionary *)jsonDict;
- (void)setEnabled:(BOOL)enabled;
- (BOOL)isEnabled;
- (void)appWillOpenUrl:(NSURL*)url;
- (void)setDeviceToken:(NSData *)deviceToken;

- (ADJAttribution*) attribution;
- (void)setAttribution:(ADJAttribution*)attribution;
- (void)setAskingAttribution:(BOOL)askingAttribution;

- (void)updateAttribution:(ADJAttribution*) attribution
          sessionDeeplink:(NSString*)sessionDeeplink
      launchAttributionDeeplink:(BOOL)launchAttributionDeeplink;

- (void)setIadDate:(NSDate*)iAdImpressionDate withPurchaseDate:(NSDate*)appPurchaseDate;

- (void)launchAttributionDelegate:(void(^)(void))attributionDelegateFinishCallback;

- (void)setOfflineMode:(BOOL)offline;

- (void)launchDeepLink:(NSString *)deeplink;

- (void)launchSessionDeepLink:(NSString *)deeplink;
@end

@interface ADJActivityHandler : NSObject <ADJActivityHandler>

+ (id<ADJActivityHandler>)handlerWithConfig:(ADJConfig *)adjustConfig;

@end
