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

#import "SocialFacebook.h"
#import "UserProfile.h"
#import "SocialUtils.h"

#pragma clang diagnostic push
#pragma ide diagnostic ignored "OCUnusedClassInspection"

#define DEFAULT_PAGE_SIZE 20

@interface SocialFacebook ()
@property(nonatomic) NSNumber *lastContactPage;
@property(nonatomic) NSNumber *lastFeedPage;
@end

@implementation SocialFacebook

@synthesize loginSuccess, loginFail, loginCancel,
            logoutSuccess;

static NSString *TAG = @"SOCIAL SocialFacebook";

- (id)init {
    self = [super init];
    if (!self) return nil;

    LogDebug(TAG, @"addObserver kUnityOnOpenURL notification");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(innerHandleOpenURL:)
                                                 name:@"kUnityOnOpenURL"
                                               object:nil];

    return self;
}

- (void)dealloc {
    LogDebug(TAG, @"removeObserver kUnityOnOpenURL notification");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)innerHandleOpenURL:(NSNotification *)notification {
    if ([[notification name] isEqualToString:@"kUnityOnOpenURL"]) {
        LogDebug(TAG, @"Successfully received the kUnityOnOpenURL notification!");

        NSURL *url = [[notification userInfo] valueForKey:@"url"];
        NSString *sourceApplication = [[notification userInfo] valueForKey:@"sourceApplication"];
        BOOL urlWasHandled = [FBAppCall handleOpenURL:url
                                    sourceApplication:sourceApplication
                                      fallbackHandler:^(FBAppCall *call) {
                    LogDebug(TAG, ([NSString stringWithFormat:@"Unhandled deep link: %@", url]));
                    // Here goes the code to handle the links
                    // Use the links to show a relevant view of your app to the user
                }];

        LogDebug(TAG,
                        ([NSString stringWithFormat:@"urlWasHandled: %@",
                                                    urlWasHandled ? @"True" : @"False"]));
    }
}

- (void)applyParams:(NSDictionary *)providerParams {
    // Nothing to do here, FB deals with AppID and AppName
}

- (Provider)getProvider {
    return FACEBOOK;
}

- (void)login:(loginSuccess)success fail:(loginFail)fail cancel:(loginCancel)cancel {

    // If the session state is any of the two "open" states when the button is clicked
    if (FBSession.activeSession.state == FBSessionStateOpen
            || FBSession.activeSession.state == FBSessionStateOpenTokenExtended) {

        // Close the session and remove the access token from the cache
        // The session state handler (in the app delegate) will be called automatically
        [FBSession.activeSession closeAndClearTokenInformation];

    } else {
        // Open a session showing the user the login UI
        // You must ALWAYS ask for public_profile permissions when opening a session
        [FBSession openActiveSessionWithReadPermissions:@[@"public_profile"]
                                           allowLoginUI:YES
                                      completionHandler:
                                              ^(FBSession *session, FBSessionState state, NSError *error) {
            self.loginSuccess = success;
            self.loginFail = fail;
            self.loginCancel = cancel;
            [self sessionStateChanged:session state:state error:error];
        }];
    }
}

/*
 Asks for the user's public profile and birthday.
 First checks for the existence of the `public_profile` and `user_birthday` permissions
 If the permissions are not present, requests them
 If/once the permissions are present, makes the user info request
 */
- (void)getUserProfile:(userProfileSuccess)success fail:(userProfileFail)fail {
    LogDebug(TAG, @"Getting user profile");
    [self checkPermissions: @[@"public_profile", @"user_birthday"] withWrite:NO
                   success:^() {

        [FBRequestConnection startForMeWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
            if (!error) {
                LogDebug(TAG, ([NSString stringWithFormat:@"user info: %@", result]));

                UserProfile *userProfile = [[UserProfile alloc] initWithProvider:FACEBOOK
                                                                    andProfileId:result[@"id"]
                                                                     andUsername:result[@"email"]
                                                                        andEmail:result[@"email"]
                                                                    andFirstName:result[@"first_name"]
                                                                     andLastName:result[@"last_name"]];

                userProfile.gender = result[@"gender"];
                userProfile.birthday = result[@"birthday"];
                userProfile.location = result[@"location"][@"name"];
                userProfile.avatarLink = [NSString stringWithFormat:@"http://graph.facebook.com/%@/picture?type=large", result[@"id"]];

                success(userProfile);
            } else {

                LogError(TAG, error.description);
                fail(error.description);
            }
        }];

    } fail:^(NSString *errorMessage) {
        fail(errorMessage);
    }];
}


- (void)logout:(logoutSuccess)success fail:(logoutFail)fail {

    self.logoutSuccess = success;

    // Clear this token
    [FBSession.activeSession closeAndClearTokenInformation];
}

/**
 Checks if the user is logged-in using the authentication provider
 
 @return YES if the user is already logged-in using the authentication provider, NO otherwise
 */
- (BOOL)isLoggedIn {
    return ((FBSession.activeSession != nil) && ((FBSession.activeSession.state == FBSessionStateOpen
                                                  || FBSession.activeSession.state == FBSessionStateOpenTokenExtended)));
}

- (BOOL)tryHandleOpenURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [FBAppCall handleOpenURL:url
                           sourceApplication:sourceApplication
                             fallbackHandler:^(FBAppCall *call) {
                                 LogDebug(TAG, ([NSString stringWithFormat:@"Unhandled deep link: %@", url]));
                                 // Here goes the code to handle the links
                                 // Use the links to show a relevant view of your app to the user
                             }];
}

/**
 * A function for parsing URL parameters.
 */
