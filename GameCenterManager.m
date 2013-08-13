//
//  GameCenterManager.m
//
//  Created by Nihal Ahmed on 12-03-16.
//  Copyright (c) 2012 NABZ Software. All rights reserved.
//

#import "GameCenterManager.h"


#pragma mark - Game Center Manager Singleton

@implementation GameCenterManager

@synthesize isGameCenterAvailable;

static GameCenterManager *sharedManager = nil;

+ (GameCenterManager *)sharedManager {
    if(sharedManager == nil) {
        sharedManager = [[super allocWithZone:NULL] init];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if(![fileManager fileExistsAtPath:kGameCenterManagerDataPath]) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:dict] encryptedWithKey:kGameCenterManagerKey];
            [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
        }
        
        NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
        if(gameCenterManagerData == nil) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:dict] encryptedWithKey:kGameCenterManagerKey];
            [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
        }
        
        [sharedManager initGameCenter];
    }
    
    return sharedManager;
}

+ (id)allocWithZone:(NSZone *)zone {
    return [self sharedManager];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;    
}

#pragma mark - Methods
- (void)initGameCenter {
    // Check for presence of GKLocalPlayer class.
    BOOL localPlayerClassAvailable = (NSClassFromString(@"GKLocalPlayer")) != nil;
    
    // The device must be running iOS 4.1 or later.
    NSString *reqSysVer = @"4.1";
    NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
    BOOL osVersionSupported = ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending);
    
    BOOL isGameCenterAPIAvailable = (localPlayerClassAvailable && osVersionSupported);
    
    if(isGameCenterAPIAvailable) {
        [[GameCenterManager sharedManager] setIsGameCenterAvailable:YES];
    }
}

- (void)authenticate {
    [[GKLocalPlayer localPlayer] authenticateWithCompletionHandler:^(NSError *error) {
        NSDictionary *dict = nil;
        if(error == nil) {
            dict = [NSDictionary dictionary];
            if(![[NSUserDefaults standardUserDefaults] boolForKey:[@"scoresSynced" stringByAppendingString:[[GameCenterManager sharedManager] localPlayerId]]] ||
               ![[NSUserDefaults standardUserDefaults] boolForKey:[@"achievementsSynced" stringByAppendingString:[[GameCenterManager sharedManager] localPlayerId]]]) {
                [[GameCenterManager sharedManager] syncGameCenter];
            }
            else {
                [[GameCenterManager sharedManager] reportSavedScoresAndAchievements];
            }
            
            [self loadAchievementDescriptions];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerAuthenticatedNotification
                                                                object:[GameCenterManager sharedManager]
                                                              userInfo:dict];
        }
        else {
            dict = [NSDictionary dictionaryWithObject:error.localizedDescription forKey:@"error"];
            if(error.code == GKErrorNotSupported) {
                [[GameCenterManager sharedManager] setIsGameCenterAvailable:NO];
            }
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerAuthenticationErrorNotification
                                                                object:[GameCenterManager sharedManager]
                                                              userInfo:dict];
        }
    }];
}

