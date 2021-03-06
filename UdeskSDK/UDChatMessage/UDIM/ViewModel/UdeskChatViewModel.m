//
//  UdeskChatViewModel.m
//  UdeskSDK
//
//  Created by Udesk on 16/1/19.
//  Copyright © 2016年 Udesk. All rights reserved.
//

#import "UdeskChatViewModel.h"
#import "UdeskTools.h"
#import "UdeskFoundationMacro.h"
#import "NSArray+UdeskSDK.h"
#import "UdeskAgentHttpData.h"
#import "UdeskReachability.h"
#import "UdeskManager.h"
#import "UdeskChatMessage.h"
#import "UdeskMessage+UdeskChatMessage.h"
#import "UdeskChatAlertController.h"
#import "UdeskTipsMessage.h"
#import "UdeskProductMessage.h"
#import "UdeskSDKConfig.h"
#import "UdeskChatSend.h"
#import "UdeskAgentSurvey.h"
#import "UdeskUtils.h"
#import "UdeskStructMessage.h"

@interface UdeskChatViewModel()<UDManagerDelegate,UdeskMessageDelegate,UdeskChatAlertDelegate>

/** 消息 */
@property (nonatomic, strong,readwrite) NSMutableArray           *messageArray;
/** 失败的消息 */
@property (nonatomic, strong,readwrite) NSMutableArray           *resendArray;
/** sdk后台配置 */
@property (nonatomic, strong          ) UdeskSetting             *sdkSetting;
/** 客服Model */
@property (nonatomic, strong          ) UdeskAgent               *agentModel;
/** 聊天弹窗 */
@property (nonatomic, strong          ) UdeskChatAlertController *chatAlert;
/** 网络状态检测 */
@property (nonatomic                  ) UdeskReachability        *reachability;
/** 网络切换 */
@property (nonatomic, assign          ) BOOL                     netWorkChange;
/** 黑名单提示语 */
@property (nonatomic, copy            ) NSString                 *blackedMessage;

@end

@implementation UdeskChatViewModel

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        self.messageArray = [NSMutableArray array];
        //聊天提示框
        self.chatAlert = [[UdeskChatAlertController alloc] init];
        self.chatAlert.delegate = self;
        
        //UdeskSDK代理
        [UdeskManager receiveUdeskDelegate:self];
        //获取db消息
        [self requestDataBaseMessageContent];
        //网络监测
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kUdeskReachabilityChangedNotification object:nil];
        self.reachability  = [UdeskReachability reachabilityWithHostName:@"www.baidu.com"];
        [self.reachability startNotifier];
    }
    return self;
}


//根据是否设置按后台配置
- (void)createCustomerWithSDKSetting:(UdeskSetting *)setting {

    if (setting) {

        self.sdkSetting = setting;
        
        if (setting.isWorktime.boolValue) {
            [self createCustomer];
        }
        else {
            UdeskAgent *agentModel = [[UdeskAgent alloc] init];
            agentModel.code = UDAgentStatusResultOffline;
            //回调客服信息到vc显示
            [self callbackAgentModel:agentModel];
            
            [self showAlertNotWorkTime];
        }
        
        return;
    }
    
    [self createCustomer];
}

- (void)showAlertNotWorkTime {

    if (self.sdkSetting) {
     
        if (self.sdkSetting.enableWebImFeedback.boolValue) {
#warning 这里以后需要做成用户在sdk端可自定义的
            NSString *no_reply_hint = getUDLocalizedString(@"udesk_alert_view_leave_msg");
            [self.chatAlert showAgentNotOnlineAlertWithMessage:no_reply_hint enableWebImFeedback:YES];
        }
        else {
            
            NSString *no_reply_hint = [NSString stringWithFormat:@"%@",self.sdkSetting.noReplyHint];
            if (!no_reply_hint || no_reply_hint.length <= 0) {
                no_reply_hint = getUDLocalizedString(@"udesk_alert_view_no_reply_hint");
            }
            [self.chatAlert showAgentNotOnlineAlertWithMessage:no_reply_hint enableWebImFeedback:NO];
        }
    }
    else {
        [self.chatAlert showAgentNotOnlineAlert];
    }
}

