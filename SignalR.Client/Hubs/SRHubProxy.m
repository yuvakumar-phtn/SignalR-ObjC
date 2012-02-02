//
//  SRHubProxy.m
//  SignalR
//
//  Created by Alex Billingsley on 10/31/11.
//  Copyright (c) 2011 DyKnow LLC. (http://dyknow.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and 
//  to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of 
//  the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
//  THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF 
//  CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
//  DEALINGS IN THE SOFTWARE.
//

#import "SRHubProxy.h"
#import "SRSignalRConfig.h"

#import "SBJson.h"
#import "SRConnection.h"
#import "SRSubscription.h"
#import "SRHubServerInvocation.h"
#import "SRHubResult.h"

@interface SRHubProxy ()

@end

@implementation SRHubProxy

@synthesize connection = _connection;
@synthesize hubName = _hubName;
@synthesize state = _state;
@synthesize subscriptions = _subscriptions;

#pragma mark - 
#pragma mark Initialization

+ (SRHubProxy *)hubProxyWith:(SRConnection *)connection hubName:(NSString *)hubname
{
    return [[SRHubProxy alloc] initWithConnection:connection hubName:hubname];
}

- (id)initWithConnection:(SRConnection *)connection hubName:(NSString *)hubname
{
    if (self = [super init]) 
    {
        _connection = connection;
        _hubName = hubname;
        _subscriptions = [[NSMutableDictionary alloc] init];
        _state = [[NSMutableDictionary alloc] init];
    }
    return self;
}

#pragma mark - 
#pragma mark Subscription Management

- (SRSubscription *)subscribe:(NSString *)eventName
{
    if([eventName isEqualToString:@""] || eventName == nil)
    {
        [NSException raise:@"ArgumentNullException" format:@"Argument %@ is null", @"eventName"];
    }
    
    SRSubscription *subscription = [_subscriptions objectForKey:eventName];
    if(subscription == nil)
    {
        subscription = [[SRSubscription alloc] init];
        [_subscriptions setObject:subscription forKey:eventName];
    }
    
    return subscription;
}

- (NSArray *)getSubscriptions
{
    return [_subscriptions allKeys];
}

- (void)invokeEvent:(NSString *)eventName withArgs:(NSArray *)args
{
    SRSubscription *eventObj = [_subscriptions objectForKey:eventName];
    if(eventObj != nil)
    {
        NSMethodSignature *signature = [eventObj.object methodSignatureForSelector:eventObj.selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:eventObj.selector];
        [invocation setTarget:eventObj.object];
        for(int i =0; i<[args count]; i++)
        {
            int arguementIndex = 2 + i;
            NSString *argument = [args objectAtIndex:i];
            [invocation setArgument:&argument atIndex:arguementIndex];
        }
        [invocation invoke];
    }
}

#pragma mark - 
#pragma mark State Management

- (id)getMember:(NSString *)name
{
    id value = [_state objectForKey:name];
    return value;
}

- (void)setMember:(NSString *)name object:(id)value
{
    [_state setValue:value forKey:name];
}

- (void)invoke:(NSString *)method withArgs:(NSArray *)args
{
    [self invoke:method withArgs:args continueWith:nil];
}

- (void)invoke:(NSString *)method withArgs:(NSArray *)args continueWith:(void(^)(id data))responseBlock
{
    if([method isEqualToString:@""] || method == nil)
    {
        [NSException raise:@"ArgumentNullException" format:@"Argument %@ is null", @"method"];
    }
    
    SRHubServerInvocation *hubData = [[SRHubServerInvocation alloc] init];
    hubData.hub = _hubName;
    hubData.action = method;
    hubData.data = [NSMutableArray arrayWithArray:args];
    hubData.state = _state;
    
    NSString *value = [[SBJsonWriter new] stringWithObject:hubData];
        
    [_connection send:value continueWith:^(id response)
    {
#if DEBUG_SERVER_SENT_EVENTS || DEBUG_LONG_POLLING || DEBUG_HTTP_BASED_TRANSPORT
        SR_DEBUG_LOG(@"[HTTP_BASED_TRANSPORT] did receive response %@",response);
#endif
         if([response isKindOfClass:[NSString class]])
         {
             SRHubResult *hubResult = [[SRHubResult alloc] initWithDictionary:[[SBJsonParser new] objectWithString:response]];
             if (hubResult != nil) 
             {
                 if(![hubResult.error isKindOfClass:[NSNull class]] && hubResult.error != nil)
                 {
                     [NSException raise:@"InvalidOperationException" format:hubResult.error];
                 }
                 
                 if(![hubResult.state isKindOfClass:[NSNull class]] && hubResult.state != nil)
                 {
                     for (id key in hubResult.state)
                     {
                         [self setMember:key object:[hubResult.state objectForKey:key]];
                     }
                 }
                 
                 if(responseBlock != nil)
                 {
                     responseBlock(hubResult.result);
                 }
             }
         }
    }];
}

- (NSString *)description 
{     
    return [NSString stringWithFormat:@"HubProxy: Name=%@ State=%@ Subscriptions:%@",_hubName,_state,_subscriptions];
}

- (void)dealloc
{
    _connection = nil;
    _hubName = nil;
    _state = nil;
    _subscriptions = nil;
}

@end