- (void)syncGameCenter {
    if([[GameCenterManager sharedManager] isInternetAvailable]) {
        if(![[NSUserDefaults standardUserDefaults] boolForKey:[@"scoresSynced" stringByAppendingString:[[GameCenterManager sharedManager] localPlayerId]]]) {
            if(_leaderboards == nil) {
                [GKLeaderboard loadCategoriesWithCompletionHandler:^(NSArray *categories, NSArray *titles, NSError *error) {
                    if(error == nil) {
                        _leaderboards = [[NSMutableArray alloc] initWithArray:categories];
                        [[GameCenterManager sharedManager] syncGameCenter];
                    }
                }];
                return;
            }
            
            if(_leaderboards.count > 0) {
                GKLeaderboard *leaderboardRequest = [[GKLeaderboard alloc] initWithPlayerIDs:[NSArray arrayWithObject:[[GameCenterManager sharedManager] localPlayerId]]];
                [leaderboardRequest setCategory:[_leaderboards objectAtIndex:0]];
                [leaderboardRequest loadScoresWithCompletionHandler:^(NSArray *scores, NSError *error) {
                    if(error == nil) {
                        if(scores.count > 0) {
                            NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
                            NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
                            NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
                            if(playerDict == nil) {
                                playerDict = [NSMutableDictionary dictionary];
                            }
                            int savedHighScoreValue = 0;
                            NSNumber *savedHighScore = [playerDict objectForKey:leaderboardRequest.localPlayerScore.category];
                            if(savedHighScore != nil) {
                                savedHighScoreValue = [savedHighScore intValue];
                            }
                            [playerDict setObject:[NSNumber numberWithInt:MAX(leaderboardRequest.localPlayerScore.value, savedHighScoreValue)] forKey:leaderboardRequest.localPlayerScore.category];
                            [plistDict setObject:playerDict forKey:[[GameCenterManager sharedManager] localPlayerId]];
                            NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
                            [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
                        }
                        
                        [_leaderboards removeObjectAtIndex:0];
                        [[GameCenterManager sharedManager] syncGameCenter];
                    }
                }];
            }
            else {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:[@"scoresSynced" stringByAppendingString:[[GameCenterManager sharedManager] localPlayerId]]];
                [[GameCenterManager sharedManager] syncGameCenter];
            }
        }
        else if(![[NSUserDefaults standardUserDefaults] boolForKey:[@"achievementsSynced" stringByAppendingString:[[GameCenterManager sharedManager] localPlayerId]]]) {
            [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
                if(error == nil) {
                    if(achievements.count > 0) {
                        NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
                        NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
                        NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
                        if(playerDict == nil) {
                            playerDict = [NSMutableDictionary dictionary];
                        }
                        for(GKAchievement *achievement in achievements) {
                            [playerDict setObject:[NSNumber numberWithDouble:achievement.percentComplete] forKey:achievement.identifier];
                        }
                        [plistDict setObject:playerDict forKey:[[GameCenterManager sharedManager] localPlayerId]];
                        NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
                        [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
                    }
                    
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:[@"achievementsSynced" stringByAppendingString:[[GameCenterManager sharedManager] localPlayerId]]];
                    [[GameCenterManager sharedManager] syncGameCenter];
                }
            }];
        }
    }
}

- (void)saveAndReportScore:(int)score leaderboard:(NSString *)identifier {
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
    if(playerDict == nil) {
        playerDict = [NSMutableDictionary dictionary];
    }
    NSNumber *savedHighScore = [playerDict objectForKey:identifier];
    if(savedHighScore == nil) {
        savedHighScore = [NSNumber numberWithInt:0];
    }
    int savedHighScoreValue = [savedHighScore intValue];
    if(score > savedHighScoreValue) {
        [playerDict setObject:[NSNumber numberWithInt:score] forKey:identifier];
        [plistDict setObject:playerDict forKey:[[GameCenterManager sharedManager] localPlayerId]];
        NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
        [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
    }
    
    if([[GameCenterManager sharedManager] isGameCenterAvailable]) {
        if([GKLocalPlayer localPlayer].authenticated) {
            if([[GameCenterManager sharedManager] isInternetAvailable]) {
                GKScore *gkScore = [[GKScore alloc] initWithCategory:identifier];
                gkScore.value = score;
                [gkScore reportScoreWithCompletionHandler:^(NSError *error) {
                    NSDictionary *dict = nil;
                    if(error == nil) {
                        dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                identifier, @"category",
                                [NSNumber numberWithInt:score], @"score",
                                nil];
                        
                        // notify on screen
                        [[GKAchievementHandler defaultHandler] notifyAchievementTitle:@"New High Score"
                                                                           andMessage:[NSString stringWithFormat:@"%@ %d", identifier, score]];
                    }
                    else {
                        dict = [NSDictionary dictionaryWithObject:error.localizedDescription forKey:@"error"];
                        [[GameCenterManager sharedManager] saveScoreToReportLater:gkScore];
                    }
                    [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerReportScoreNotification
                                                                        object:[GameCenterManager sharedManager]
                                                                      userInfo:dict];
                }];
            }
            else {
                GKScore *gkScore = [[GKScore alloc] initWithCategory:identifier];
                [[GameCenterManager sharedManager] saveScoreToReportLater:gkScore];
            }
        }
    }
}

