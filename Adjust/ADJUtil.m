//
//  ADJUtil.m
//  Adjust
//
//  Created by Christian Wellenbrock on 2013-07-05.
//  Copyright (c) 2013 adjust GmbH. All rights reserved.
//

#import "ADJUtil.h"
#import "ADJLogger.h"
#import "UIDevice+ADJAdditions.h"
#import "ADJAdjustFactory.h"
#import "NSString+ADJAdditions.h"
#import "ADJAdjustFactory.h"
#import "ADJResponseDataTasks.h"

#include <sys/xattr.h>

static NSString * const kBaseUrl   = @"https://app.adjust.com";
static NSString * const kClientSdk = @"ios4.5.0";

static NSString * const kDateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'Z";
static NSDateFormatter *dateFormat;

#pragma mark -
@implementation ADJUtil

+ (void) initialize {
    dateFormat = [[NSDateFormatter alloc] init];

    if ([NSCalendar instancesRespondToSelector:@selector(calendarWithIdentifier:)]) {
        // http://stackoverflow.com/a/3339787
        NSString * calendarIdentifier;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
        if (&NSCalendarIdentifierGregorian != NULL) {
#pragma clang diagnostic pop
            calendarIdentifier = NSCalendarIdentifierGregorian;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            calendarIdentifier = NSGregorianCalendar;
#pragma clang diagnostic pop
        }


        dateFormat.calendar = [NSCalendar calendarWithIdentifier:calendarIdentifier];
    }

    dateFormat.locale = [NSLocale systemLocale];
    [dateFormat setDateFormat:kDateFormat];
}

+ (NSString *)baseUrl {
    return kBaseUrl;
}

+ (NSString *)clientSdk {
    return kClientSdk;
}

// inspired by https://gist.github.com/kevinbarrett/2002382
+ (void)excludeFromBackup:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    const char* filePath = [[url path] fileSystemRepresentation];
    const char* attrName = "com.apple.MobileBackup";
    id<ADJLogger> logger = ADJAdjustFactory.logger;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
    if (&NSURLIsExcludedFromBackupKey == nil) {
        u_int8_t attrValue = 1;
        int result = setxattr(filePath, attrName, &attrValue, sizeof(attrValue), 0, 0);
        if (result != 0) {
            [logger debug:@"Failed to exclude '%@' from backup", url.lastPathComponent];
        }
    } else { // iOS 5.0 and higher
        // First try and remove the extended attribute if it is present
        ssize_t result = getxattr(filePath, attrName, NULL, sizeof(u_int8_t), 0, 0);
        if (result != -1) {
            // The attribute exists, we need to remove it
            int removeResult = removexattr(filePath, attrName, 0);
            if (removeResult == 0) {
                [logger debug:@"Removed extended attribute on file '%@'", url];
            }
        }

        // Set the new key
        NSError *error = nil;
        BOOL success = [url setResourceValue:[NSNumber numberWithBool:YES]
                                      forKey:NSURLIsExcludedFromBackupKey
                                       error:&error];
        if (!success || error != nil) {
            [logger debug:@"Failed to exclude '%@' from backup (%@)", url.lastPathComponent, error.localizedDescription];
        }
    }
#pragma clang diagnostic pop

}

+ (NSString *)formatSeconds1970:(double) value {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:value];

    return [self formatDate:date];
}

+ (NSString *)formatDate:(NSDate *) value {
    return [dateFormat stringFromDate:value];
}

+ (void) buildJsonDict:(NSData *)jsonData
                   responseData:(ADJResponseData *)responseData
{
    if (jsonData == nil) {
        return;
    }
    NSError *error = nil;
    NSDictionary *jsonDict = nil;
    @try {
        jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    } @catch (NSException *ex) {
        NSString * message = [NSString stringWithFormat:@"Failed to parse json response. (%@)", ex.description];
        [ADJAdjustFactory.logger error:message];
        responseData.message = message;
        return;
    }

    if (error != nil) {
        NSString * message = [NSString stringWithFormat:@"Failed to parse json response. (%@)", error.localizedDescription];
        [ADJAdjustFactory.logger error:message];
        responseData.message = message;
        return;
    }

    responseData.jsonResponse = jsonDict;
}

+ (NSString *)getFullFilename:(NSString *) baseFilename {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [paths objectAtIndex:0];
    NSString *filename = [path stringByAppendingPathComponent:baseFilename];
    return filename;
}