- (NSDictionary*)parseURLParams:(NSString *)query {
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        NSString *val =
        [kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        params[kv[0]] = val;
    }
    return params;
}

//
// Private Methods
//


// This method will handle ALL the session state changes in the app
- (void)sessionStateChanged:(FBSession *)session state:(FBSessionState)state error:(NSError *)error {

    // If the session was opened successfully
    if (!error && state == FBSessionStateOpen) {
        LogDebug(TAG, @"Session opened");

        // Callback
        if (self.loginSuccess) {
            self.loginSuccess(FACEBOOK);
        }
        [self clearLoginBlocks];
        return;
    }
    if (state == FBSessionStateClosed || state == FBSessionStateClosedLoginFailed) {

        if (state == FBSessionStateClosedLoginFailed) {
            if (self.loginCancel) {
                self.loginCancel();
            }
            [self clearLoginBlocks];
        }

        if (state == FBSessionStateClosed) {
            if (logoutSuccess) {
                self.logoutSuccess();
            }
            [self clearLoginBlocks];
        }

        // If the session is closed
        LogDebug(TAG, @"Session closed");
    }

    // Handle errors
    if (error) {
        LogError(TAG, @"Error");
        NSString *alertText;
        NSString *alertTitle;

        // If the error requires people using an app to make an action outside of the app in order to recover
        if ([FBErrorUtility shouldNotifyUserForError:error]) {
            alertTitle = @"Something went wrong";
            alertText = [FBErrorUtility userMessageForError:error];

            // Callback
            if (self.loginFail) {
                self.loginFail([NSString stringWithFormat:@"%@: %@", alertTitle, alertText]);
            }
            [self clearLoginBlocks];
        } else {

            // If the user cancelled login, do nothing
            if ([FBErrorUtility errorCategoryForError:error] == FBErrorCategoryUserCancelled) {
                LogError(TAG, @"User cancelled login");

                // Callback
                if (self.loginCancel) {
                    self.loginCancel();
                }
                [self clearLoginBlocks];

                // Handle session closures that happen outside of the app
            } else if ([FBErrorUtility errorCategoryForError:error] == FBErrorCategoryAuthenticationReopenSession) {
                alertTitle = @"Session Error";
                alertText = @"Your current session is no longer valid. Please log in again.";

                // Callback
                if (self.loginFail) {
                    self.loginFail([NSString stringWithFormat:@"%@: %@", alertTitle, alertText]);
                }
                [self clearLoginBlocks];

                // For simplicity, here we just show a generic message for all other errors
                // You can learn how to handle other errors using our guide: https://developers.facebook.com/docs/ios/errors
            } else {
                //Get more error information from the error
                NSDictionary *errorInformation = [[[error.userInfo objectForKey:@"com.facebook.sdk:ParsedJSONResponseKey"] objectForKey:@"body"] objectForKey:@"error"];

                // Show the user an error message
                alertTitle = @"Something went wrong";
                alertText = [NSString stringWithFormat:@"Please retry. \n\n If the problem persists contact us and mention this error code: %@", [errorInformation objectForKey:@"message"]];

                // Callback
                if (self.loginFail) {
                    self.loginFail([NSString stringWithFormat:@"%@: %@", alertTitle, alertText]);
                }
                [self clearLoginBlocks];
            }
        }

        // Clear this token
        [FBSession.activeSession closeAndClearTokenInformation];
    }
}

/**
A helper method for requesting user data from Facebook.
*/

- (void)checkPermissions: (NSArray*)permissionsNeeded withWrite:(BOOL)writePermissions success:(void (^)())success fail:(void(^)(NSString* message))fail {
    LogDebug(TAG, @"Getting user profile");

    // Request the permissions the user currently has
    [FBRequestConnection startWithGraphPath:@"/me/permissions"
                          completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        if (!error) {
            // These are the current permissions the user has
            NSArray *currentPermissions = [result data];

            // We will store here the missing permissions that we will have to request
            NSMutableArray *requestPermissions = [[NSMutableArray alloc] initWithArray:@[]];

            // Check if all the permissions we need are present in the user's current permissions
            // If they are not present add them to the permissions to be requested
            for (NSString *permission in permissionsNeeded) {
                BOOL found = NO;
                for (NSDictionary *currentPermission in currentPermissions) {
                    if ([permission isEqualToString:[currentPermission objectForKey:@"permission"]]) {
                        found = YES;
                        break;
                    }
                }
                if (!found) {
                    [requestPermissions addObject:permission];
                }
            }

            // If we have permissions to request
            if ([requestPermissions count] > 0) {
                
                if (writePermissions) {
                    // Ask for the missing read permissions
                    [FBSession.activeSession
                     requestNewPublishPermissions:requestPermissions
                     defaultAudience:FBSessionDefaultAudienceFriends 
                     completionHandler:^(FBSession *session, NSError *error) {
                         if (!error) {
                             // Permission granted, we can go on
                             success();
                         } else {
                             fail(error.description);
                         }
                     }];
                }
                else {
                    // Ask for the missing publish permissions
                    [FBSession.activeSession
                     requestNewReadPermissions:requestPermissions
                     completionHandler:^(FBSession *session, NSError *error) {
                         if (!error) {
                             // Permission granted, we can go on
                             success();
                         } else {
                             fail(error.description);
                         }
                     }];
                }
            } else {
                // Permissions are present
                // We can go on
                success();
            }

        } else {
            fail(error.description);
        }
    }];
}

/*
 Helper methods for clearing callback blocks
 */

- (void)clearLoginBlocks {
    self.loginSuccess = nil;
    self.loginFail = nil;
    self.loginCancel = nil;
}

@end

#pragma clang diagnostic pop