- (void)saveAndReportAchievement:(NSString *)identifier percentComplete:(double)percentComplete {
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
    if(playerDict == nil) {
        playerDict = [NSMutableDictionary dictionary];
    }
    NSNumber *savedPercentComplete = [playerDict objectForKey:identifier];
    if(savedPercentComplete == nil) {
        savedPercentComplete = [NSNumber numberWithDouble:0];
    }
    double savedPercentCompleteValue = [savedPercentComplete doubleValue];
    if(percentComplete > savedPercentCompleteValue) {
        [playerDict setObject:[NSNumber numberWithDouble:percentComplete] forKey:identifier];
        [plistDict setObject:playerDict forKey:[[GameCenterManager sharedManager] localPlayerId]];
        NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
        [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
    }
    
    if([[GameCenterManager sharedManager] isGameCenterAvailable]) {
        if([GKLocalPlayer localPlayer].authenticated) {
            if([[GameCenterManager sharedManager] isInternetAvailable]) {
                GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:identifier];
                achievement.percentComplete = percentComplete;
                [achievement reportAchievementWithCompletionHandler:^(NSError *error) {
                    NSDictionary *dict = nil;
                    if(error == nil) {
                        dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                identifier, @"category",
                                [NSNumber numberWithDouble:percentComplete], @"percent",
                                nil];
                        
                        // notify on screen
                        GKAchievementDescription *achievementDesc = [self getAchievementDescription:identifier];
                        if (achievementDesc) {
                            [[GKAchievementHandler defaultHandler] notifyAchievement:achievementDesc];
                        }
                    }
                    else {
                        dict = [NSDictionary dictionaryWithObject:error.localizedDescription forKey:@"error"];
                        [[GameCenterManager sharedManager] saveAchievementToReportLater:identifier percentComplete:percentComplete];
                    }
                    [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerReportAchievementNotification
                                                                        object:[GameCenterManager sharedManager]
                                                                      userInfo:dict];
                }];
            }
            else {
                [[GameCenterManager sharedManager] saveAchievementToReportLater:identifier percentComplete:percentComplete];
            }
        }
    }
}

- (void)saveScoreToReportLater:(GKScore *)score {
    NSData *scoreData = [NSKeyedArchiver archivedDataWithRootObject:score];
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableArray *savedScores = [plistDict objectForKey:@"SavedScores"];
    if(savedScores != nil) {
        [savedScores addObject:scoreData];
    }
    else {
        savedScores = [NSMutableArray arrayWithObject:scoreData];
    }
    [plistDict setObject:savedScores forKey:@"SavedScores"];
    NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
    [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
}

- (void)saveAchievementToReportLater:(NSString *)identifier percentComplete:(double)percentComplete {
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
    if(playerDict != nil) {
        NSMutableDictionary *savedAchievements = [playerDict objectForKey:@"SavedAchievements"];
        if(savedAchievements != nil) {
            double savedPercentCompleteValue = 0;
            NSNumber *savedPercentComplete = [savedAchievements objectForKey:identifier];
            if(savedPercentComplete != nil) {
                savedPercentCompleteValue = [savedPercentComplete doubleValue];
            }
            savedPercentComplete = [NSNumber numberWithDouble:percentComplete + savedPercentCompleteValue];
            [savedAchievements setObject:savedPercentComplete forKey:identifier];
        }
        else {
            savedAchievements = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:percentComplete], identifier, nil];
            [playerDict setObject:savedAchievements forKey:@"SavedAchievements"];
        }
    }
    else {
        NSMutableDictionary *savedAchievements = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:percentComplete], identifier, nil];
        playerDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:savedAchievements, @"SavedAchievements", nil];                    
    }
    [plistDict setObject:playerDict forKey:[[GameCenterManager sharedManager] localPlayerId]];
    NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
    [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];    
}