//创建用户
- (void)createCustomer {
    
    @udWeakify(self);
    //创建用户(为了保证sdk正常使用请不要删除使用UdeskManager的方法)
    [UdeskManager createServerCustomerCompletion:^(BOOL success, NSError *error) {
        
        if (success) {
            @udStrongify(self);
            //请求客服数据(为了保证sdk正常使用请不要删除使用UdeskManager的方法)
            [self requestAgentData];
        }
        else {
            
            if ([UdeskManager isBlacklisted]) {
                //客户在黑名单
                [self customerIsBlacklisted:error.userInfo[@"message"]];
            }
            else {
                NSLog(@"Udesk SDK初始化失败，请查看控制台LOG");
            }
        }        
    }];
}

//客户在黑名单
- (void)customerIsBlacklisted:(NSString *)message {
    
    _blackedMessage = message;
    //退出
    [UdeskManager setupCustomerOffline];
    
    UdeskAgent *agentModel = [[UdeskAgent alloc] init];
    agentModel.message = [UdeskTools isBlankString:message]?getUDLocalizedString(@"udesk_im_title_blocked_list"):message;
    agentModel.code = UDAgentStatusResultUnKnown;
    
    [self callbackAgentModel:agentModel];
    //显示客户黑名单提示
    [self.chatAlert showIsBlacklistedAlert:message];
}
//网络状态检测
- (void)reachabilityChanged:(NSNotification *)note
{
    
    UdeskReachability *curReach = [note object];
    UDNetworkStatus internetStatus = [curReach currentReachabilityStatus];
    
    @udWeakify(self)
    switch (internetStatus) {
        case UDReachableViaWiFi:
        case UDReachableViaWWAN:{
            
            @udStrongify(self);
            if (self.netWorkChange) {
                self.netWorkChange = NO;
                //请求客服数据
                [self requestAgentData];
            }
            break;
        }
            
        case UDNotReachable:{
            
            @udStrongify(self);
            self.netWorkChange = YES;
            self.agentModel.message = getUDLocalizedString(@"udesk_network_interrupt");
            self.agentModel.code = UDAgentStatusResultNotNetWork;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [self callbackAgentModel:self.agentModel];
            });
        }
            
        default:
            break;
    }
    
}

#pragma mark - 获取DB数据
- (void)requestDataBaseMessageContent {
    
    [UdeskManager getHistoryMessagesFromDatabaseWithMessageDate:[NSDate date] messagesNumber:20 result:^(NSArray *messagesArray) {
        
        if (messagesArray.count==20) {
            self.isShowRefresh = YES;
        }
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            if (messagesArray.count) {
                self.messageArray = [self convertToChatViewMessageWithUdeskMessages:messagesArray];
            }
            
            //咨询对象
            if ([UdeskSDKConfig sharedConfig].productDictionary) {
                UdeskProductMessage *productMessage = [[UdeskProductMessage alloc] initWithProductMessage:[UdeskSDKConfig sharedConfig].productDictionary];
                if (productMessage) {
                    productMessage.delegate = self;
                    [self.messageArray addObject:productMessage];
                }
            }
            //更新UI
            [self updateContent];
        });
        
    }];
    
}

#pragma mark - 加载更多DB消息
- (void)pullMoreDateBaseMessage {
    
    UdeskChatMessage *lastMessage = self.messageArray.firstObject;
    //根据最后列表最后一条消息的时间获取历史记录
    [UdeskManager getHistoryMessagesFromDatabaseWithMessageDate:lastMessage.date messagesNumber:20 result:^(NSArray *messagesArray) {
        
        if (messagesArray.count) {
            if (messagesArray.count>19) {
                self.isShowRefresh = YES;
            }
            else {
                self.isShowRefresh = NO;
            }
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                
                if (messagesArray.count) {
                    
                    NSRange range = NSMakeRange(0, [messagesArray count]);
                    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];
                    
                    NSArray *moreMessageArray = [self convertToChatViewMessageWithUdeskMessages:messagesArray];
                    if (moreMessageArray.count) {
                        [self.messageArray insertObjects:moreMessageArray atIndexes:indexSet];
                        //更新UI
                        [self updateContent];
                    }
                }
                
            });
        }
        else {
            //没有数据不展示下拉刷新按钮
            self.isShowRefresh = NO;
        }
    }];
    
}

