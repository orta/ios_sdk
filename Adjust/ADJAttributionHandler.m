//
//  ADJAttributionHandler.m
//  adjust
//
//  Created by Pedro Filipe on 29/10/14.
//  Copyright (c) 2014 adjust GmbH. All rights reserved.
//

#import "ADJAttributionHandler.h"
#import "ADJAdjustFactory.h"
#import "ADJUtil.h"
#import "ADJActivityHandler.h"
#import "NSString+ADJAdditions.h"
#import "ADJTimerOnce.h"

static const char * const kInternalQueueName     = "com.adjust.AttributionQueue";

@interface ADJAttributionHandler()

@property (nonatomic) dispatch_queue_t internalQueue;
@property (nonatomic, assign) id<ADJActivityHandler> activityHandler;
@property (nonatomic, assign) id<ADJLogger> logger;
@property (nonatomic, retain) ADJTimerOnce *timer;
@property (nonatomic, retain) ADJActivityPackage * attributionPackage;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL hasDelegate;

@end

static const double kRequestTimeout = 60; // 60 seconds

@implementation ADJAttributionHandler

+ (id<ADJAttributionHandler>)handlerWithActivityHandler:(id<ADJActivityHandler>)activityHandler
                                 withAttributionPackage:(ADJActivityPackage *) attributionPackage
                                            startPaused:(BOOL)startPaused
                                            hasDelegate:(BOOL)hasDelegate;
{
    return [[ADJAttributionHandler alloc] initWithActivityHandler:activityHandler
                                           withAttributionPackage:attributionPackage
                                                      startPaused:startPaused
                                                      hasDelegate:hasDelegate];
}

- (id)initWithActivityHandler:(id<ADJActivityHandler>) activityHandler
       withAttributionPackage:(ADJActivityPackage *) attributionPackage
                  startPaused:(BOOL)startPaused
                  hasDelegate:(BOOL)hasDelegate;
{
    self = [super init];
    if (self == nil) return nil;

    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    self.activityHandler = activityHandler;
    self.logger = ADJAdjustFactory.logger;
    self.attributionPackage = attributionPackage;
    self.paused = startPaused;
    self.hasDelegate = hasDelegate;
    self.timer = [ADJTimerOnce timerWithBlock:^{ [self getAttributionInternal]; }
                                         queue:self.internalQueue];

    return self;
}

- (void) checkResponse:(NSDictionary *)jsonDict {
    dispatch_async(self.internalQueue, ^{
        [self checkResponseInternal:jsonDict];
    });
}

- (void) getAttributionWithDelay:(int)milliSecondsDelay {
    NSTimeInterval secondsDelay = milliSecondsDelay / 1000;
    NSTimeInterval nextAskIn = [self.timer fireIn];
    if (nextAskIn > secondsDelay) {
        return;
    }

    if (milliSecondsDelay > 0) {
        [self.logger debug:@"Waiting to query attribution in %d milliseconds", milliSecondsDelay];
    }

    // set the new time the timer will fire in
    [self.timer startIn:secondsDelay];
}

- (void) getAttribution {
    [self getAttributionWithDelay:0];
}

- (void) pauseSending {
    self.paused = YES;
}

- (void) resumeSending {
    self.paused = NO;
}

#pragma mark - internal

// session deeplink to launch always, but after the
//  attribution changed delegate if it exists
-(void) checkResponseInternal:(NSDictionary *)jsonDict
{
    if ([ADJUtil isNull:jsonDict]) {
        return;
    }

    NSString * sessionDeeplink = [jsonDict objectForKey:@"deeplink"];

    // TODO parse this correctly
    NSNumber* considerDeeplink = [jsonDict objectForKey :@"consider_deeplink"];
    BOOL launchAttributionDeeplink = [considerDeeplink boolValue];

    NSDictionary* jsonAttribution = [jsonDict objectForKey:@"attribution"];
    ADJAttribution *attribution = [ADJAttribution dataWithJsonDict:jsonAttribution];

    NSNumber *timerMilliseconds = [jsonDict objectForKey:@"ask_in"];

    if (timerMilliseconds == nil) {
        [self.activityHandler updateAttribution:attribution
                                sessionDeeplink:sessionDeeplink
                            launchAttributionDeeplink:launchAttributionDeeplink];

        [self.activityHandler setAskingAttribution:NO];

        return;
    };

    [self.activityHandler launchSessionDeepLink:sessionDeeplink];

    [self.activityHandler setAskingAttribution:YES];

    [self getAttributionWithDelay:[timerMilliseconds intValue]];
}

-(void) getAttributionInternal {
    if (!self.hasDelegate) {
        return;
    }
    if (self.paused) {
        [self.logger debug:@"Attribution handler is paused"];
        return;
    }
    [self.logger verbose:@"%@", self.attributionPackage.extendedString];

    [ADJUtil sendRequest:[self request]
      prefixErrorMessage:@"Failed to get attribution"
     jsonResponseHandler:^(NSDictionary *jsonDict) {
         [self checkResponse:jsonDict];
     }];
}

#pragma mark - private

- (NSMutableURLRequest *)request {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self url]];
    request.timeoutInterval = kRequestTimeout;
    request.HTTPMethod = @"GET";

    [request setValue:self.attributionPackage.clientSdk forHTTPHeaderField:@"Client-Sdk"];

    return request;
}

- (NSURL *)url {
    NSString *parameters = [ADJUtil queryString:self.attributionPackage.parameters];
    NSString *relativePath = [NSString stringWithFormat:@"%@?%@", self.attributionPackage.path, parameters];
    NSURL *baseUrl = [NSURL URLWithString:ADJUtil.baseUrl];
    NSURL *url = [NSURL URLWithString:relativePath relativeToURL:baseUrl];
    
    return url;
}

@end