- (int)highScoreForLeaderboard:(NSString *)identifier {
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
    if(playerDict != nil) {
        NSNumber *savedHighScore = [playerDict objectForKey:identifier];
        if(savedHighScore != nil) {
            return [savedHighScore intValue];
        }
    }
    return 0;
}

- (NSDictionary *)highScoreForLeaderboards:(NSArray *)identifiers {
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
    NSMutableDictionary *highScores = [[NSMutableDictionary alloc] initWithCapacity:identifiers.count];
    for(NSString *identifier in identifiers) {
        if(playerDict != nil) {
            NSNumber *savedHighScore = [playerDict objectForKey:identifier];
            if(savedHighScore != nil) {
                [highScores setObject:[NSNumber numberWithInt:[savedHighScore intValue]] forKey:identifier];
                continue;
            }
        }
        [highScores setObject:[NSNumber numberWithInt:0] forKey:identifier];
    }
    
    NSDictionary *highScoreDict = [NSDictionary dictionaryWithDictionary:highScores];
    
    return highScoreDict;
}

- (double)progressForAchievement:(NSString *)identifier {
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
    if(playerDict != nil) {
        NSNumber *savedPercentComplete = [playerDict objectForKey:identifier];
        if(savedPercentComplete != nil) {
            return [savedPercentComplete doubleValue];
        }
    }
    return 0;
}

- (NSDictionary *)progressForAchievements:(NSArray *)identifiers {
    NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
    NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
    NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
    NSMutableDictionary *percent = [[NSMutableDictionary alloc] initWithCapacity:identifiers.count];
    for(NSString *identifier in identifiers) {
        if(playerDict != nil) {
            NSNumber *savedPercentComplete = [playerDict objectForKey:identifier];
            if(savedPercentComplete != nil) {
                [percent setObject:[NSNumber numberWithDouble:[savedPercentComplete doubleValue]] forKey:identifier];
                continue;
            }
        }
        [percent setObject:[NSNumber numberWithDouble:0] forKey:identifier];
    }
    
    NSDictionary *percentDict = [NSDictionary dictionaryWithDictionary:percent];
    
    return percentDict;
}