//把UdeskMessage转换成UdeskChatMessage
- (NSMutableArray *)convertToChatViewMessageWithUdeskMessages:(NSArray *)messagesArray {
    
    NSMutableArray *toMessages = [[NSMutableArray alloc] init];
    
    if (messagesArray.count) {
        
        for (int i = 0; i<messagesArray.count; i++) {
            
            UdeskMessage *message = messagesArray[i];
            
            if(i==0 || i == messagesArray.count-1){
                
                id chatMessage = [self addMessage:message withDisplayTimestamp:YES];
                if (chatMessage) {
                    [toMessages addObject:chatMessage];
                }
            }
            else{
                
                UdeskMessage *newMessage = [messagesArray objectAtIndexCheck:i];
                UdeskMessage *previousMessage=[messagesArray objectAtIndexCheck:i-1];
                NSInteger interval=[newMessage.timestamp timeIntervalSinceDate:previousMessage.timestamp];
                if(interval>60*3){
                    
                    id chatMessage = [self addMessage:message withDisplayTimestamp:YES];
                    if (chatMessage) {
                        [toMessages addObject:chatMessage];
                    }
                }
                else{
                    
                    id chatMessage = [self addMessage:message withDisplayTimestamp:NO];
                    if (chatMessage) {
                        [toMessages addObject:chatMessage];
                    }
                }
            }
        }
    }
    
    return toMessages;
}

- (id)addMessage:(UdeskMessage *)message withDisplayTimestamp:(BOOL)displayTimestamp {
    
    if (message.messageType == UDMessageContentTypeRedirect) {
        UdeskTipsMessage *tipsMessage = [[UdeskTipsMessage alloc] initWithUdeskMessage:message];
        if (tipsMessage) {
            return tipsMessage;
        }
    }
    else if (message.messageType == UDMessageContentTypeStruct) {
        UdeskStructMessage *strucrtMessage = [[UdeskStructMessage alloc] initWithUdeskMessage:message];
        strucrtMessage.delegate = self;
        if (strucrtMessage) {
            return strucrtMessage;
        }
    }
    else {
        UdeskChatMessage *chatMessage = [self chatMessageWithModel:message withDisplayTimestamp:displayTimestamp];
        if (chatMessage) {
            return chatMessage;
        }
    }
    return nil;
}

//检查是否需要显示时间
- (BOOL)addMessageDateAtLastWithNowDate:(NSDate *)date {
    
    if (self.messageArray.count) {
        
        UdeskBaseMessage *message = self.messageArray.lastObject;
        NSDate *date = message.date;
        
        NSInteger interval = [date timeIntervalSinceDate:date];
        if(interval>60*3){
            return YES;
        }else{
            return NO;
        }
    }
    else {
        return YES;
    }
}
//UdeskMessage转换成UdeskChatMessage
- (UdeskChatMessage *)chatMessageWithModel:(UdeskMessage *)message withDisplayTimestamp:(BOOL)displayTimestamp {
    
    UdeskChatMessage *chatMessage = [[UdeskChatMessage alloc] initWithModel:message withDisplayTimestamp:displayTimestamp];
    chatMessage.delegate = self;
    
    return chatMessage;
}

#pragma mark - UdeskChatMessageDelegate
- (void)didUpdateCellDataWithMessageId:(NSString *)messageId {
    
    if ([UdeskTools isBlankString:messageId]) {
        return;
    }
    
    //获取又更新的cell的index
    NSInteger index = [self getIndexOfCellWithMessageId:messageId];
    if (index < 0) {
        return;
    }
    [self updateCellWithIndex:index];
}

- (NSInteger)getIndexOfCellWithMessageId:(NSString *)messageId {
    
    for (NSInteger index=0; index<self.messageArray.count; index++) {
        
        UdeskBaseMessage *message = [self.messageArray objectAtIndexCheck:index];
        if ([message.messageId isEqualToString:messageId]) {
            return index;
        }
    }
    return -1;
}

- (void)updateCellWithIndex:(NSInteger)index {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    if (self.delegate) {
        if ([self.delegate respondsToSelector:@selector(didUpdateCellModelWithIndexPath:)]) {
            [self.delegate didUpdateCellModelWithIndexPath:indexPath];
        }
    }
}

