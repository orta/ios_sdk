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
                          hasAttributionChangedDelegate:(BOOL)hasAttributionChangedDelegate;
{
    return [[ADJAttributionHandler alloc] initWithActivityHandler:activityHandler
                                           withAttributionPackage:attributionPackage
                                                      startPaused:startPaused
                                    hasAttributionChangedDelegate:hasAttributionChangedDelegate];
}

- (id)initWithActivityHandler:(id<ADJActivityHandler>) activityHandler
       withAttributionPackage:(ADJActivityPackage *) attributionPackage
                  startPaused:(BOOL)startPaused
hasAttributionChangedDelegate:(BOOL)hasAttributionChangedDelegate;
{
    self = [super init];
    if (self == nil) return nil;

    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    self.activityHandler = activityHandler;
    self.logger = ADJAdjustFactory.logger;
    self.attributionPackage = attributionPackage;
    self.paused = startPaused;
    self.hasDelegate = hasAttributionChangedDelegate;
    self.timer = [ADJTimerOnce timerWithBlock:^{ [self getAttributionInternal]; }
                                         queue:self.internalQueue];

    return self;
}

- (void) checkResponse:(ADJResponseDataTasks *)responseDataTasks {
    dispatch_async(self.internalQueue, ^{
        [self checkResponseInternal:responseDataTasks];
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
- (void) checkResponseInternal:(ADJResponseDataTasks *)responseDataTasks {
    [self checkAttributionInternal:responseDataTasks];

    [self.activityHandler launchResponseTasks:responseDataTasks];
}

- (void) checkAttributionInternal:(ADJResponseDataTasks *)responseDataTasks {
    NSDictionary * jsonResponse = responseDataTasks.responseData.jsonResponse;

    if (jsonResponse == nil) {
        return;
    }

    NSNumber *timerMilliseconds = [jsonResponse objectForKey:@"ask_in"];

    if (timerMilliseconds != nil) {
        [self.activityHandler setAskingAttribution:YES];

        [self getAttributionWithDelay:[timerMilliseconds intValue]];

        return;
    }

    [self.activityHandler setAskingAttribution:NO];

    NSDictionary * jsonAttribution = [jsonResponse objectForKey:@"attribution"];
    responseDataTasks.attribution = [ADJAttribution dataWithJsonDict:jsonAttribution];
}

- (void) getAttributionInternal {
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
         activityPackage:self.attributionPackage
responseDataTasksHandler:^(ADJResponseDataTasks * responseDataTasks)
    {
        [self checkResponse:responseDataTasks];
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