- (void)reportSavedScoresAndAchievements {    
    if([[GameCenterManager sharedManager] isInternetAvailable]) {
        GKScore *gkScore = nil;
        
        NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
        NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
        NSMutableArray *savedScores = [plistDict objectForKey:@"SavedScores"];
        if(savedScores != nil) {
            if(savedScores.count > 0) {
                gkScore = [NSKeyedUnarchiver unarchiveObjectWithData:[savedScores objectAtIndex:0]];
                [savedScores removeObjectAtIndex:0];
                [plistDict setObject:savedScores forKey:@"SavedScores"];
                NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
                [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
            }
        }
        
        if(gkScore != nil) {            
            [gkScore reportScoreWithCompletionHandler:^(NSError *error) {
                if(error == nil) {
                    // notify on screen
                    [[GKAchievementHandler defaultHandler] notifyAchievementTitle:@"New High Score"
                                                                       andMessage:[NSString stringWithFormat:@"%@ %" PRId64, gkScore.category, gkScore.value]];
                    
                    // notify reported score
                    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                          gkScore.category, @"category",
                                          [NSNumber numberWithLongLong:gkScore.value], @"score",
                                          nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerReportScoreNotification
                                                                        object:[GameCenterManager sharedManager]
                                                                      userInfo:dict];
                    
                    [[GameCenterManager sharedManager] reportSavedScoresAndAchievements];
                }
                else {
                    [[GameCenterManager sharedManager] saveScoreToReportLater:gkScore];
                }
            }];
        }
        else {
            if([GKLocalPlayer localPlayer].authenticated) {
                NSString *identifier = nil;
                double percentComplete = 0;
                
                NSData *gameCenterManagerData = [[NSData dataWithContentsOfFile:kGameCenterManagerDataPath] decryptedWithKey:kGameCenterManagerKey];
                NSMutableDictionary *plistDict = [NSKeyedUnarchiver unarchiveObjectWithData:gameCenterManagerData];
                NSMutableDictionary *playerDict = [plistDict objectForKey:[[GameCenterManager sharedManager] localPlayerId]];
                if(playerDict != nil) {
                    NSMutableDictionary *savedAchievements = [playerDict objectForKey:@"SavedAchievements"];
                    if(savedAchievements != nil) {
                        if(savedAchievements.count > 0) {
                            identifier = [[savedAchievements allKeys] objectAtIndex:0];
                            percentComplete = [[savedAchievements objectForKey:identifier] doubleValue];
                            [savedAchievements removeObjectForKey:identifier];
                            [playerDict setObject:savedAchievements forKey:@"SavedAchievements"];
                            [plistDict setObject:playerDict forKey:[[GameCenterManager sharedManager] localPlayerId]];
                            NSData *saveData = [[NSKeyedArchiver archivedDataWithRootObject:plistDict] encryptedWithKey:kGameCenterManagerKey];
                            [saveData writeToFile:kGameCenterManagerDataPath atomically:YES];
                        }
                    }
                }
                
                if(identifier != nil) {
                    GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:identifier];
                    achievement.percentComplete = percentComplete;
                    [achievement reportAchievementWithCompletionHandler:^(NSError *error) {
                        if(error == nil) {
                            // notify on screen
                            GKAchievementDescription *achievementDesc = [self getAchievementDescription:achievement.identifier];
                            if (achievementDesc) {
                                [[GKAchievementHandler defaultHandler] notifyAchievement:achievementDesc];
                            }
                            
                            // notify reported achievement
                            NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                                  achievement.identifier, @"category",
                                                  [NSNumber numberWithDouble:achievement.percentComplete], @"percent",
                                                  nil];
                            [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerReportAchievementNotification
                                                                                object:[GameCenterManager sharedManager]
                                                                              userInfo:dict];
                            
                            [[GameCenterManager sharedManager] reportSavedScoresAndAchievements];
                        }
                        else {
                            [[GameCenterManager sharedManager] saveAchievementToReportLater:achievement.identifier percentComplete:achievement.percentComplete]; 
                        }
                    }];
                }
            }
        }
    }
}

- (void)loadAchievementDescriptions
{
    NSLog(@"loading achievement descriptions");
    
    [GKAchievementDescription loadAchievementDescriptionsWithCompletionHandler:^(NSArray *achievementDesc, NSError *error)
     {
         _achievementDescriptions = [[NSMutableDictionary alloc] init];
         
         if (error != nil)
         {
             NSLog(@"unable to load achievements");
             return;
         }
         
         for (GKAchievementDescription *description in achievementDesc)
         {
             [_achievementDescriptions setObject:description forKey:description.identifier];
         }
         
         NSLog(@"achievement descriptions initialized: %d", _achievementDescriptions.count);
     }];
}

-(GKAchievementDescription*) getAchievementDescription:(NSString*)identifier
{
    GKAchievementDescription* description = [_achievementDescriptions objectForKey:identifier];
    return description;
}

- (void)resetAchievements {
    if([[GameCenterManager sharedManager] isGameCenterAvailable]) {
        [GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
            NSDictionary *dict = nil;
            if(error == nil) {
                dict = [NSDictionary dictionary];
            }
            else {
                dict = [NSDictionary dictionaryWithObject:error.localizedDescription forKey:@"error"];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerResetAchievementNotification
                                                                object:[GameCenterManager sharedManager]
                                                              userInfo:dict];
        }];
    }
}

- (NSString *)localPlayerId {
    if([[GameCenterManager sharedManager] isGameCenterAvailable]) {
        if([GKLocalPlayer localPlayer].authenticated) {
            return [GKLocalPlayer localPlayer].playerID;
        }
    }
    return @"UnknownPlayer";
}