#pragma mark - 根据是否有客服id和客服组id请求客服数据
- (void)requestAgentData {
    
    NSString *agentId = [UdeskSDKConfig sharedConfig].scheduledAgentId;
    NSString *groupId = [UdeskSDKConfig sharedConfig].scheduledGroupId;
    
    @udWeakify(self);
    //获取客服信息
    if (![UdeskTools isBlankString:agentId]) {
        //获取指定客服ID的客服信息
        [[UdeskAgentHttpData sharedAgentHttpData] scheduledAgentId:agentId completion:^(UdeskAgent *agentModel, NSError *error) {
            @udStrongify(self);
            [self distributionAgent:agentModel];
        }];
    }
    else if (![UdeskTools isBlankString:groupId]) {
        //获取指定客服组ID的客服组信息
        [[UdeskAgentHttpData sharedAgentHttpData] scheduledGroupId:groupId completion:^(UdeskAgent *agentModel, NSError *error) {
            @udStrongify(self);
            [self distributionAgent:agentModel];
        }];
    }
    else {
        
        //根据管理员后台配置选择客服
        [[UdeskAgentHttpData sharedAgentHttpData] requestRandomAgent:^(UdeskAgent *agentModel, NSError *error) {
            @udStrongify(self);
            [self distributionAgent:agentModel];
        }];
    }
    
}

//获取分配客服
- (void)distributionAgent:(UdeskAgent *)agentModel {
    
    //回调客服信息到vc显示
    [self callbackAgentModel:agentModel];
    
    if (agentModel.code != UDAgentStatusResultOnline) {
        
        if (self.isNotShowAlert) {
            return;
        }
        [self showAlertViewWithAgent];
        return;
    }
    //只有客服在线才发送消息
    if (agentModel.code == UDAgentStatusResultOnline) {
        
        if ([UdeskSDKConfig sharedConfig].productDictionary) {
            UdeskMessage *productMessage = [[UdeskMessage alloc] initWithProductMessage:[UdeskSDKConfig sharedConfig].productDictionary];
            [UdeskManager sendMessage:productMessage completion:nil];
        }
    }
}

//回调客服信息到vc显示
- (void)callbackAgentModel:(UdeskAgent *)agentModel {
    
    if (self.delegate) {
        if ([self.delegate respondsToSelector:@selector(didFetchAgentModel:)]) {
            [self.delegate didFetchAgentModel:agentModel];
        }
    }
    self.agentModel = agentModel;
}
#pragma mark - UdeskChatAlertDelegate
//点击了发送表单
- (void)didSelectSendTicket {
    
    if (self.delegate) {
        if ([self.delegate respondsToSelector:@selector(didSelectSendTicket)]) {
            [self.delegate didSelectSendTicket];
        }
    }
}
//点击了黑名单确定
- (void)didSelectBlacklistedAlertViewOkButton {
    
    if (self.delegate) {
        if ([self.delegate respondsToSelector:@selector(didSelectBlacklistedAlertViewOkButton)]) {
            [self.delegate didSelectBlacklistedAlertViewOkButton];
        }
    }
}

#pragma mark - UDManagerDelegate
- (void)didReceiveMessages:(UdeskMessage *)message {
    
    if ([UdeskTools isBlankString:message.content]) {
        return;
    }
    
    BOOL displayTimestamp = [self addMessageDateAtLastWithNowDate:[NSDate date]];
    
    if (message.messageType == UDMessageContentTypeRedirect) {
        UdeskTipsMessage *tipsMessage = [[UdeskTipsMessage alloc] initWithUdeskMessage:message];
        if (tipsMessage) {
            [self.messageArray addObject:tipsMessage];
        }
    }
    else if (message.messageType == UDMessageContentTypeStruct) {
        UdeskStructMessage *structMessage = [[UdeskStructMessage alloc] initWithUdeskMessage:message];
        structMessage.delegate = self;
        if (structMessage) {
            [self.messageArray addObject:structMessage];
        }
    }
    else {
        UdeskChatMessage *chatMessage = [self chatMessageWithModel:message withDisplayTimestamp:displayTimestamp];
        if (chatMessage) {
            [self.messageArray addObject:chatMessage];
        }
    }
    
    [self updateContent];
}

