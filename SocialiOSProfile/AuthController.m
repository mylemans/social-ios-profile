/*
 Copyright (C) 2012-2014 Soomla Inc.
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "AuthController.h"
#import "UserProfile.h"
#import "UserProfileStorage.h"
#import "UserProfileNotFoundException.h"
#import "ProfileEventHandling.h"
#import "IAuthProvider.h"
#import "SocialUtils.h"
#import "AccessTokenStorage.h"
#import "UserProfileUtils.h"

@implementation AuthController

static NSString* TAG = @"SOCIAL AuthController";

- (id)initWithParameters:(NSDictionary *)providerParams {
    if (self = [super init]) {

        // TODO: Check if providerPkgPrefix can be omitted completely in iOS
        if (![self loadProvidersWithProtocol:@protocol(IAuthProvider) andProviderParams:providerParams]) {
            NSString* msg = @"You don't have a IAuthProvider service attached. \
                            Decide which IAuthProvider you want, and add its static libraries \
                            and headers to the target's search path.";
            LogDebug(TAG, msg);
        } else {
            
        }
    }

    return self;
}

- (id)initWithoutLoadingProviders {
    if (self = [super init]) {
    }
    return self;
}

- (void)loginWithProvider:(Provider)provider andPayload:(NSString *)payload {
    
    id<IAuthProvider> authProvider = (id<IAuthProvider>)[self getProvider:provider];
    [ProfileEventHandling postLoginStarted:provider withPayload:payload];
    
    // Perform login process
    // TODO: Check if need to change any nonatomic properties
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [authProvider login:^(Provider provider) {
            [authProvider getUserProfile: ^(UserProfile *userProfile) {
                [UserProfileStorage setUserProfile:userProfile];
                
                [ProfileEventHandling postLoginFinished:userProfile withPayload:payload];
            } fail:^(NSString *message) {
                [ProfileEventHandling postLoginFailed:provider withMessage:message withPayload:payload];
            }];
        } fail:^(NSString *message) {
            [ProfileEventHandling postLoginFailed:provider withMessage:message withPayload:payload];
        } cancel:^{
            [ProfileEventHandling postLoginCancelled:provider withPayload:payload];
        }];
    }];
}

- (void)logoutWithProvider:(Provider)provider {
    
    id<IAuthProvider> authProvider = (id<IAuthProvider>)[self getProvider:provider];
    UserProfile* userProfile = nil;
    
    @try {
        userProfile = [self getStoredUserProfileWithProvider:provider];
    }
    @catch (NSException *ex) {
        LogError(TAG, ([NSString stringWithFormat:@"%@", [ex callStackSymbols]]));
    }
    
    // Perform logout process
    [ProfileEventHandling postLogoutStarted:provider];
    [authProvider logout:^() {
        if (userProfile) {
            [UserProfileStorage removeUserProfile:userProfile];
        }
        if (provider == GOOGLE) {
            [AccessTokenStorage removeAccessToken:provider];
        }
        [ProfileEventHandling postLogoutFinished:provider];
    }
    fail:^(NSString* message) {
        [ProfileEventHandling postLogoutFailed:provider withMessage:message];
    }];
}

- (BOOL)isLoggedInWithProvider:(Provider)provider {
    id<IAuthProvider> authProvider = (id<IAuthProvider>)[self getProvider:provider];
    return [authProvider isLoggedIn];
}

- (void)getAccessTokenWithProvider:(Provider)provider andRequestNew:(BOOL)requestNew andPayload:(NSString *)payload andCallback:(GPTokenSuccessCallback)callback{
    
    mTokenSuccessCallback = callback;
    id<IAuthProvider> authProvider = (id<IAuthProvider>)[self getProvider:provider];
    [ProfileEventHandling postGetAccessTokenStarted:provider withPayload:payload];
    
    // Perform get access token process
    // TODO: Check if need to change any nonatomic properties
    //[[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [authProvider getAccessToken:^(NSString *accessToken) {
            [ProfileEventHandling postGetAccessTokenFinished:provider withAccessToken:accessToken withPayload:payload];
            if (provider == GOOGLE) {
                double delayInSeconds = 1.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [AccessTokenStorage setAccessToken:provider andAccessToken:accessToken];
                    mTokenSuccessCallback(GPTRUE,[accessToken UTF8String],[[UserProfileUtils providerEnumToString:provider] UTF8String],[payload UTF8String]);
                });
            }
        } fail:^(NSString *message) {
            [ProfileEventHandling postGetAccessTokenFailed:provider withMessage:message withPayload:payload];
            mTokenSuccessCallback(GPFALSE,[message UTF8String],[[UserProfileUtils providerEnumToString:provider] UTF8String],[payload UTF8String]);
        } cancel:^{
            [ProfileEventHandling postGetAccessTokenCancelled:provider withPayload:payload];
            NSString *cancelled=@"Get access token cancelled";
            mTokenSuccessCallback(GPFALSE,[cancelled UTF8String],[[UserProfileUtils providerEnumToString:provider] UTF8String],[payload UTF8String]);
        }];
    //}];
}

- (UserProfile *)getStoredUserProfileWithProvider:(Provider)provider {
    UserProfile* userProfile = [UserProfileStorage getUserProfile:provider];
    if (!userProfile) {
        @throw [[UserProfileNotFoundException alloc] init];
    }
    return userProfile;
}

- (BOOL)tryHandleOpenURL:(Provider)provider openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    id<IAuthProvider> authProvider = (id<IAuthProvider>)[self getProvider:provider];
    return [authProvider tryHandleOpenURL:url sourceApplication:sourceApplication annotation:annotation];
}

- (BOOL)tryHandleOpenURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    for(id key in self.providers) {
        id<IAuthProvider> value = [self.providers objectForKey:key];
        if ([value tryHandleOpenURL:url sourceApplication:sourceApplication annotation:annotation]) {
            return YES;
        }
    }
    
    return NO;
}


@end