- (BOOL)isInternetAvailable {
    Reachability *reachability = [Reachability reachabilityForInternetConnection];    
    NetworkStatus internetStatus = [reachability currentReachabilityStatus];
    if (internetStatus != NotReachable) {
        return YES;
    }
    return NO;
}

#pragma mark - Game Center / Leaderboard / Achievement Extension -
-(UIViewController*) getRootViewController
{
    return [UIApplication sharedApplication].keyWindow.rootViewController;
}

-(void) presentViewController:(UIViewController*)vc
{
    UIViewController* rootVC = [self getRootViewController];
    [rootVC presentModalViewController:vc animated:YES];
}

-(void) dismissModalViewController
{
    UIViewController* rootVC = [self getRootViewController];
    [rootVC dismissModalViewControllerAnimated:YES];
}

- (void)alertGamerCenterNotAvailable
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Game Center"
                                                    message:@"Game Center is not available."
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles: nil, nil];
    [alert show];
}

-(void) showGameCenter
{
    if (isGameCenterAvailable == NO)
    {
        [self alertGamerCenterNotAvailable];
        return;
    }
    
    if ([GKGameCenterViewController class])
    {
        GKGameCenterViewController *gameCenterController = [[GKGameCenterViewController alloc] init];
        if (gameCenterController != nil)
        {
            gameCenterController.gameCenterDelegate = self;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerShowGameCenterNotification
                                                                object:[GameCenterManager sharedManager]
                                                              userInfo:[NSDictionary dictionary]];
            
            [self presentViewController:gameCenterController];
        }
    }
    else
    {
        [self showLeaderboard];
    }
}

- (void)gameCenterViewControllerDidFinish:(GKGameCenterViewController *)gameCenterViewController
{
    [self dismissModalViewController];
}

-(void) showLeaderboard
{
    if (isGameCenterAvailable == NO)
    {
        [self alertGamerCenterNotAvailable];
        return;
    }
    
    GKLeaderboardViewController* leaderboardVC = [[GKLeaderboardViewController alloc] init];
    if (leaderboardVC != nil)
    {
        leaderboardVC.leaderboardDelegate = self;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerShowLeaderboardNotification
                                                            object:[GameCenterManager sharedManager]
                                                          userInfo:[NSDictionary dictionary]];
        
        [self presentViewController:leaderboardVC];
    }
}

-(void) showLeaderboardwithCategory:(NSString*)category timeScope:(int)tscope
{
    if (isGameCenterAvailable == NO)
    {
        [self alertGamerCenterNotAvailable];
        return;
    }
    
    GKLeaderboardViewController* leaderboardVC = [[GKLeaderboardViewController alloc] init];
    if (leaderboardVC != nil)
    {
        leaderboardVC.leaderboardDelegate = self;
        leaderboardVC.category = category;
        leaderboardVC.timeScope = tscope;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerShowLeaderboardNotification
                                                            object:[GameCenterManager sharedManager]
                                                          userInfo:[NSDictionary dictionary]];
        
        [self presentViewController:leaderboardVC];
    }
}

-(void) leaderboardViewControllerDidFinish:(GKLeaderboardViewController*)viewController
{
    [self dismissModalViewController];
}

-(void) showAchievements
{
    if (isGameCenterAvailable == NO)
    {
        [self alertGamerCenterNotAvailable];
        return;
    }
    
    GKAchievementViewController* achievementsVC = [[GKAchievementViewController alloc] init];
    if (achievementsVC != nil)
    {
        achievementsVC.achievementDelegate = self;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kGameCenterManagerShowAchievementsNotification
                                                            object:[GameCenterManager sharedManager]
                                                          userInfo:[NSDictionary dictionary]];
        
        [self presentViewController:achievementsVC];
    }
}

-(void) achievementViewControllerDidFinish:(GKAchievementViewController*)viewController
{
    [self dismissModalViewController];
}

@end