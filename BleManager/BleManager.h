//
//  BleManager.h
//
//  Created by larva on 2020/2/28.
//  Copyright © 2020 larva. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^ScanDevicesBlock)(NSArray <CBPeripheral *> *devices);
typedef void(^ConnectResultBlock)(CBPeripheral * _Nullable peripheral);
typedef void(^ReceiveDataBlock)(NSDictionary *data);
typedef void(^ErrorMsgBlock)(NSString *errorMsg);

@interface BleManager : NSObject

/// 检索回调
@property (copy, nonatomic) ScanDevicesBlock   scanDevicesBlock;
/// 接续回调
@property (copy, nonatomic) ConnectResultBlock connectResultBlock;
/// 接收回调
@property (copy, nonatomic) ReceiveDataBlock   receiveDataBlock;
/// 错误回调
@property (copy, nonatomic) ErrorMsgBlock      errorMsgBlock;
/// 最长接续时间，默认 5.0s
@property (assign, nonatomic) NSTimeInterval connectionDuration;

/// 初期化
+ (instancetype)sharedInstance;
- (instancetype)init __attribute__((unavailable("Use BleManager.sharedInstance")));
+ (instancetype)new  __attribute__((unavailable("Use BleManager.sharedInstance")));

/// 检索设备
- (void)scanPeripherals;

/// 停止检索
- (void)stopScan;

/// 连接设备
/// @param peripheral 蓝牙设备
- (void)connectPeripheral:(CBPeripheral *)peripheral;

/// 断开连接
/// @param peripheral 蓝牙设备
- (void)cancelPeripheralConnection:(CBPeripheral *)peripheral;

/// 写入数据
/// @param data 待写入的数据
- (void)writeValue:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