+ (id)readObject:(NSString *)filename
      objectName:(NSString *)objectName
           class:(Class) classToRead
{
    id<ADJLogger> logger = [ADJAdjustFactory logger];
    @try {
        NSString *fullFilename = [ADJUtil getFullFilename:filename];
        id object = [NSKeyedUnarchiver unarchiveObjectWithFile:fullFilename];
        if ([object isKindOfClass:classToRead]) {
            [logger debug:@"Read %@: %@", objectName, object];
            return object;
        } else if (object == nil) {
            [logger verbose:@"%@ file not found", objectName];
        } else {
            [logger error:@"Failed to read %@ file", objectName];
        }
    } @catch (NSException *ex ) {
        [logger error:@"Failed to read %@ file (%@)", objectName, ex];
    }

    return nil;
}

+ (void)writeObject:(id)object
           filename:(NSString *)filename
         objectName:(NSString *)objectName {
    id<ADJLogger> logger = [ADJAdjustFactory logger];
    NSString *fullFilename = [ADJUtil getFullFilename:filename];
    BOOL result = [NSKeyedArchiver archiveRootObject:object toFile:fullFilename];
    if (result == YES) {
        [ADJUtil excludeFromBackup:fullFilename];
        [logger debug:@"Wrote %@: %@", objectName, object];
    } else {
        [logger error:@"Failed to write %@ file", objectName];
    }
}

+ (NSString *) queryString:(NSDictionary *)parameters {
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in parameters) {
        NSString *value = [parameters objectForKey:key];
        NSString *escapedValue = [value adjUrlEncode];
        NSString *escapedKey = [key adjUrlEncode];
        NSString *pair = [NSString stringWithFormat:@"%@=%@", escapedKey, escapedValue];
        [pairs addObject:pair];
    }

    double now = [NSDate.date timeIntervalSince1970];
    NSString *dateString = [ADJUtil formatSeconds1970:now];
    NSString *escapedDate = [dateString adjUrlEncode];
    NSString *sentAtPair = [NSString stringWithFormat:@"%@=%@", @"sent_at", escapedDate];

    [pairs addObject:sentAtPair];

    NSString *queryString = [pairs componentsJoinedByString:@"&"];
    
    return queryString;
}

+ (BOOL)isNull:(id)value {
    return value == nil || value == (id)[NSNull null];
}

+ (NSString *)formatErrorMessage:(NSString *)prefixErrorMessage
              systemErrorMessage:(NSString *)systemErrorMessage
              suffixErrorMessage:(NSString *)suffixErrorMessage
{
    NSString * errorMessage = [NSString stringWithFormat:@"%@ (%@)", prefixErrorMessage, systemErrorMessage];
    if (suffixErrorMessage == nil) {
        return errorMessage;
    } else {
        return [errorMessage stringByAppendingFormat:@" %@", suffixErrorMessage];
    }
}

+ (void)sendRequest:(NSMutableURLRequest *)request
 prefixErrorMessage:(NSString *)prefixErrorMessage
    activityPackage:(ADJActivityPackage *)activityPackage
responseDataTasksHandler:(void (^) (ADJResponseDataTasks * responseDataTasks))responseDataTasksHandler
{
    [ADJUtil sendRequest:request
      prefixErrorMessage:prefixErrorMessage
      suffixErrorMessage:nil
         activityPackage:activityPackage
responseDataTasksHandler:responseDataTasksHandler];
}

+ (void)sendRequest:(NSMutableURLRequest *)request
 prefixErrorMessage:(NSString *)prefixErrorMessage
 suffixErrorMessage:(NSString *)suffixErrorMessage
    activityPackage:(ADJActivityPackage *)activityPackage
responseDataTasksHandler:(void (^) (ADJResponseDataTasks * responseDataTasks))responseDataTasksHandler
{
    Class NSURLSessionClass = NSClassFromString(@"NSURLSession");
    if (NSURLSessionClass != nil) {
        [ADJUtil sendNSURLSessionRequest:request
                      prefixErrorMessage:prefixErrorMessage
                      suffixErrorMessage:suffixErrorMessage
                         activityPackage:activityPackage
                responseDataTasksHandler:responseDataTasksHandler];
    } else {
        [ADJUtil sendNSURLConnectionRequest:request
                         prefixErrorMessage:prefixErrorMessage
                         suffixErrorMessage:suffixErrorMessage
                            activityPackage:activityPackage
                   responseDataTasksHandler:responseDataTasksHandler];
    }
}

+ (void)sendNSURLSessionRequest:(NSMutableURLRequest *)request
             prefixErrorMessage:(NSString *)prefixErrorMessage
             suffixErrorMessage:(NSString *)suffixErrorMessage
                activityPackage:(ADJActivityPackage *)activityPackage
       responseDataTasksHandler:(void (^) (ADJResponseDataTasks * responseDataTasks))responseDataTasksHandler
{
    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:
                                  ^(NSData *data, NSURLResponse *response, NSError *error) {
                                      ADJResponseDataTasks * responseDataTasks = [ADJUtil completionHandler:data
                                                                                                   response:(NSHTTPURLResponse *)response
                                                                                                      error:error
                                                                                         prefixErrorMessage:prefixErrorMessage
                                                                                         suffixErrorMessage:suffixErrorMessage
                                                                                            activityPackage:activityPackage];
                                      responseDataTasksHandler(responseDataTasks);
                                  }];
    [task resume];
}