//接受到转接
- (void)didReceiveRedirect:(UdeskAgent *)agent {
    
    [self callbackAgentModel:agent];
}

//接收客服状态
- (void)didReceivePresence:(NSDictionary *)presence {
    
    NSString *statusType = [presence objectForKey:@"type"];
    UDAgentStatusType agentCode;
    NSString  *agentMessage = @"unavailable";
    if([statusType isEqualToString:@"over"]) {

        [[NSNotificationCenter defaultCenter] postNotificationName:@"agentOver" object:nil];

        agentCode = UDAgentConversationOver;
        agentMessage = getUDLocalizedString(@"udesk_chat_end");
    }
    else if ([statusType isEqualToString:@"available"]) {
        
        agentCode = UDAgentStatusResultOnline;
        agentMessage = [NSString stringWithFormat:@"%@ %@ %@",getUDLocalizedString(@"udesk_agent"),self.agentModel.nick,getUDLocalizedString(@"udesk_online")];
        
    }
    else if ([statusType isEqualToString:@"unavailable"]) {
        
        agentCode = UDAgentStatusResultOffline;
        agentMessage = [NSString stringWithFormat:@"%@ %@ %@",getUDLocalizedString(@"udesk_agent"),self.agentModel.nick,getUDLocalizedString(@"udesk_offline")];
    }
    
    
    //与上次不同的code才抛给vc
    if (self.agentModel.code != agentCode) {
        self.agentModel.code = agentCode;
        self.agentModel.message = agentMessage;
        
        if (self.delegate) {
            if ([self.delegate respondsToSelector:@selector(didReceiveAgentPresence:)]) {
                [self.delegate didReceiveAgentPresence:self.agentModel];
            }
        }
    }
}

//接收客服发送的满意度调查
- (void)didReceiveSurveyWithAgentId:(NSString *)agentId {
    
    if ([UdeskTools isBlankString:agentId]) {
        return;
    }
    [UdeskAgentSurvey.store showAgentSurveyAlertViewWithAgentId:agentId completion:^{
        
        //评价提交成功Alert
        if (self.delegate) {
            if ([self.delegate respondsToSelector:@selector(didSurveyCompletion:)]) {
                [self.delegate didSurveyCompletion:getUDLocalizedString(@"udesk_top_view_thanks_evaluation")];
            }
        }
    }];
}
#pragma mark - 发送文字消息
- (void)sendTextMessage:(NSString *)text
             completion:(void(^)(UdeskMessage *message,BOOL sendStatus))completion {
    
    if (_agentModel.code != UDAgentStatusResultOnline) {
        
        [self showAlertViewWithAgent];
        return;
    }
    
    if ([UdeskTools isBlankString:text]) {
        [self.chatAlert showAlertWithMessage:getUDLocalizedString(@"udesk_no_send_empty")];
        return;
    }
    //是否需要显示时间
    BOOL displayTimestamp = [self addMessageDateAtLastWithNowDate:[NSDate date]];
    
    UdeskChatMessage *chatMessage = [UdeskChatSend sendTextMessage:text displayTimestamp:displayTimestamp completion:completion];
    chatMessage.delegate = self;
    if (chatMessage) {
        [self.messageArray addObject:chatMessage];
    }
    //通知刷新UI
    [self updateContent];
}

#pragma mark - 发送图片消息
- (void)sendImageMessage:(UIImage *)image
              completion:(void(^)(UdeskMessage *message,BOOL sendStatus))completion {
    
    if (_agentModel.code != UDAgentStatusResultOnline) {
        
        [self showAlertViewWithAgent];
        return;
    }
    //是否需要显示时间
    BOOL displayTimestamp = [self addMessageDateAtLastWithNowDate:[NSDate date]];
    
    if (image) {
        UdeskChatMessage *chatMessage = [UdeskChatSend sendImageMessage:image displayTimestamp:displayTimestamp completion:completion];
        chatMessage.delegate = self;
        if (chatMessage) {
            [self.messageArray addObject:chatMessage];
        }
        //通知刷新UI
        [self updateContent];
    }
}

#pragma mark - 发送语音消息
- (void)sendAudioMessage:(NSString *)voicePath
           audioDuration:(NSString *)audioDuration
              completion:(void (^)(UdeskMessage *, BOOL sendStatus))comletion {
    
    if (_agentModel.code != UDAgentStatusResultOnline) {
        
        [self showAlertViewWithAgent];
        return;
    }
    //是否需要显示时间
    BOOL displayTimestamp = [self addMessageDateAtLastWithNowDate:[NSDate date]];
    
    if ([UdeskTools isBlankString:voicePath]) {
        return;
    }
    
    UdeskChatMessage *chatMessage = [UdeskChatSend sendAudioMessage:voicePath audioDuration:audioDuration displayTimestamp:displayTimestamp completion:comletion];
    chatMessage.delegate = self;
    if (chatMessage) {
        [self.messageArray addObject:chatMessage];
    }
    //通知刷新UI
    [self updateContent];
}

#pragma mark - 点击功能栏弹出相应Alert
- (void)clickInputViewShowAlertView {
    
    if (self.agentModel.code == UDAgentConversationOver) {
        [self createCustomer];
    }
    
    if ([UdeskManager isBlacklisted]) {
        //黑名单用户
        [self.chatAlert showIsBlacklistedAlert:self.blackedMessage];
    }
    else {
        
        [self showAlertViewWithAgent];
    }
}

//根据客服code展示alertview
- (void)showAlertViewWithAgent {
    
    if (self.sdkSetting) {
        
        NSString *no_reply_hint = [NSString stringWithFormat:@"%@",self.sdkSetting.noReplyHint];
        if(self.agentModel.code == UDAgentStatusResultQueue) {
            no_reply_hint = self.agentModel.message;
        }
        
        //开启留言
        if (self.sdkSetting.enableWebImFeedback.boolValue) {
            
#warning 这里以后需要做成用户在sdk端可自定义的
            if (self.agentModel.code == UDAgentStatusResultOffline) {
                no_reply_hint = getUDLocalizedString(@"udesk_alert_view_leave_msg");
            }
            
            [self.chatAlert showChatAlertViewWithCode:self.agentModel.code andMessage:no_reply_hint enableWebImFeedback:YES];
            return;
        }
        
        //关闭留言
        if (self.agentModel.code == UDAgentStatusResultOffline) {
            if (!no_reply_hint || no_reply_hint.length <= 0) {
                no_reply_hint = getUDLocalizedString(@"udesk_alert_view_no_reply_hint");
            }
        }
        
        [self.chatAlert showChatAlertViewWithCode:self.agentModel.code andMessage:no_reply_hint enableWebImFeedback:NO];
        
        return;
    }
    
    [self.chatAlert showChatAlertViewWithCode:self.agentModel.code andMessage:self.agentModel.message enableWebImFeedback:YES];
}


#pragma mark - 更新消息内容
- (void)updateContent {
    
    if (self.delegate) {
        if ([self.delegate respondsToSelector:@selector(reloadChatTableView)]) {
            [self.delegate reloadChatTableView];
        }
    }
}

#pragma mark - 重发失败的消息
- (void)resendFailedMessage:(void(^)(UdeskMessage *failedMessage,BOOL sendStatus))completion {
    
    [UdeskChatSend resendFailedMessage:self.resendArray completion:completion];
}

//失败的消息数组
- (NSMutableArray *)resendArray {
    
    if (!_resendArray) {
        _resendArray = [NSMutableArray array];
    }
    return _resendArray;
}
//添加失败的消息
- (void)addResendMessageToArray:(UdeskMessage *)message {
    
    if (message) {
        [self.resendArray addObject:message];
    }
}
//删除失败的消息
- (void)removeResendMessageInArray:(UdeskMessage *)message {
    
    if (message) {
        [self.resendArray removeObject:message];
    }
}

- (NSInteger)numberOfItems {
    
    return [self.messageArray count];
}

- (id)objectAtIndexPath:(NSInteger)row {
    
    return [self.messageArray objectAtIndexCheck:row];
}

- (void)dealloc
{
    NSLog(@"%@销毁了",[self class]);
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kUdeskReachabilityChangedNotification object:nil];
}

@end