+ (void)sendNSURLConnectionRequest:(NSMutableURLRequest *)request
                prefixErrorMessage:(NSString *)prefixErrorMessage
                suffixErrorMessage:(NSString *)suffixErrorMessage
                   activityPackage:(ADJActivityPackage *)activityPackage
          responseDataTasksHandler:(void (^) (ADJResponseDataTasks * responseDataTasks))responseDataTasksHandler
{
    NSError *responseError = nil;
    NSHTTPURLResponse *urlResponse = nil;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData * data = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:&urlResponse
                                                             error:&responseError];
#pragma clang diagnostic pop

    ADJResponseDataTasks * responseDataTasks = [ADJUtil completionHandler:data
                                                                 response:(NSHTTPURLResponse *)urlResponse
                                                                    error:responseError
                                                       prefixErrorMessage:prefixErrorMessage
                                                       suffixErrorMessage:suffixErrorMessage
                                                          activityPackage:activityPackage];

    responseDataTasksHandler(responseDataTasks);
}

+ (ADJResponseDataTasks *)completionHandler:(NSData *)data
                                   response:(NSHTTPURLResponse *)urlResponse
                                      error:(NSError *)responseError
                         prefixErrorMessage:(NSString *)prefixErrorMessage
                         suffixErrorMessage:(NSString *)suffixErrorMessage
                            activityPackage:(ADJActivityPackage *)activityPackage
{
    ADJResponseDataTasks * responseDataTasks = [ADJResponseDataTasks responseDataTasks];
    responseDataTasks.responseData = [ADJResponseData responseData];
    responseDataTasks.finishDelegate = activityPackage.failureDelegate;

    // connection error
    if (responseError != nil) {
        [ADJAdjustFactory.logger error:[ADJUtil formatErrorMessage:prefixErrorMessage
                                                systemErrorMessage:responseError.localizedDescription
                                                suffixErrorMessage:suffixErrorMessage]];
        return responseDataTasks;
    }
    if ([ADJUtil isNull:data]) {
        [ADJAdjustFactory.logger error:[ADJUtil formatErrorMessage:prefixErrorMessage
                                                systemErrorMessage:@"empty error"
                                                suffixErrorMessage:suffixErrorMessage]];
        return responseDataTasks;
    }

    NSString *responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] adjTrim];
    NSInteger statusCode = urlResponse.statusCode;

    [ADJAdjustFactory.logger verbose:@"Response: %@", responseString];

    [ADJUtil buildJsonDict:data responseData:responseDataTasks.responseData];

    if ([ADJUtil isNull:responseDataTasks.responseData.jsonResponse]) {
        return responseDataTasks;
    }

    NSString* messageResponse = [responseDataTasks.responseData.jsonResponse objectForKey:@"message"];

    responseDataTasks.responseData.message = messageResponse;
    responseDataTasks.responseData.timeStamp = [responseDataTasks.responseData.jsonResponse objectForKey:@"timestamp"];

    if (messageResponse == nil) {
        messageResponse = @"No message found";
    }

    if (statusCode == 200) {
        [ADJAdjustFactory.logger info:@"%@", messageResponse];
        responseDataTasks.finishDelegate = activityPackage.successDelegate;
    } else {
        [ADJAdjustFactory.logger error:@"%@", messageResponse];
    }

    return responseDataTasks;
}

// convert all values to strings, if value is dictionary -> recursive call
+ (NSDictionary *)convertDictionaryValues:(NSDictionary *)dictionary
{
    NSMutableDictionary * convertedDictionary = [[NSMutableDictionary alloc] initWithCapacity:dictionary.count];

    for (NSString * key in dictionary) {
        id value = [dictionary objectForKey:key];
        if ([value isKindOfClass:[NSDictionary class]]) {
            // dictionary value, recursive call
            NSDictionary * dictionaryValue = [ADJUtil convertDictionaryValues:(NSDictionary *)value];
            [convertedDictionary setObject:dictionaryValue forKey:key];

        } else if ([value isKindOfClass:[NSDate class]]) {
            // format date to our custom format
            NSString * dateStingValue = [ADJUtil formatDate:value];
            [convertedDictionary setObject:dateStingValue forKey:key];

        } else {
            // convert all other objects directly to string
            NSString * stringValue = [NSString stringWithFormat:@"%@", value];
            [convertedDictionary setObject:stringValue forKey:key];
        }
    }

    return convertedDictionary;
}
@end
